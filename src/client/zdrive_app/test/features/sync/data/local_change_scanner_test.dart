import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:zdrive_app/features/files/domain/file_item.dart';
import 'package:zdrive_app/features/files/domain/file_repository.dart';
import 'package:zdrive_app/features/sync/data/device_registration_service.dart';
import 'package:zdrive_app/features/sync/data/local_change_scanner.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_entry.dart';
import 'package:zdrive_app/features/sync/domain/sync_progress.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_repository.dart';

class MockSyncMirrorRepository extends Mock implements SyncMirrorRepository {}

class MockFileRepository extends Mock implements FileRepository {}

class MockDeviceRegistrationService extends Mock implements DeviceRegistrationService {}

class FakeSyncMirrorEntry extends Fake implements SyncMirrorEntry {}

/// Wires [mock]'s getChildrenUnder/upsert/deleteByServerId/getCursor/commit
/// to one mutable row list, so a test sees exactly what the scanner's own
/// mirror calls left behind — not a hand-picked "after" snapshot the test
/// re-stubs itself, which would hide a regression where the scanner forgets
/// to write a row at all. [commit] here mirrors
/// SqfliteSyncMirrorRepository.commit's own semantics (rePath, then
/// upserts, then deletes, then deleteUnderPath) closely enough for that
/// purpose, without being a second implementation of its SQL.
class _StatefulMirror {
  final List<SyncMirrorEntry> rows;

  _StatefulMirror(MockSyncMirrorRepository mock, List<SyncMirrorEntry> initialRows, {int cursor = 7})
      : rows = List.of(initialRows) {
    when(() => mock.getChildrenUnder(any())).thenAnswer((inv) async {
      final dirPath = inv.positionalArguments[0] as String;
      final prefix =
          dirPath.endsWith(Platform.pathSeparator) ? dirPath : '$dirPath${Platform.pathSeparator}';
      return rows.where((e) => e.localPath.startsWith(prefix)).toList();
    });
    when(() => mock.upsert(any())).thenAnswer((inv) async {
      final entry = inv.positionalArguments[0] as SyncMirrorEntry;
      rows.removeWhere((e) => e.serverId == entry.serverId);
      rows.add(entry);
    });
    when(() => mock.deleteByServerId(any())).thenAnswer((inv) async {
      final serverId = inv.positionalArguments[0] as String;
      rows.removeWhere((e) => e.serverId == serverId);
    });
    when(() => mock.getCursor(any())).thenAnswer((_) async => cursor);
    when(() => mock.commit(
          upserts: any(named: 'upserts'),
          deleteServerIds: any(named: 'deleteServerIds'),
          deleteUnderPath: any(named: 'deleteUnderPath'),
          rePath: any(named: 'rePath'),
        )).thenAnswer((inv) async {
      final upserts = inv.namedArguments[#upserts] as List<SyncMirrorEntry>? ?? const [];
      final deleteServerIds = inv.namedArguments[#deleteServerIds] as List<String>? ?? const [];
      final deleteUnderPath = inv.namedArguments[#deleteUnderPath] as String?;
      final rePath = inv.namedArguments[#rePath] as ({String from, String to})?;

      if (rePath != null) {
        final prefix =
            rePath.from.endsWith(Platform.pathSeparator) ? rePath.from : '${rePath.from}${Platform.pathSeparator}';
        for (var i = 0; i < rows.length; i++) {
          if (rows[i].localPath.startsWith(prefix)) {
            rows[i] = _reparented(rows[i], p.join(rePath.to, rows[i].localPath.substring(prefix.length)));
          }
        }
      }
      for (final entry in upserts) {
        rows.removeWhere((e) => e.serverId == entry.serverId);
        rows.add(entry);
      }
      for (final serverId in deleteServerIds) {
        rows.removeWhere((e) => e.serverId == serverId);
      }
      if (deleteUnderPath != null) {
        final prefix = deleteUnderPath.endsWith(Platform.pathSeparator)
            ? deleteUnderPath
            : '$deleteUnderPath${Platform.pathSeparator}';
        rows.removeWhere((e) => e.localPath.startsWith(prefix));
      }
    });
  }

  SyncMirrorEntry _reparented(SyncMirrorEntry e, String newPath) => SyncMirrorEntry(
        serverId: e.serverId,
        localPath: newPath,
        isFolder: e.isFolder,
        sizeBytes: e.sizeBytes,
        contentHash: e.contentHash,
        updatedAt: e.updatedAt,
        syncedAt: e.syncedAt,
        downloaded: e.downloaded,
      );

  SyncMirrorEntry? row(String serverId) => rows.where((e) => e.serverId == serverId).firstOrNull;
}

/// Whether this host's filesystem folds case (Windows, default macOS) —
/// computed once, synchronously, before any test registers, by creating
/// `probe.txt` and checking whether `PROBE.TXT` resolves to the same file
/// (PR #14 review round 4, R4-4). A real a.txt/A.txt collision test only
/// means anything on a case-sensitive host (Linux CI); on this host it is
/// skipped instead of silently passing for the wrong reason.
bool _probeCaseInsensitiveHost() {
  final probeDir = Directory.systemTemp.createTempSync('case_probe_');
  try {
    File(p.join(probeDir.path, 'probe.txt')).writeAsStringSync('x');
    return File(p.join(probeDir.path, 'PROBE.TXT')).existsSync();
  } finally {
    probeDir.deleteSync(recursive: true);
  }
}

final _isCaseInsensitiveHost = _probeCaseInsensitiveHost();

void main() {
  late MockSyncMirrorRepository mockMirror;
  late MockFileRepository mockFileRepository;
  late MockDeviceRegistrationService mockDeviceRegistration;
  late LocalChangeScanner scanner;
  late Directory tempDir;

  final now = DateTime.utc(2026, 1, 1);
  // Comfortably before "now" — used as syncedAt for a mirror entry that
  // should read as "not recently touched" against a just-written test file.
  final past = now.subtract(const Duration(days: 1));
  // Comfortably after "now" — used as syncedAt when a test needs a file's
  // real (just-written) mtime to read as *not* after syncedAt, regardless
  // of clock/filesystem timestamp granularity.
  final future = DateTime.now().add(const Duration(days: 1));

  String hashOf(String content) => sha256.convert(utf8.encode(content)).toString();
  String hashOfBytes(List<int> bytes) => sha256.convert(bytes).toString();

  DioException dioError(int statusCode) => DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(requestOptions: RequestOptions(path: '/x'), statusCode: statusCode),
        type: DioExceptionType.badResponse,
      );

  LocalChangeScanner scannerWith({required bool isWindows}) => LocalChangeScanner(
        mockMirror,
        mockFileRepository,
        mockDeviceRegistration,
        isWindows: isWindows,
      );

  _StatefulMirror stateful(List<SyncMirrorEntry> initialRows) => _StatefulMirror(mockMirror, initialRows);

  setUpAll(() {
    registerFallbackValue(FakeSyncMirrorEntry());
    registerFallbackValue(<SyncMirrorEntry>[]);
    registerFallbackValue(<String>[]);
    registerFallbackValue(const Stream<List<int>>.empty());
    registerFallbackValue(CancelToken());
    registerFallbackValue((String _) async {});
  });

  setUp(() {
    mockMirror = MockSyncMirrorRepository();
    mockFileRepository = MockFileRepository();
    mockDeviceRegistration = MockDeviceRegistrationService();
    scanner = scannerWith(isWindows: false);
    tempDir = Directory.systemTemp.createTempSync('local_change_scanner_test_');

    when(() => mockDeviceRegistration.ensureRegistered()).thenAnswer((_) async => 'dev-1');
    when(() => mockDeviceRegistration.localDeviceId()).thenAnswer((_) async => 'dev-1');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('file deleted during upload is removed remotely in the same scan', () async {
    final file = File(p.join(tempDir.path, 'deleted.mp4'))..writeAsStringSync('video');
    final mirror = stateful([]);
    when(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(),
      originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated'))).thenAnswer((_) async {
        await file.delete();
        return 'deleted-upload';
      });
    when(() => mockFileRepository.deleteFile('deleted-upload',
      originDeviceId: any(named: 'originDeviceId'))).thenAnswer((_) async {});

    await scanner.scanOnce(tempDir.path);

    verify(() => mockFileRepository.deleteFile('deleted-upload',
      originDeviceId: 'dev-1')).called(1);
    expect(mirror.row('deleted-upload'), isNull);
  });

  test('deleting an active upload cancels transport and cleans its durable node', () async {
    final file = File(p.join(tempDir.path, 'active.mp4'))..writeAsStringSync('video');
    final mirror = stateful([]);
    final started = Completer<void>();
    when(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(),
      originDeviceId: any(named: 'originDeviceId'),
      cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')))
      .thenAnswer((inv) async {
        final created = inv.namedArguments[#onNodeCreated] as Future<void> Function(String);
        await created('active');
        expect(mirror.row('active')!.contentHash, isNull);
        started.complete();
        final token = inv.namedArguments[#cancelToken] as CancelToken;
        throw await token.whenCancel;
      });
    when(() => mockFileRepository.deleteFile('active', originDeviceId: 'dev-1'))
      .thenAnswer((_) async {});
    final run = scanner.scanOnce(tempDir.path);
    await started.future.timeout(const Duration(seconds: 5));
    await file.delete();
    await run.timeout(const Duration(seconds: 5));
    verify(() => mockFileRepository.deleteFile('active', originDeviceId: 'dev-1')).called(1);
    expect(mirror.rows, isEmpty);
  });

  test('failed cleanup remains durable and retries after scanner restart', () async {
    final file = File(p.join(tempDir.path, 'retry-delete.mp4'))..writeAsStringSync('video');
    final mirror = stateful([]);
    when(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(),
      originDeviceId: any(named: 'originDeviceId'),
      cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')))
      .thenAnswer((inv) async {
        await (inv.namedArguments[#onNodeCreated] as Future<void> Function(String))('retry-delete');
        await file.delete();
        (inv.namedArguments[#cancelToken] as CancelToken).cancel();
        throw (inv.namedArguments[#cancelToken] as CancelToken).cancelError!;
      });
    when(() => mockFileRepository.deleteFile('retry-delete', originDeviceId: 'dev-1'))
      .thenThrow(DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionError));
    await scanner.scanOnce(tempDir.path);
    expect(mirror.row('retry-delete'), isNotNull);
    when(() => mockFileRepository.deleteFile('retry-delete', originDeviceId: 'dev-1'))
      .thenAnswer((_) async {});
    await scannerWith(isWindows: false).scanOnce(tempDir.path);
    expect(mirror.rows, isEmpty);
  });

  test('restart retries a persisted unfinished upload even with unchanged mtime', () async {
    final file = File(p.join(tempDir.path, 'pending.mp4'))..writeAsStringSync('video');
    final mirror = stateful([
      SyncMirrorEntry(serverId: 'pending', localPath: file.path, isFolder: false,
        sizeBytes: 5, updatedAt: past, syncedAt: future),
    ]);
    when(() => mockFileRepository.uploadNewVersion('pending', 'pending.mp4', any(), 5,
      originDeviceId: 'dev-1', cancelToken: any(named: 'cancelToken'),
      onProgress: any(named: 'onProgress'))).thenAnswer((_) async {});
    expect(await scannerWith(isWindows: false).scanOnce(tempDir.path), 1);
    expect(mirror.row('pending')!.contentHash, hashOf('video'));
  });

  test('restart deletes persisted unfinished upload when its local file is gone', () async {
    final mirror = stateful([
      SyncMirrorEntry(serverId: 'pending', localPath: p.join(tempDir.path, 'gone.mp4'),
        isFolder: false, updatedAt: past, syncedAt: past),
    ]);
    when(() => mockFileRepository.deleteFile('pending', originDeviceId: 'dev-1'))
      .thenAnswer((_) async {});
    expect(await scannerWith(isWindows: false).scanOnce(tempDir.path), 1);
    expect(mirror.rows, isEmpty);
  });

  test('unchanged content advances the check timestamp beyond the precision overlap', () async {
    final file = File(p.join(tempDir.path, 'same.txt'))..writeAsStringSync('same');
    await file.setLastModified(DateTime.now().subtract(const Duration(seconds: 10)));
    final mirror = stateful([
      SyncMirrorEntry(serverId: 'same', localPath: file.path, isFolder: false,
        sizeBytes: 4, contentHash: hashOf('same'), updatedAt: past, syncedAt: past),
    ]);
    expect(await scanner.scanOnce(tempDir.path), 0);
    final checkedAt = mirror.row('same')!.syncedAt;
    expect(checkedAt.isAfter((await file.stat()).modified), isTrue);
    expect(await scanner.scanOnce(tempDir.path), 0);
    expect(mirror.row('same')!.syncedAt, checkedAt); // Stat prefilter now skips hashing.
  });

  test('upload snapshot matches mirror despite edits before and during transfer', () async {
    final changed = File(p.join(tempDir.path, 'changed.txt'))..writeAsStringSync('1111');
    File(p.join(tempDir.path, 'new.txt')).writeAsStringSync('new');
    final mirror = stateful([
      SyncMirrorEntry(serverId: 'changed', localPath: changed.path, isFolder: false,
        sizeBytes: 4, contentHash: hashOf('0000'), updatedAt: past, syncedAt: past),
    ]);
    when(() => mockFileRepository.uploadFile(any(), 'new.txt', any(), 3, any(),
      originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated'))).thenAnswer((_) async {
        // Existing-file prehash has finished, but its upload has not begun.
        await changed.writeAsString('2222');
        return 'new';
      });
    final uploaded = <String>[];
    when(() => mockFileRepository.uploadNewVersion('changed', 'changed.txt', any(), 4,
      originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'))).thenAnswer((inv) async {
        final stream = inv.positionalArguments[2] as Stream<List<int>>;
        if (uploaded.isEmpty) {
          // The transfer must keep reading its snapshot, including if the
          // live file is replaced before the stream is even consumed.
          await changed.writeAsString('3333');
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          await changed.setLastModified(DateTime.fromMillisecondsSinceEpoch(nowMs ~/ 2000 * 2000));
        }
        uploaded.add(utf8.decode(await stream.expand((chunk) => chunk).toList()));
      });
    expect(await scanner.scanOnce(tempDir.path), 2);
    expect(uploaded, ['2222']);
    expect(mirror.row('changed')!.contentHash, hashOf('2222'));
    expect(mirror.row('changed')!.sizeBytes, 4);
    expect(mirror.row('changed')!.localPath, changed.path);
    expect((await changed.stat()).modified.isAfter(mirror.row('changed')!.syncedAt), isTrue);
    expect(await scanner.scanOnce(tempDir.path), 1);
    expect(uploaded, ['2222', '3333']);
    expect(mirror.row('changed')!.contentHash, hashOf('3333'));
  });

  test('backed-off file remains visible as a failure without retrying upload', () async {
    final file = File(p.join(tempDir.path, 'retry.txt'))..writeAsStringSync('retry');
    stateful([]);
    scanner.debugBackOff(file.path);
    final snapshots = <SyncProgress>[];
    expect(await scanner.scanOnce(tempDir.path, progress: SyncProgressTracker(snapshots.add)), 0);
    expect(snapshots.any((s) => s.failedFiles > 0), isTrue);
    expect(snapshots.any((s) => s.activeFiles.any((f) => f.path == syncPathKey(file.path))), isTrue);
    verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(),
      originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')));
  });

  test('folder creation failure is reported by this run tracker', () async {
    final dir = Directory(p.join(tempDir.path, 'folder'))..createSync();
    stateful([]);
    when(() => mockFileRepository.createFolder(any(), 'folder', originDeviceId: any(named: 'originDeviceId')))
      .thenThrow(StateError('folder failed'));
    final snapshots = <SyncProgress>[];
    expect(await scanner.scanOnce(tempDir.path, progress: SyncProgressTracker(snapshots.add)), 0);
    expect(snapshots.any((s) => s.failedFiles > 0), isTrue);
    expect(snapshots.any((s) => s.activeFiles.any((f) => f.path == dir.path)), isTrue);
  });

  test('parallel uploads cap concurrency and drain after an error before deleting', () async {
    for (var i = 0; i < 5; i++) {
      File(p.join(tempDir.path, '$i.txt')).writeAsStringSync('new-$i');
    }
    final mirror = stateful([
      SyncMirrorEntry(serverId: 'missing', localPath: p.join(tempDir.path, 'gone.txt'),
        isFolder: false, sizeBytes: 100, contentHash: 'unrelated', updatedAt: past, syncedAt: past),
    ]);
    final startedThree = Completer<void>();
    final release = Completer<void>();
    var active = 0;
    var peak = 0;
    var started = 0;
    var scanCompleted = false;
    var deleted = false;
    final snapshots = <SyncProgress>[];
    when(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(),
      originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated'))).thenAnswer((inv) async {
      active++;
      started++;
      if (active > peak) peak = active;
      if (started == 3) startedThree.complete();
      await release.future;
      active--;
      final name = inv.positionalArguments[1] as String;
      if (name == '0.txt') throw StateError('upload failed');
      return name;
    });
    when(() => mockFileRepository.deleteFile('missing', originDeviceId: any(named: 'originDeviceId')))
      .thenAnswer((_) async { expect(active, 0); deleted = true; });
    final scan = scanner.scanOnce(tempDir.path, progress: SyncProgressTracker(snapshots.add))
      .then((value) { scanCompleted = true; return value; });
    await startedThree.future.timeout(const Duration(seconds: 10));
    expect(active, 3);
    expect(started, 3);
    expect(scanCompleted, isFalse);
    expect(deleted, isFalse);
    release.complete();
    expect(await scan, 5); // Four uploads and one deletion.
    expect(peak, 3);
    expect(active, 0);
    expect(started, 5);
    expect(mirror.rows.length, 4);
    final uploaded = snapshots.lastWhere((s) => s.phase == SyncPhase.uploading);
    expect(uploaded.completedFiles, 4);
    expect(uploaded.failedFiles, 1);
    expect(uploaded.activeFiles, isEmpty);
    expect(deleted, isTrue);
  });

  test('new file at root: uploads tagged with this device\'s id, commits '
      'the mirror', () async {
    final file = File(p.join(tempDir.path, 'new.txt'))..writeAsStringSync('hello');
    final mirror = stateful([]);
    when(() => mockFileRepository.uploadFile(any(that: isNull), 'new.txt', any(), 5, any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')))
        .thenAnswer((_) async => 'file-1');

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    final upserted = mirror.row('file-1')!;
    expect(upserted.localPath, file.path);
    expect(upserted.isFolder, isFalse);
    expect(upserted.sizeBytes, 5);
    expect(upserted.contentHash, hashOf('hello'));
    verify(() => mockFileRepository.uploadFile(
          any(that: isNull),
          'new.txt',
          any(),
          5,
          any(),
          originDeviceId: 'dev-1',
         cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated'))).called(1);
  });

  test('new file inside a new subfolder: creates the folder first (also '
      'tagged), then uploads into it', () async {
    final subDir = Directory(p.join(tempDir.path, 'sub'))..createSync();
    File(p.join(subDir.path, 'new.txt')).writeAsStringSync('x');
    final mirror = stateful([]);
    when(() => mockFileRepository.createFolder(null, 'sub', originDeviceId: any(named: 'originDeviceId'))).thenAnswer((_) async => FileItem(
          id: 'folder-1',
          name: 'sub',
          isFolder: true,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockFileRepository.uploadFile('folder-1', 'new.txt', any(), 1, any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')))
        .thenAnswer((_) async => 'file-2');

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    verifyInOrder([
      () => mockFileRepository.createFolder(null, 'sub', originDeviceId: 'dev-1'),
      () => mockFileRepository.uploadFile('folder-1', 'new.txt', any(), 1, any(),
          originDeviceId: 'dev-1', cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')),
    ]);
    expect(mirror.row('folder-1'), isNotNull);
  });

  test('tracked file edited (different bytes): uploads a new version '
      'tagged with this device\'s id; no create, no delete', () async {
    final file = File(p.join(tempDir.path, 'tracked.txt'))
      ..writeAsStringSync('a longer new body');
    stateful([
      SyncMirrorEntry(
        serverId: 'file-3',
        localPath: file.path,
        isFolder: false,
        sizeBytes: 3, // old length ('old') — differs from the new content's length
        contentHash: hashOf('old'),
        updatedAt: past,
        syncedAt: past,
      ),
    ]);
    when(() => mockFileRepository.uploadNewVersion('file-3', 'tracked.txt', any(), 17, originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken')))
        .thenAnswer((_) async {});

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    verify(() => mockFileRepository.uploadNewVersion('file-3', 'tracked.txt', any(), 17,
            originDeviceId: 'dev-1', cancelToken: any(named: 'cancelToken')))
        .called(1);
    verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')));
    verifyNever(() => mockFileRepository.deleteFile(any(), originDeviceId: any(named: 'originDeviceId')));
  });

  test('tracked file unchanged (same size, not modified since it was last '
      'synced): no server calls at all', () async {
    final file = File(p.join(tempDir.path, 'same.txt'))..writeAsStringSync('same');
    stateful([
      SyncMirrorEntry(
        serverId: 'file-4',
        localPath: file.path,
        isFolder: false,
        sizeBytes: 4,
        contentHash: hashOf('same'),
        updatedAt: past,
        syncedAt: future, // guarantees the real (just-written) mtime is not after this
      ),
    ]);

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 0);
    verifyNever(() => mockFileRepository.uploadNewVersion(any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken')));
    verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')));
    verifyNever(() => mockFileRepository.deleteFile(any(), originDeviceId: any(named: 'originDeviceId')));
    verifyNever(() => mockMirror.commit(
          upserts: any(named: 'upserts'),
          deleteServerIds: any(named: 'deleteServerIds'),
          deleteUnderPath: any(named: 'deleteUnderPath'),
          rePath: any(named: 'rePath'),
        ));
  });

  test('tracked file deleted: deletes server-side (tagged with this '
      'device\'s id), removes the mirror row', () async {
    final gonePath = p.join(tempDir.path, 'gone.txt'); // never created on disk
    final mirror = stateful([
      SyncMirrorEntry(
        serverId: 'file-5',
        localPath: gonePath,
        isFolder: false,
        sizeBytes: 3,
        contentHash: hashOf('bye'),
        updatedAt: past,
        syncedAt: past,
      ),
    ]);
    when(() => mockFileRepository.deleteFile('file-5', originDeviceId: any(named: 'originDeviceId'))).thenAnswer((_) async {});

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    verify(() => mockFileRepository.deleteFile('file-5', originDeviceId: 'dev-1')).called(1);
    expect(mirror.row('file-5'), isNull);
  });

  test('tracked file renamed in place (same bytes): renames only (tagged '
      'with this device\'s id) — no upload, no delete; mirror path updated',
      () async {
    final oldPath = p.join(tempDir.path, 'old.txt'); // no longer on disk
    final newFile = File(p.join(tempDir.path, 'new.txt'))
      ..writeAsStringSync('same bytes');
    final mirror = stateful([
      SyncMirrorEntry(
        serverId: 'file-6',
        localPath: oldPath,
        isFolder: false,
        sizeBytes: 10,
        contentHash: hashOf('same bytes'),
        updatedAt: past,
        syncedAt: past,
      ),
    ]);
    when(() => mockFileRepository.getFile('file-6')).thenAnswer((_) async => FileItem(
          id: 'file-6',
          name: 'old.txt',
          isFolder: false,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockFileRepository.renameFile('file-6', 'new.txt', originDeviceId: any(named: 'originDeviceId'))).thenAnswer((_) async => FileItem(
          id: 'file-6',
          name: 'new.txt',
          isFolder: false,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    verify(() => mockFileRepository.renameFile('file-6', 'new.txt', originDeviceId: 'dev-1'))
        .called(1);
    verifyNever(() => mockFileRepository.moveFile(any(), any(), originDeviceId: any(named: 'originDeviceId')));
    verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')));
    verifyNever(() => mockFileRepository.deleteFile(any(), originDeviceId: any(named: 'originDeviceId')));
    expect(mirror.row('file-6')!.localPath, newFile.path);
  });

  test('tracked file moved into another tracked folder: moves only, '
      'tagged with this device\'s id', () async {
    final subDir = Directory(p.join(tempDir.path, 'sub'))..createSync();
    final oldPath = p.join(tempDir.path, 'file.txt'); // no longer on disk
    final movedFile = File(p.join(subDir.path, 'file.txt'))
      ..writeAsStringSync('payload');
    final mirror = stateful([
      SyncMirrorEntry(
        serverId: 'sub-id',
        localPath: subDir.path,
        isFolder: true,
        updatedAt: past,
        syncedAt: past,
      ),
      SyncMirrorEntry(
        serverId: 'file-7',
        localPath: oldPath,
        isFolder: false,
        sizeBytes: 7,
        contentHash: hashOf('payload'),
        updatedAt: past,
        syncedAt: past,
      ),
    ]);
    when(() => mockFileRepository.getFile('file-7')).thenAnswer((_) async => FileItem(
          id: 'file-7',
          name: 'file.txt',
          isFolder: false,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockFileRepository.moveFile('file-7', 'sub-id', originDeviceId: any(named: 'originDeviceId'))).thenAnswer((_) async => FileItem(
          id: 'file-7',
          name: 'file.txt',
          isFolder: false,
          parentId: 'sub-id',
          createdAt: now,
          updatedAt: now,
        ));

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    verify(() => mockFileRepository.moveFile('file-7', 'sub-id', originDeviceId: 'dev-1'))
        .called(1);
    verifyNever(() => mockFileRepository.renameFile(any(), any(), originDeviceId: any(named: 'originDeviceId')));
    expect(mirror.row('file-7')!.localPath, movedFile.path);
  });

  test('moved and renamed: moves first, then renames; both tagged with '
      'this device\'s id', () async {
    final subDir = Directory(p.join(tempDir.path, 'sub'))..createSync();
    final oldPath = p.join(tempDir.path, 'old.txt'); // no longer on disk
    File(p.join(subDir.path, 'new.txt')).writeAsStringSync('payload');
    stateful([
      SyncMirrorEntry(
        serverId: 'sub-id',
        localPath: subDir.path,
        isFolder: true,
        updatedAt: past,
        syncedAt: past,
      ),
      SyncMirrorEntry(
        serverId: 'file-8',
        localPath: oldPath,
        isFolder: false,
        sizeBytes: 7,
        contentHash: hashOf('payload'),
        updatedAt: past,
        syncedAt: past,
      ),
    ]);
    when(() => mockFileRepository.getFile('file-8')).thenAnswer((_) async => FileItem(
          id: 'file-8',
          name: 'old.txt',
          isFolder: false,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockFileRepository.moveFile('file-8', 'sub-id', originDeviceId: any(named: 'originDeviceId'))).thenAnswer((_) async => FileItem(
          id: 'file-8',
          name: 'old.txt',
          isFolder: false,
          parentId: 'sub-id',
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockFileRepository.renameFile('file-8', 'new.txt', originDeviceId: any(named: 'originDeviceId'))).thenAnswer((_) async => FileItem(
          id: 'file-8',
          name: 'new.txt',
          isFolder: false,
          parentId: 'sub-id',
          createdAt: now,
          updatedAt: now,
        ));

    await scanner.scanOnce(tempDir.path);

    verifyInOrder([
      () => mockFileRepository.moveFile('file-8', 'sub-id', originDeviceId: 'dev-1'),
      () => mockFileRepository.renameFile('file-8', 'new.txt', originDeviceId: 'dev-1'),
    ]);
  });

  test('ambiguous hash match (two missing tracked files share content with '
      'one new file): no move — the new file is uploaded and both missing '
      'files are deleted', () async {
    final dupeAPath = p.join(tempDir.path, 'dupeA.txt'); // no longer on disk
    final dupeBPath = p.join(tempDir.path, 'dupeB.txt'); // no longer on disk
    File(p.join(tempDir.path, 'newdupe.txt')).writeAsStringSync('shared content');
    stateful([
      SyncMirrorEntry(
        serverId: 'dupeA-id',
        localPath: dupeAPath,
        isFolder: false,
        sizeBytes: 14,
        contentHash: hashOf('shared content'),
        updatedAt: past,
        syncedAt: past,
      ),
      SyncMirrorEntry(
        serverId: 'dupeB-id',
        localPath: dupeBPath,
        isFolder: false,
        sizeBytes: 14,
        contentHash: hashOf('shared content'),
        updatedAt: past,
        syncedAt: past,
      ),
    ]);
    when(() => mockFileRepository.uploadFile(any(that: isNull), 'newdupe.txt', any(), 14, any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')))
        .thenAnswer((_) async => 'newdupe-id');
    when(() => mockFileRepository.deleteFile('dupeA-id', originDeviceId: any(named: 'originDeviceId'))).thenAnswer((_) async {});
    when(() => mockFileRepository.deleteFile('dupeB-id', originDeviceId: any(named: 'originDeviceId'))).thenAnswer((_) async {});

    await scanner.scanOnce(tempDir.path);

    verifyNever(() => mockFileRepository.moveFile(any(), any(), originDeviceId: any(named: 'originDeviceId')));
    verifyNever(() => mockFileRepository.renameFile(any(), any(), originDeviceId: any(named: 'originDeviceId')));
    verify(() => mockFileRepository.uploadFile(any(that: isNull), 'newdupe.txt', any(), 14, any(),
            originDeviceId: 'dev-1', cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')))
        .called(1);
    verify(() => mockFileRepository.deleteFile('dupeA-id', originDeviceId: 'dev-1')).called(1);
    verify(() => mockFileRepository.deleteFile('dupeB-id', originDeviceId: 'dev-1')).called(1);
  });

  test('empty file renamed: treated as a new file plus a delete — empty '
      'files are never hash-matched', () async {
    final oldPath = p.join(tempDir.path, 'emptyOld.txt'); // no longer on disk
    File(p.join(tempDir.path, 'emptyNew.txt')).writeAsStringSync('');
    stateful([
      SyncMirrorEntry(
        serverId: 'empty-id',
        localPath: oldPath,
        isFolder: false,
        sizeBytes: 0,
        contentHash: hashOfBytes(const []),
        updatedAt: past,
        syncedAt: past,
      ),
    ]);
    when(() => mockFileRepository.uploadFile(any(that: isNull), 'emptyNew.txt', any(), 0, any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')))
        .thenAnswer((_) async => 'emptyNew-id');
    when(() => mockFileRepository.deleteFile('empty-id', originDeviceId: any(named: 'originDeviceId'))).thenAnswer((_) async {});

    await scanner.scanOnce(tempDir.path);

    verifyNever(() => mockFileRepository.moveFile(any(), any(), originDeviceId: any(named: 'originDeviceId')));
    verifyNever(() => mockFileRepository.renameFile(any(), any(), originDeviceId: any(named: 'originDeviceId')));
    verify(() => mockFileRepository.uploadFile(any(that: isNull), 'emptyNew.txt', any(), 0, any(),
            originDeviceId: 'dev-1', cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')))
        .called(1);
    verify(() => mockFileRepository.deleteFile('empty-id', originDeviceId: 'dev-1')).called(1);
  });

  test('a tracked folder with tracked children, all deleted locally: '
      'exactly one deleteFile for the folder, and every mirror row under '
      'it — folder and children — is removed via one commit', () async {
    final projPath = p.join(tempDir.path, 'proj'); // whole tree gone from disk
    final aPath = p.join(projPath, 'a.txt');
    final subPath = p.join(projPath, 'sub');
    final bPath = p.join(subPath, 'b.txt');

    final mirror = stateful([
      SyncMirrorEntry(serverId: 'proj-id', localPath: projPath, isFolder: true, updatedAt: past, syncedAt: past),
      SyncMirrorEntry(
        serverId: 'a-id',
        localPath: aPath,
        isFolder: false,
        sizeBytes: 1,
        contentHash: hashOf('a'),
        updatedAt: past,
        syncedAt: past,
      ),
      SyncMirrorEntry(serverId: 'sub-id', localPath: subPath, isFolder: true, updatedAt: past, syncedAt: past),
      SyncMirrorEntry(
        serverId: 'b-id',
        localPath: bPath,
        isFolder: false,
        sizeBytes: 1,
        contentHash: hashOf('b'),
        updatedAt: past,
        syncedAt: past,
      ),
    ]);
    when(() => mockFileRepository.deleteFile('proj-id', originDeviceId: any(named: 'originDeviceId'))).thenAnswer((_) async {});

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    verify(() => mockFileRepository.deleteFile('proj-id', originDeviceId: 'dev-1')).called(1);
    verifyNever(() => mockFileRepository.deleteFile('a-id', originDeviceId: any(named: 'originDeviceId')));
    verifyNever(() => mockFileRepository.deleteFile('b-id', originDeviceId: any(named: 'originDeviceId')));
    verifyNever(() => mockFileRepository.deleteFile('sub-id', originDeviceId: any(named: 'originDeviceId')));
    expect(mirror.rows, isEmpty);
  });

  test('OS metadata, an unsafe Windows name, and a symlink are all ignored '
      '— no server calls for any of them', () async {
    File(p.join(tempDir.path, '.DS_Store')).writeAsStringSync('finder metadata');
    File(p.join(tempDir.path, 'Thumbs.db')).writeAsStringSync('thumbnail cache');
    File(p.join(tempDir.path, 'aux.txt')).writeAsStringSync('reserved on Windows');

    try {
      Link(p.join(tempDir.path, 'link.txt')).createSync(p.join(tempDir.path, 'aux.txt'));
    } on FileSystemException {
      // Symlink creation needs a privilege this host/user does not have
      // (common in CI without developer mode / elevation) — the other two
      // sub-cases in this test still cover the walk's filtering.
    }

    stateful([]);

    final pushed = await scannerWith(isWindows: true).scanOnce(tempDir.path);

    expect(pushed, 0);
    verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')));
    verifyNever(() => mockFileRepository.createFolder(any(), any(), originDeviceId: any(named: 'originDeviceId')));
  });

  test('createFolder 409 (another device already created it, not yet '
      'pulled here): adopts the existing folder by name instead of '
      'waiting for the next pull, so a child under it still uploads this '
      'same scan (test 9)', () async {
    final subDir = Directory(p.join(tempDir.path, 'sub'))..createSync();
    File(p.join(subDir.path, 'child.txt')).writeAsStringSync('payload');
    final mirror = stateful([]);
    when(() => mockFileRepository.createFolder(null, 'sub', originDeviceId: any(named: 'originDeviceId')))
        .thenThrow(dioError(409));
    when(() => mockFileRepository.listChildren(null, page: 1, pageSize: 200)).thenAnswer(
        (_) async => PagedResult(
              items: [
                FileItem(
                  id: 'existing-folder-id',
                  name: 'sub',
                  isFolder: true,
                  parentId: null,
                  createdAt: now,
                  updatedAt: now,
                ),
              ],
              totalCount: 1,
              page: 1,
              pageSize: 200,
            ));
    when(() => mockFileRepository.uploadFile(
          'existing-folder-id',
          'child.txt',
          any(),
          7,
          any(),
          originDeviceId: any(named: 'originDeviceId'),
         cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated'))).thenAnswer((_) async => 'child-id');

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1); // the folder adopt itself is never counted, only the child upload
    expect(mirror.row('existing-folder-id')!.localPath, subDir.path);
    verify(() => mockFileRepository.uploadFile(
          'existing-folder-id',
          'child.txt',
          any(),
          7,
          any(),
          originDeviceId: any(named: 'originDeviceId'),
         cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated'))).called(1);
  });

  test('createFolder 409 against a server folder name that differs only by '
      'case: still adopted case-insensitively', () async {
    final subDir = Directory(p.join(tempDir.path, 'sub'))..createSync();
    final mirror = stateful([]);
    when(() => mockFileRepository.createFolder(null, 'sub', originDeviceId: any(named: 'originDeviceId')))
        .thenThrow(dioError(409));
    when(() => mockFileRepository.listChildren(null, page: 1, pageSize: 200)).thenAnswer(
        (_) async => PagedResult(
              items: [
                FileItem(
                  id: 'existing-folder-id',
                  name: 'Sub', // differs only by case from the local 'sub'
                  isFolder: true,
                  parentId: null,
                  createdAt: now,
                  updatedAt: now,
                ),
              ],
              totalCount: 1,
              page: 1,
              pageSize: 200,
            ));

    await scanner.scanOnce(tempDir.path);

    expect(mirror.row('existing-folder-id')!.localPath, subDir.path);
  });

  test('createFolder 409 whose conflicting server sibling is a file, not a '
      'folder: not adopted — waits for the next pull like before', () async {
    Directory(p.join(tempDir.path, 'sub')).createSync();
    stateful([]);
    when(() => mockFileRepository.createFolder(null, 'sub', originDeviceId: any(named: 'originDeviceId')))
        .thenThrow(dioError(409));
    when(() => mockFileRepository.listChildren(null, page: 1, pageSize: 200)).thenAnswer(
        (_) async => PagedResult(
              items: [
                FileItem(
                  id: 'file-not-folder',
                  name: 'sub',
                  isFolder: false, // a file named "sub", not the folder we tried to create
                  parentId: null,
                  createdAt: now,
                  updatedAt: now,
                ),
              ],
              totalCount: 1,
              page: 1,
              pageSize: 200,
            ));

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 0);
    verifyNever(() => mockMirror.upsert(any()));
  });

  test('new file 409 (name already exists server-side): uploads a new '
      'version into the existing file, tagged with this device\'s id',
      () async {
    File(p.join(tempDir.path, 'shared.txt')).writeAsStringSync('local content');
    stateful([]);
    when(() => mockFileRepository.uploadFile(any(that: isNull), 'shared.txt', any(), 13, any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')))
        .thenThrow(dioError(409));
    when(() => mockFileRepository.listChildren(null, page: 1, pageSize: 200))
        .thenAnswer((_) async => PagedResult(
              items: [
                FileItem(
                  id: 'existing-id',
                  name: 'shared.txt',
                  isFolder: false,
                  parentId: null,
                  createdAt: now,
                  updatedAt: now,
                ),
              ],
              totalCount: 1,
              page: 1,
              pageSize: 200,
            ));
    when(() => mockFileRepository.uploadNewVersion('existing-id', 'shared.txt', any(), 13, originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken')))
        .thenAnswer((_) async {});

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    verify(() => mockFileRepository.uploadNewVersion('existing-id', 'shared.txt', any(), 13,
            originDeviceId: 'dev-1', cancelToken: any(named: 'cancelToken')))
        .called(1);
  });

  test('new file 409 against a server name that differs only by case: '
      'finds it case-insensitively and uploads a new version into it', () async {
    File(p.join(tempDir.path, 'Shared.txt')).writeAsStringSync('local content');
    stateful([]);
    when(() => mockFileRepository.uploadFile(any(that: isNull), 'Shared.txt', any(), 13, any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')))
        .thenThrow(dioError(409));
    when(() => mockFileRepository.listChildren(null, page: 1, pageSize: 200))
        .thenAnswer((_) async => PagedResult(
              items: [
                FileItem(
                  id: 'existing-id',
                  name: 'shared.txt',
                  isFolder: false,
                  parentId: null,
                  createdAt: now,
                  updatedAt: now,
                ),
              ],
              totalCount: 1,
              page: 1,
              pageSize: 200,
            ));
    when(() => mockFileRepository.uploadNewVersion(any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken')))
        .thenAnswer((_) async {});

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    verify(() => mockFileRepository.uploadNewVersion('existing-id', 'Shared.txt', any(), 13,
            originDeviceId: 'dev-1', cancelToken: any(named: 'cancelToken')))
        .called(1);
  });

  test('changed file whose uploadNewVersion 404s (deleted server-side '
      'meanwhile): re-created via uploadFile, old mirror row removed in the '
      'same commit as the new one', () async {
    final file = File(p.join(tempDir.path, 'edited.txt'))
      ..writeAsStringSync('new local content');
    final mirror = stateful([
      SyncMirrorEntry(
        serverId: 'stale-id',
        localPath: file.path,
        isFolder: false,
        sizeBytes: 3,
        contentHash: hashOf('old'),
        updatedAt: past,
        syncedAt: past,
      ),
    ]);
    when(() => mockFileRepository.uploadNewVersion('stale-id', 'edited.txt', any(), 17, originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken')))
        .thenThrow(dioError(404));
    when(() => mockFileRepository.uploadFile(any(that: isNull), 'edited.txt', any(), 17, any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')))
        .thenAnswer((_) async => 'fresh-id');

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    verify(() => mockFileRepository.uploadFile(any(that: isNull), 'edited.txt', any(), 17, any(),
            originDeviceId: 'dev-1', cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')))
        .called(1);
    expect(mirror.row('stale-id'), isNull);
    expect(mirror.row('fresh-id')!.localPath, file.path);
  });

  test('one failing upload does not stop the next file; the failed path is '
      'skipped on an immediate second scan (backoff)', () async {
    File(p.join(tempDir.path, 'bad.txt')).writeAsStringSync('will fail');
    File(p.join(tempDir.path, 'good.txt')).writeAsStringSync('will succeed');
    stateful([]);
    when(() => mockFileRepository.uploadFile(any(that: isNull), 'bad.txt', any(), 9, any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')))
        .thenThrow(Exception('network dropped'));
    when(() => mockFileRepository.uploadFile(any(that: isNull), 'good.txt', any(), 12, any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')))
        .thenAnswer((_) async => 'good-id');

    final firstPushed = await scanner.scanOnce(tempDir.path);
    expect(firstPushed, 1); // only good.txt landed
    verify(() => mockFileRepository.uploadFile(any(that: isNull), 'good.txt', any(), 12, any(),
            originDeviceId: 'dev-1', cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')))
        .called(1);

    // Second, immediate scan: bad.txt is still a "new file" from the
    // mirror's point of view (it was never committed), but backoff must
    // skip it rather than retrying the same failure straight away. The
    // good.txt row is exactly what scan 1's own commit call left behind —
    // untouched by the test.
    clearInteractions(mockFileRepository);

    final secondPushed = await scanner.scanOnce(tempDir.path);

    expect(secondPushed, 0);
    verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')));
  });

  test('tracked file touched (mtime bumped) but identical content: the hash '
      'compare catches it — no upload (F8)', () async {
    final file = File(p.join(tempDir.path, 'touched.txt'))..writeAsStringSync('same content');
    // Bump mtime forward so the cheap stat pre-filter alone cannot skip the
    // hash compare below it — a re-save (e.g. an editor "touch") must not be
    // mistaken for an edit just because the OS timestamp moved.
    file.setLastModifiedSync(DateTime.now().add(const Duration(days: 1)));
    stateful([
      SyncMirrorEntry(
        serverId: 'file-touch',
        localPath: file.path,
        isFolder: false,
        sizeBytes: 12, // 'same content'.length
        contentHash: hashOf('same content'),
        updatedAt: past,
        syncedAt: past, // older than the bumped mtime
      ),
    ]);

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 0);
    verifyNever(() => mockFileRepository.uploadNewVersion(any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken')));
  });

  test('a tracked .DS_Store still present on disk is never deleted, even '
      'though the walk itself never surfaces it (F5)', () async {
    final dsStore = File(p.join(tempDir.path, '.DS_Store'))
      ..writeAsStringSync('finder metadata');
    stateful([
      SyncMirrorEntry(
        serverId: 'ds-store-id',
        localPath: dsStore.path,
        isFolder: false,
        sizeBytes: 16,
        contentHash: hashOf('finder metadata'),
        updatedAt: past,
        syncedAt: past,
      ),
    ]);

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 0);
    verifyNever(() => mockFileRepository.deleteFile(any(), originDeviceId: any(named: 'originDeviceId')));
    verifyNever(() => mockFileRepository.uploadNewVersion(any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken')));
  });

  group('decision 2: case-insensitive path matching everywhere', () {
    test('a.txt -> A.txt on disk (tracked): renameFile only — no upload, '
        'no delete (test 6)', () async {
      final oldPath = p.join(tempDir.path, 'a.txt'); // tracked, no longer on disk
      final newFile = File(p.join(tempDir.path, 'A.txt'))..writeAsStringSync('payload');
      final mirror = stateful([
        SyncMirrorEntry(
          serverId: 'a-id',
          localPath: oldPath,
          isFolder: false,
          sizeBytes: 7,
          contentHash: hashOf('payload'),
          updatedAt: past,
          syncedAt: past,
        ),
      ]);
      when(() => mockFileRepository.renameFile('a-id', 'A.txt', originDeviceId: any(named: 'originDeviceId'))).thenAnswer((_) async => FileItem(
            id: 'a-id',
            name: 'A.txt',
            isFolder: false,
            parentId: null,
            createdAt: now,
            updatedAt: now,
          ));

      final pushed = await scanner.scanOnce(tempDir.path);

      expect(pushed, 1);
      verify(() => mockFileRepository.renameFile('a-id', 'A.txt', originDeviceId: 'dev-1')).called(1);
      verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')));
      verifyNever(() => mockFileRepository.deleteFile(any(), originDeviceId: any(named: 'originDeviceId')));
      verifyNever(() => mockFileRepository.moveFile(any(), any(), originDeviceId: any(named: 'originDeviceId')));
      expect(mirror.row('a-id')!.localPath, newFile.path);
    });

    test('case rename plus a same-size edit made before the rename was '
        'seen: across at most two scans, exactly one renameFile and '
        'exactly one uploadNewVersion — the edit is not silently dropped '
        '(PR #14 review round 4, R4-2)', () async {
      final oldPath = p.join(tempDir.path, 'a.txt'); // tracked, no longer on disk
      // Same byte length as the tracked content ('original'.length == 8) but
      // different bytes — the edit this test must not lose.
      final newFile = File(p.join(tempDir.path, 'A.txt'))..writeAsStringSync('edited!!');
      final mirror = stateful([
        SyncMirrorEntry(
          serverId: 'a-id',
          localPath: oldPath,
          isFolder: false,
          sizeBytes: 8,
          contentHash: hashOf('original'),
          updatedAt: past,
          syncedAt: past,
        ),
      ]);
      when(() => mockFileRepository.renameFile('a-id', 'A.txt', originDeviceId: any(named: 'originDeviceId'))).thenAnswer((_) async => FileItem(
            id: 'a-id',
            name: 'A.txt',
            isFolder: false,
            parentId: null,
            createdAt: now,
            updatedAt: now,
          ));
      when(() => mockFileRepository.uploadNewVersion('a-id', 'A.txt', any(), 8, originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken')))
          .thenAnswer((_) async {});

      // Scan 1: case-only rename only — no upload yet.
      final firstPushed = await scanner.scanOnce(tempDir.path);
      expect(firstPushed, 1);
      verify(() => mockFileRepository.renameFile('a-id', 'A.txt', originDeviceId: 'dev-1')).called(1);
      verifyNever(() => mockFileRepository.uploadNewVersion(any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken')));
      // The renamed row must keep the OLD hash/syncedAt (not stamped to
      // "now") — otherwise scan 2's change-detection pre-filter in
      // _uploadChangedFile reads sizeBytes-equal + not-modified-since-
      // syncedAt as "nothing changed" and the edit below is never uploaded.
      expect(mirror.row('a-id')!.contentHash, hashOf('original'));
      expect(mirror.row('a-id')!.syncedAt, past);

      // Scan 2: the edit is now visible under its new (renamed) path.
      final secondPushed = await scanner.scanOnce(tempDir.path);
      expect(secondPushed, 1);
      verify(() => mockFileRepository.uploadNewVersion('a-id', 'A.txt', any(), 8,
              originDeviceId: 'dev-1', cancelToken: any(named: 'cancelToken')))
          .called(1);
      expect(mirror.row('a-id')!.localPath, newFile.path);
      expect(mirror.row('a-id')!.contentHash, hashOf('edited!!'));
    });

    test('tracked Docs/ with tracked Docs/x.txt, disk has docs/x.txt: one '
        'renameFile(docsId, "docs"), no create/delete/upload (test 7)', () async {
      final docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync();
      File(p.join(docsDir.path, 'x.txt')).writeAsStringSync('x');
      final oldDocsPath = p.join(tempDir.path, 'Docs'); // tracked path, no longer on disk
      final oldChildPath = p.join(oldDocsPath, 'x.txt');
      final mirror = stateful([
        SyncMirrorEntry(serverId: 'docs-id', localPath: oldDocsPath, isFolder: true, updatedAt: past, syncedAt: past),
        SyncMirrorEntry(
          serverId: 'child-id',
          localPath: oldChildPath,
          isFolder: false,
          sizeBytes: 1,
          contentHash: hashOf('x'),
          updatedAt: past,
          syncedAt: past,
        ),
      ]);
      when(() => mockFileRepository.renameFile('docs-id', 'docs', originDeviceId: any(named: 'originDeviceId'))).thenAnswer((_) async => FileItem(
            id: 'docs-id',
            name: 'docs',
            isFolder: true,
            parentId: null,
            createdAt: now,
            updatedAt: now,
          ));

      final pushed = await scanner.scanOnce(tempDir.path);

      expect(pushed, 1);
      verify(() => mockFileRepository.renameFile('docs-id', 'docs', originDeviceId: 'dev-1'))
          .called(1);
      verifyNever(() => mockFileRepository.createFolder(any(), any(), originDeviceId: any(named: 'originDeviceId')));
      verifyNever(() => mockFileRepository.deleteFile(any(), originDeviceId: any(named: 'originDeviceId')));
      verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')));
      // The child itself was never renamed — a directory rename moves it
      // along for free.
      verifyNever(() => mockFileRepository.renameFile('child-id', any(), originDeviceId: any(named: 'originDeviceId')));
      expect(mirror.row('docs-id')!.localPath, docsDir.path);
      expect(mirror.row('child-id')!.localPath, p.join(docsDir.path, 'x.txt'));
    });

    test('residual B: same as test 7 but renameFile throws — no deleteFile, '
        'uploadFile, uploadNewVersion or createFolder for the folder or '
        'anything under it, in that scan and in a second scan after '
        'debugClearBackoff() with renameFile still failing (test 8)', () async {
      final docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync();
      File(p.join(docsDir.path, 'x.txt')).writeAsStringSync('x');
      final oldDocsPath = p.join(tempDir.path, 'Docs');
      final oldChildPath = p.join(oldDocsPath, 'x.txt');
      stateful([
        SyncMirrorEntry(serverId: 'docs-id', localPath: oldDocsPath, isFolder: true, updatedAt: past, syncedAt: past),
        SyncMirrorEntry(
          serverId: 'child-id',
          localPath: oldChildPath,
          isFolder: false,
          sizeBytes: 1,
          contentHash: hashOf('x'),
          updatedAt: past,
          syncedAt: past,
        ),
      ]);
      when(() => mockFileRepository.renameFile('docs-id', 'docs', originDeviceId: any(named: 'originDeviceId'))).thenThrow(Exception('server unreachable'));

      final firstPushed = await scanner.scanOnce(tempDir.path);
      expect(firstPushed, 0);
      verifyNever(() => mockFileRepository.deleteFile(any(), originDeviceId: any(named: 'originDeviceId')));
      verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')));
      verifyNever(() => mockFileRepository.uploadNewVersion(any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken')));
      verifyNever(() => mockFileRepository.createFolder(any(), any(), originDeviceId: any(named: 'originDeviceId')));

      scanner.debugClearBackoff();
      clearInteractions(mockFileRepository);
      when(() => mockFileRepository.renameFile('docs-id', 'docs', originDeviceId: any(named: 'originDeviceId'))).thenThrow(Exception('still unreachable'));

      final secondPushed = await scanner.scanOnce(tempDir.path);
      expect(secondPushed, 0);
      verifyNever(() => mockFileRepository.deleteFile(any(), originDeviceId: any(named: 'originDeviceId')));
      verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')));
      verifyNever(() => mockFileRepository.uploadNewVersion(any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken')));
      verifyNever(() => mockFileRepository.createFolder(any(), any(), originDeviceId: any(named: 'originDeviceId')));
    });
  });

  group('F2: a failed move does not delete the source, and a partial move '
      'is idempotent on retry', () {
    test('moveFile throws: no deleteFile for the source, no upload of the '
        'new file, mirror row unchanged, nothing enqueued', () async {
      final subDir = Directory(p.join(tempDir.path, 'sub'))..createSync();
      final oldPath = p.join(tempDir.path, 'file.txt'); // no longer on disk
      File(p.join(subDir.path, 'file.txt')).writeAsStringSync('payload');
      final mirror = stateful([
        SyncMirrorEntry(serverId: 'sub-id', localPath: subDir.path, isFolder: true, updatedAt: past, syncedAt: past),
        SyncMirrorEntry(
          serverId: 'file-a',
          localPath: oldPath,
          isFolder: false,
          sizeBytes: 7,
          contentHash: hashOf('payload'),
          updatedAt: past,
          syncedAt: past,
        ),
      ]);
      when(() => mockFileRepository.getFile('file-a')).thenAnswer((_) async => FileItem(
            id: 'file-a',
            name: 'file.txt',
            isFolder: false,
            parentId: null,
            createdAt: now,
            updatedAt: now,
          ));
      when(() => mockFileRepository.moveFile('file-a', 'sub-id', originDeviceId: any(named: 'originDeviceId')))
          .thenThrow(Exception('network dropped'));

      await scanner.scanOnce(tempDir.path);

      verifyNever(() => mockFileRepository.deleteFile(any(), originDeviceId: any(named: 'originDeviceId')));
      verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')));
      expect(mirror.row('file-a')!.localPath, oldPath);
    });

    test('move succeeds but rename throws: the mirror row is left '
        'unchanged this scan (the commit that would update it never runs); '
        'a retried scan with getFile now reflecting the already-moved '
        'parent skips moveFile and calls only renameFile', () async {
      final subDir = Directory(p.join(tempDir.path, 'sub'))..createSync();
      final oldPath = p.join(tempDir.path, 'old.txt'); // no longer on disk
      File(p.join(subDir.path, 'new.txt')).writeAsStringSync('payload');
      final mirror = stateful([
        SyncMirrorEntry(serverId: 'sub-id', localPath: subDir.path, isFolder: true, updatedAt: past, syncedAt: past),
        SyncMirrorEntry(
          serverId: 'file-b',
          localPath: oldPath,
          isFolder: false,
          sizeBytes: 7,
          contentHash: hashOf('payload'),
          updatedAt: past,
          syncedAt: past,
        ),
      ]);
      when(() => mockFileRepository.getFile('file-b')).thenAnswer((_) async => FileItem(
            id: 'file-b',
            name: 'old.txt',
            isFolder: false,
            parentId: null,
            createdAt: now,
            updatedAt: now,
          ));
      when(() => mockFileRepository.moveFile('file-b', 'sub-id', originDeviceId: any(named: 'originDeviceId'))).thenAnswer((_) async => FileItem(
            id: 'file-b',
            name: 'old.txt',
            isFolder: false,
            parentId: 'sub-id',
            createdAt: now,
            updatedAt: now,
          ));
      when(() => mockFileRepository.renameFile('file-b', 'new.txt', originDeviceId: any(named: 'originDeviceId')))
          .thenThrow(Exception('server unreachable'));

      await scanner.scanOnce(tempDir.path);

      verify(() => mockFileRepository.moveFile('file-b', 'sub-id', originDeviceId: 'dev-1'))
          .called(1);
      verifyNever(() => mockFileRepository.deleteFile(any(), originDeviceId: any(named: 'originDeviceId')));
      expect(mirror.row('file-b')!.localPath, oldPath); // commit never ran

      // Retry: backoff cleared, and getFile now reflects the half that
      // already landed (parentId is 'sub-id'; the rename never made it).
      scanner.debugClearBackoff();
      clearInteractions(mockFileRepository);
      when(() => mockFileRepository.getFile('file-b')).thenAnswer((_) async => FileItem(
            id: 'file-b',
            name: 'old.txt',
            isFolder: false,
            parentId: 'sub-id',
            createdAt: now,
            updatedAt: now,
          ));
      when(() => mockFileRepository.renameFile('file-b', 'new.txt', originDeviceId: any(named: 'originDeviceId'))).thenAnswer((_) async => FileItem(
            id: 'file-b',
            name: 'new.txt',
            isFolder: false,
            parentId: 'sub-id',
            createdAt: now,
            updatedAt: now,
          ));

      await scanner.scanOnce(tempDir.path);

      verifyNever(() => mockFileRepository.moveFile(any(), any(), originDeviceId: any(named: 'originDeviceId')));
      // getFile now reflects the parent as already moved, so only the
      // rename half is actually called this time — and it is still tagged.
      verify(() => mockFileRepository.renameFile('file-b', 'new.txt', originDeviceId: 'dev-1'))
          .called(1);
    });

    test('an unreadable/backed-off new file with the same size as a missing '
        'file: no deleteFile for that missing file', () async {
      final oldPath = p.join(tempDir.path, 'gone.bin'); // no longer on disk
      final newFile = File(p.join(tempDir.path, 'unreadable.bin'))
        ..writeAsBytesSync(List.filled(9, 1));
      stateful([
        SyncMirrorEntry(
          serverId: 'file-c',
          localPath: oldPath,
          isFolder: false,
          sizeBytes: 9, // same size as newFile, unrelated content
          contentHash: hashOf('irrelevant, never compared'),
          updatedAt: past,
          syncedAt: past,
        ),
      ]);
      // Simulates a read failure without depending on OS-specific file
      // locking: pre-backing the path off is exactly what _hashFiles's own
      // failure path leaves behind, and the scanner cannot tell the two
      // apart.
      scanner.debugBackOff(newFile.path);

      await scanner.scanOnce(tempDir.path);

      verifyNever(() => mockFileRepository.deleteFile('file-c', originDeviceId: any(named: 'originDeviceId')));
    });
  });

  test('finding 5: a getFile 404 during a move drops the stale mirror row '
      'instead of calling moveFile/renameFile', () async {
    final subDir = Directory(p.join(tempDir.path, 'sub11'))..createSync();
    final oldPath = p.join(tempDir.path, 'file11.txt');
    File(p.join(subDir.path, 'file11.txt')).writeAsStringSync('gone payload');
    final mirror = stateful([
      SyncMirrorEntry(serverId: 'sub11-id', localPath: subDir.path, isFolder: true, updatedAt: past, syncedAt: past),
      SyncMirrorEntry(
        serverId: 'file-g11',
        localPath: oldPath,
        isFolder: false,
        sizeBytes: 12,
        contentHash: hashOf('gone payload'),
        updatedAt: past,
        syncedAt: past,
      ),
    ]);
    when(() => mockFileRepository.getFile('file-g11')).thenThrow(dioError(404));

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 0);
    verifyNever(() => mockFileRepository.moveFile(any(), any(), originDeviceId: any(named: 'originDeviceId')));
    verifyNever(() => mockFileRepository.renameFile(any(), any(), originDeviceId: any(named: 'originDeviceId')));
    verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')));
    expect(mirror.row('file-g11'), isNull);
  });

  test('finding 6: an unhashed new file whose stat reports an unknown size '
      'protects same-size missing files instead of deleting them', () async {
    final oldPath = p.join(tempDir.path, 'gone12.bin');
    final newFile = File(p.join(tempDir.path, 'unknown12.bin'))..writeAsBytesSync(List.filled(9, 1));
    stateful([
      SyncMirrorEntry(
        serverId: 'file-u12',
        localPath: oldPath,
        isFolder: false,
        sizeBytes: 9,
        contentHash: hashOf('irrelevant, never compared'),
        updatedAt: past,
        syncedAt: past,
      ),
    ]);
    // Stubbed (but expected never called) so that a regression here fails
    // on the verifyNever below rather than on a missing-stub error.
    when(() => mockFileRepository.deleteFile('file-u12', originDeviceId: any(named: 'originDeviceId'))).thenAnswer((_) async {});
    // Backed off so _hashFiles never attempts to hash it (same seam the F2
    // "unreadable new file" test above uses), landing it in the
    // unhashed-new-files check — and forced to report an unknown size
    // there. File.stat() cannot actually throw; it returns size == -1 for
    // a vanished/unreadable file, which a portable test cannot reliably
    // race into existing here (see debugForceUnknownSize's doc comment).
    scanner.debugBackOff(newFile.path);
    scanner.debugForceUnknownSize(newFile.path);

    await scanner.scanOnce(tempDir.path);

    verifyNever(() => mockFileRepository.deleteFile('file-u12', originDeviceId: any(named: 'originDeviceId')));
  });

  test('finding 2 (folder delete 404): a retried deleteFile 404s once the '
      'server already trashed the folder — still commits, clearing the '
      'mirror row and everything under it', () async {
    final projPath = p.join(tempDir.path, 'proj9');
    final aPath = p.join(projPath, 'a9.txt');
    final mirror = stateful([
      SyncMirrorEntry(serverId: 'proj9-id', localPath: projPath, isFolder: true, updatedAt: past, syncedAt: past),
      SyncMirrorEntry(
        serverId: 'a9-id',
        localPath: aPath,
        isFolder: false,
        sizeBytes: 1,
        contentHash: hashOf('a'),
        updatedAt: past,
        syncedAt: past,
      ),
    ]);
    when(() => mockFileRepository.deleteFile('proj9-id', originDeviceId: any(named: 'originDeviceId'))).thenThrow(dioError(404));

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 0); // already gone server-side too; not a new push
    expect(mirror.rows, isEmpty);
    verify(() => mockFileRepository.deleteFile('proj9-id', originDeviceId: 'dev-1')).called(1);
  });

  group('scan 5: the scan never depends on SyncService being reachable — '
      'there is no push service any more, only local writes tagged for the '
      'server\'s own change feed', () {
    test('tagging a write with this device\'s id never needs a network '
        'call: ensureRegistered throwing does not stop a local change from '
        'being written, and the scan never calls it (PR #14 review round '
        '4, R4-1, adapted for the origin-tagging design)', () async {
      final file = File(p.join(tempDir.path, 'tracked2.txt'))
        ..writeAsStringSync('a longer new body');
      final mirror = stateful([
        SyncMirrorEntry(
          serverId: 'file-v2',
          localPath: file.path,
          isFolder: false,
          sizeBytes: 3, // old content's length
          contentHash: hashOf('old'),
          updatedAt: past,
          syncedAt: past,
        ),
      ]);
      when(() => mockDeviceRegistration.ensureRegistered())
          .thenThrow(Exception('SyncService unreachable'));
      when(() => mockFileRepository.uploadNewVersion('file-v2', 'tracked2.txt', any(), 17,
              originDeviceId: 'dev-1', cancelToken: any(named: 'cancelToken')))
          .thenAnswer((_) async {});

      final firstScanPushed = await scanner.scanOnce(tempDir.path);

      expect(firstScanPushed, 1);
      expect(mirror.row('file-v2')!.contentHash, hashOf('a longer new body'));
      verifyNever(() => mockDeviceRegistration.ensureRegistered());
    });
  });

  group('collidingKeys (PR #14 review round 4, R4-4)', () {
    test('two paths differing only by case collide on one key', () {
      final a = p.join('sync', 'a.txt');
      final upperA = p.join('sync', 'A.txt');
      expect(collidingKeys([a, upperA]), {a.toLowerCase()});
    });

    test('paths that differ by more than case do not collide', () {
      expect(collidingKeys([p.join('sync', 'a.txt'), p.join('sync', 'b.txt')]), isEmpty);
    });

    test('a single path, or none at all, has no collisions', () {
      expect(collidingKeys([p.join('sync', 'a.txt')]), isEmpty);
      expect(collidingKeys(const []), isEmpty);
    });

    test('a three-way collision is still just one key', () {
      final a = p.join('sync', 'a.txt');
      expect(
        collidingKeys([a, p.join('sync', 'A.txt'), p.join('sync', 'A.TXT')]),
        {a.toLowerCase()},
      );
    });
  });

  group('R4-4: case collisions on disk are skipped entirely, not touched', () {
    test('a real file plus an injected case-colliding path: no server call '
        'for either — the collision skip does not need a real '
        'case-sensitive host to be exercised (teeth: disabling the skip in '
        '_classify makes this fail on an unexpected uploadFile call)',
        () async {
      File(p.join(tempDir.path, 'a.txt')).writeAsStringSync('one');
      stateful([]);
      // Stands in for the second disk entry a real walk could only produce
      // on a case-sensitive filesystem — see LocalChangeScanner
      // .debugInjectExtraDiskFile's doc comment. Goes through the exact
      // same collidingKeys() call _classify makes on a real walk's result.
      scanner.debugInjectExtraDiskFile(p.join(tempDir.path, 'A.txt'));

      final pushed = await scanner.scanOnce(tempDir.path);

      expect(pushed, 0);
      verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')));
      verifyNever(() => mockFileRepository.createFolder(any(), any(), originDeviceId: any(named: 'originDeviceId')));
      verifyNever(() => mockFileRepository.deleteFile(any(), originDeviceId: any(named: 'originDeviceId')));
      verifyNever(() => mockFileRepository.renameFile(any(), any(), originDeviceId: any(named: 'originDeviceId')));
      verifyNever(() => mockFileRepository.moveFile(any(), any(), originDeviceId: any(named: 'originDeviceId')));
    });

    test('a tracked file whose name collides on disk is not taken for '
        'deleted: its mirror row and its server file are left alone '
        '(PR #14 review round 5)', () async {
      final tracked = File(p.join(tempDir.path, 'a.txt'))..writeAsStringSync('one');
      stateful([
        SyncMirrorEntry(
          serverId: 'tracked-a',
          localPath: tracked.path,
          isFolder: false,
          sizeBytes: 3,
          contentHash: hashOf('one'),
          updatedAt: past,
          syncedAt: future,
        ),
      ]);
      scanner.debugInjectExtraDiskFile(p.join(tempDir.path, 'A.txt'));

      final pushed = await scanner.scanOnce(tempDir.path);

      expect(pushed, 0);
      verifyNever(() => mockFileRepository.deleteFile(any(), originDeviceId: any(named: 'originDeviceId')));
      verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')));
      verifyNever(() => mockFileRepository.uploadNewVersion(any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken')));
    });

    test(
      'a real filesystem case collision: no server call for either file',
      () async {
        File(p.join(tempDir.path, 'a.txt')).writeAsStringSync('one');
        File(p.join(tempDir.path, 'A.txt')).writeAsStringSync('two');
        stateful([]);

        final pushed = await scanner.scanOnce(tempDir.path);

        expect(pushed, 0);
        verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any(), originDeviceId: any(named: 'originDeviceId'), cancelToken: any(named: 'cancelToken'), onNodeCreated: any(named: 'onNodeCreated')));
        verifyNever(() => mockFileRepository.createFolder(any(), any(), originDeviceId: any(named: 'originDeviceId')));
      },
      // Only a case-sensitive filesystem can hold both spellings at once —
      // this host cannot, so the two writeAsStringSync calls above would
      // just overwrite the same file and the test would pass for the wrong
      // reason. Runs for real on Linux CI (see CLAUDE.md: "CI is Linux
      // (case-sensitive)").
      skip: _isCaseInsensitiveHost ? 'host filesystem is case-insensitive' : false,
    );
  });

  group('cloud-only entries', () {
    test('CloudOnly_NoFileOnDisk_IsNotPushedAsDelete', () async {
      // The data-loss case: a cloud-only file/folder has a mirror row but,
      // by design, nothing on disk. Reading that as "deleted locally" would
      // trash the user's cloud copy.
      final mirror = stateful([
        SyncMirrorEntry(serverId: 'cloud-file', localPath: p.join(tempDir.path, 'remote.txt'),
          isFolder: false, sizeBytes: 5, updatedAt: past, syncedAt: past, downloaded: false),
        SyncMirrorEntry(serverId: 'cloud-dir', localPath: p.join(tempDir.path, 'Docs'),
          isFolder: true, updatedAt: past, syncedAt: past, downloaded: false),
        SyncMirrorEntry(serverId: 'cloud-nested', localPath: p.join(tempDir.path, 'Docs', 'inner.txt'),
          isFolder: false, sizeBytes: 5, updatedAt: past, syncedAt: past, downloaded: false),
      ]);

      final pushed = await scanner.scanOnce(tempDir.path);

      expect(pushed, 0);
      verifyNever(() => mockFileRepository.deleteFile(any(), originDeviceId: any(named: 'originDeviceId')));
      expect(mirror.rows.map((e) => e.serverId), containsAll(['cloud-file', 'cloud-dir', 'cloud-nested']));
    });

    test('DownloadedNextToCloudOnly_MissingDownloadedStillPushedAsDelete', () async {
      // Teeth check: the exclusion must be per row, not a blanket "skip
      // deletes" - a downloaded file the user removed is still a delete.
      stateful([
        SyncMirrorEntry(serverId: 'cloud-file', localPath: p.join(tempDir.path, 'remote.txt'),
          isFolder: false, sizeBytes: 5, updatedAt: past, syncedAt: past, downloaded: false),
        SyncMirrorEntry(serverId: 'local-gone', localPath: p.join(tempDir.path, 'gone.txt'),
          isFolder: false, sizeBytes: 5, contentHash: 'h', updatedAt: past, syncedAt: past),
      ]);
      when(() => mockFileRepository.deleteFile('local-gone', originDeviceId: any(named: 'originDeviceId')))
          .thenAnswer((_) async {});

      expect(await scanner.scanOnce(tempDir.path), 1);

      verify(() => mockFileRepository.deleteFile('local-gone', originDeviceId: 'dev-1')).called(1);
      verifyNever(() => mockFileRepository.deleteFile('cloud-file', originDeviceId: any(named: 'originDeviceId')));
    });
  });
}

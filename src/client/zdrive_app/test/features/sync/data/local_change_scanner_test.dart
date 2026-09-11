import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zdrive_app/features/files/domain/file_item.dart';
import 'package:zdrive_app/features/files/domain/file_repository.dart';
import 'package:zdrive_app/features/sync/data/device_registration_service.dart';
import 'package:zdrive_app/features/sync/data/local_change_scanner.dart';
import 'package:zdrive_app/features/sync/data/push_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sqflite_sync_mirror_repository.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_entry.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_repository.dart';

class MockSyncMirrorRepository extends Mock implements SyncMirrorRepository {}

class MockFileRepository extends Mock implements FileRepository {}

class MockDeviceRegistrationService extends Mock implements DeviceRegistrationService {}

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

class FakeSyncMirrorEntry extends Fake implements SyncMirrorEntry {}

class FakeOutboxItem extends Fake implements OutboxItem {}

/// Wires [mock]'s getChildrenUnder/upsert/deleteByServerId/getCursor/commit
/// to one mutable row list plus an in-memory outbox, so a test sees exactly
/// what the scanner's own mirror calls left behind — not a hand-picked
/// "after" snapshot the test re-stubs itself, which would hide a regression
/// where the scanner forgets to write a row, or forgets to enqueue a report,
/// at all. [commit] here mirrors SqfliteSyncMirrorRepository.commit's own
/// semantics (rePath, then upserts, then deletes, then deleteUnderPath, then
/// enqueue) closely enough for that purpose, without being a second
/// implementation of its SQL.
class _StatefulMirror {
  final List<SyncMirrorEntry> rows;
  final List<OutboxItem> outbox = [];
  int _nextOutboxId = 1;

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
          enqueue: any(named: 'enqueue'),
        )).thenAnswer((inv) async {
      final upserts = inv.namedArguments[#upserts] as List<SyncMirrorEntry>? ?? const [];
      final deleteServerIds = inv.namedArguments[#deleteServerIds] as List<String>? ?? const [];
      final deleteUnderPath = inv.namedArguments[#deleteUnderPath] as String?;
      final rePath = inv.namedArguments[#rePath] as ({String from, String to})?;
      final enqueue = inv.namedArguments[#enqueue] as List<OutboxItem>? ?? const [];

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
      for (final item in enqueue) {
        outbox.add(OutboxItem(
          id: _nextOutboxId++,
          fileId: item.fileId,
          type: item.type,
          baseCursor: item.baseCursor,
          createdAt: item.createdAt,
        ));
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
      );

  SyncMirrorEntry? row(String serverId) => rows.where((e) => e.serverId == serverId).firstOrNull;

  List<OutboxItem> outboxFor(String fileId) => outbox.where((o) => o.fileId == fileId).toList();
}

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
    registerFallbackValue(FakeOutboxItem());
    registerFallbackValue(<SyncMirrorEntry>[]);
    registerFallbackValue(<String>[]);
    registerFallbackValue(<OutboxItem>[]);
    registerFallbackValue(const Stream<List<int>>.empty());
  });

  setUp(() {
    mockMirror = MockSyncMirrorRepository();
    mockFileRepository = MockFileRepository();
    mockDeviceRegistration = MockDeviceRegistrationService();
    scanner = scannerWith(isWindows: false);
    tempDir = Directory.systemTemp.createTempSync('local_change_scanner_test_');

    when(() => mockDeviceRegistration.ensureRegistered()).thenAnswer((_) async => 'dev-1');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('new file at root: uploads, commits the mirror, enqueues a create',
      () async {
    final file = File(p.join(tempDir.path, 'new.txt'))..writeAsStringSync('hello');
    final mirror = stateful([]);
    when(() => mockFileRepository.uploadFile(any(that: isNull), 'new.txt', any(), 5, any()))
        .thenAnswer((_) async => 'file-1');

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    final upserted = mirror.row('file-1')!;
    expect(upserted.localPath, file.path);
    expect(upserted.isFolder, isFalse);
    expect(upserted.sizeBytes, 5);
    expect(upserted.contentHash, hashOf('hello'));
    expect(mirror.outboxFor('file-1').single.type, SyncChangeType.create);
  });

  test('new file inside a new subfolder: creates the folder first (plain '
      'upsert, not enqueued), then uploads into it', () async {
    final subDir = Directory(p.join(tempDir.path, 'sub'))..createSync();
    File(p.join(subDir.path, 'new.txt')).writeAsStringSync('x');
    final mirror = stateful([]);
    when(() => mockFileRepository.createFolder(null, 'sub')).thenAnswer((_) async => FileItem(
          id: 'folder-1',
          name: 'sub',
          isFolder: true,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockFileRepository.uploadFile('folder-1', 'new.txt', any(), 1, any()))
        .thenAnswer((_) async => 'file-2');

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    verifyInOrder([
      () => mockFileRepository.createFolder(null, 'sub'),
      () => mockFileRepository.uploadFile('folder-1', 'new.txt', any(), 1, any()),
    ]);
    expect(mirror.row('folder-1'), isNotNull);
    expect(mirror.outboxFor('folder-1'), isEmpty); // folder creation is never reported
    expect(mirror.outboxFor('file-2').single.type, SyncChangeType.create);
  });

  test('tracked file edited (different bytes): uploads a new version, '
      'enqueues an update; no create, no delete', () async {
    final file = File(p.join(tempDir.path, 'tracked.txt'))
      ..writeAsStringSync('a longer new body');
    final mirror = stateful([
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
    when(() => mockFileRepository.uploadNewVersion('file-3', 'tracked.txt', any(), 17))
        .thenAnswer((_) async {});

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    verify(() => mockFileRepository.uploadNewVersion('file-3', 'tracked.txt', any(), 17))
        .called(1);
    expect(mirror.outboxFor('file-3').single.type, SyncChangeType.update);
    verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any()));
    verifyNever(() => mockFileRepository.deleteFile(any()));
  });

  test('tracked file unchanged (same size, not modified since it was last '
      'synced): no server calls at all', () async {
    final file = File(p.join(tempDir.path, 'same.txt'))..writeAsStringSync('same');
    final mirror = stateful([
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
    verifyNever(() => mockFileRepository.uploadNewVersion(any(), any(), any(), any()));
    verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any()));
    verifyNever(() => mockFileRepository.deleteFile(any()));
    verifyNever(() => mockMirror.commit(
          upserts: any(named: 'upserts'),
          deleteServerIds: any(named: 'deleteServerIds'),
          deleteUnderPath: any(named: 'deleteUnderPath'),
          rePath: any(named: 'rePath'),
          enqueue: any(named: 'enqueue'),
        ));
    expect(mirror.outbox, isEmpty);
  });

  test('tracked file deleted: deletes server-side, removes the mirror row, '
      'enqueues a delete', () async {
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
    when(() => mockFileRepository.deleteFile('file-5')).thenAnswer((_) async {});

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    verify(() => mockFileRepository.deleteFile('file-5')).called(1);
    expect(mirror.row('file-5'), isNull);
    expect(mirror.outboxFor('file-5').single.type, SyncChangeType.delete);
  });

  test('tracked file renamed in place (same bytes): renames only — no '
      'upload, no delete; mirror path updated; enqueues a rename', () async {
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
    when(() => mockFileRepository.renameFile('file-6', 'new.txt')).thenAnswer((_) async => FileItem(
          id: 'file-6',
          name: 'new.txt',
          isFolder: false,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    verify(() => mockFileRepository.renameFile('file-6', 'new.txt')).called(1);
    verifyNever(() => mockFileRepository.moveFile(any(), any()));
    verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any()));
    verifyNever(() => mockFileRepository.deleteFile(any()));
    expect(mirror.row('file-6')!.localPath, newFile.path);
    expect(mirror.outboxFor('file-6').single.type, SyncChangeType.rename);
  });

  test('tracked file moved into another tracked folder: moves only, '
      'enqueues a move', () async {
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
    when(() => mockFileRepository.moveFile('file-7', 'sub-id')).thenAnswer((_) async => FileItem(
          id: 'file-7',
          name: 'file.txt',
          isFolder: false,
          parentId: 'sub-id',
          createdAt: now,
          updatedAt: now,
        ));

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    verify(() => mockFileRepository.moveFile('file-7', 'sub-id')).called(1);
    verifyNever(() => mockFileRepository.renameFile(any(), any()));
    expect(mirror.row('file-7')!.localPath, movedFile.path);
    expect(mirror.outboxFor('file-7').single.type, SyncChangeType.move);
  });

  test('moved and renamed: moves first, then renames; both enqueued in that '
      'order', () async {
    final subDir = Directory(p.join(tempDir.path, 'sub'))..createSync();
    final oldPath = p.join(tempDir.path, 'old.txt'); // no longer on disk
    File(p.join(subDir.path, 'new.txt')).writeAsStringSync('payload');
    final mirror = stateful([
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
    when(() => mockFileRepository.moveFile('file-8', 'sub-id')).thenAnswer((_) async => FileItem(
          id: 'file-8',
          name: 'old.txt',
          isFolder: false,
          parentId: 'sub-id',
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockFileRepository.renameFile('file-8', 'new.txt')).thenAnswer((_) async => FileItem(
          id: 'file-8',
          name: 'new.txt',
          isFolder: false,
          parentId: 'sub-id',
          createdAt: now,
          updatedAt: now,
        ));

    await scanner.scanOnce(tempDir.path);

    verifyInOrder([
      () => mockFileRepository.moveFile('file-8', 'sub-id'),
      () => mockFileRepository.renameFile('file-8', 'new.txt'),
    ]);
    expect(mirror.outboxFor('file-8').map((o) => o.type), [SyncChangeType.move, SyncChangeType.rename]);
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
    when(() => mockFileRepository.uploadFile(any(that: isNull), 'newdupe.txt', any(), 14, any()))
        .thenAnswer((_) async => 'newdupe-id');
    when(() => mockFileRepository.deleteFile('dupeA-id')).thenAnswer((_) async {});
    when(() => mockFileRepository.deleteFile('dupeB-id')).thenAnswer((_) async {});

    await scanner.scanOnce(tempDir.path);

    verifyNever(() => mockFileRepository.moveFile(any(), any()));
    verifyNever(() => mockFileRepository.renameFile(any(), any()));
    verify(() => mockFileRepository.uploadFile(any(that: isNull), 'newdupe.txt', any(), 14, any())).called(1);
    verify(() => mockFileRepository.deleteFile('dupeA-id')).called(1);
    verify(() => mockFileRepository.deleteFile('dupeB-id')).called(1);
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
    when(() => mockFileRepository.uploadFile(any(that: isNull), 'emptyNew.txt', any(), 0, any()))
        .thenAnswer((_) async => 'emptyNew-id');
    when(() => mockFileRepository.deleteFile('empty-id')).thenAnswer((_) async {});

    await scanner.scanOnce(tempDir.path);

    verifyNever(() => mockFileRepository.moveFile(any(), any()));
    verifyNever(() => mockFileRepository.renameFile(any(), any()));
    verify(() => mockFileRepository.uploadFile(any(that: isNull), 'emptyNew.txt', any(), 0, any())).called(1);
    verify(() => mockFileRepository.deleteFile('empty-id')).called(1);
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
    when(() => mockFileRepository.deleteFile('proj-id')).thenAnswer((_) async {});

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    verify(() => mockFileRepository.deleteFile('proj-id')).called(1);
    verifyNever(() => mockFileRepository.deleteFile('a-id'));
    verifyNever(() => mockFileRepository.deleteFile('b-id'));
    verifyNever(() => mockFileRepository.deleteFile('sub-id'));
    expect(mirror.rows, isEmpty);
    expect(mirror.outboxFor('proj-id').single.type, SyncChangeType.delete);
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
    verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any()));
    verifyNever(() => mockFileRepository.createFolder(any(), any()));
  });

  test('new file 409 (name already exists server-side): uploads a new '
      'version into the existing file, enqueues an update', () async {
    File(p.join(tempDir.path, 'shared.txt')).writeAsStringSync('local content');
    final mirror = stateful([]);
    when(() => mockFileRepository.uploadFile(any(that: isNull), 'shared.txt', any(), 13, any()))
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
    when(() => mockFileRepository.uploadNewVersion('existing-id', 'shared.txt', any(), 13))
        .thenAnswer((_) async {});

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    verify(() => mockFileRepository.uploadNewVersion('existing-id', 'shared.txt', any(), 13))
        .called(1);
    expect(mirror.outboxFor('existing-id').single.type, SyncChangeType.update);
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
    when(() => mockFileRepository.uploadNewVersion('stale-id', 'edited.txt', any(), 17))
        .thenThrow(dioError(404));
    when(() => mockFileRepository.uploadFile(any(that: isNull), 'edited.txt', any(), 17, any()))
        .thenAnswer((_) async => 'fresh-id');

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    verify(() => mockFileRepository.uploadFile(any(that: isNull), 'edited.txt', any(), 17, any())).called(1);
    expect(mirror.row('stale-id'), isNull);
    expect(mirror.row('fresh-id')!.localPath, file.path);
    expect(mirror.outboxFor('fresh-id').single.type, SyncChangeType.create);
  });

  test('one failing upload does not stop the next file; the failed path is '
      'skipped on an immediate second scan (backoff)', () async {
    File(p.join(tempDir.path, 'bad.txt')).writeAsStringSync('will fail');
    File(p.join(tempDir.path, 'good.txt')).writeAsStringSync('will succeed');
    final mirror = stateful([]);
    when(() => mockFileRepository.uploadFile(any(that: isNull), 'bad.txt', any(), 9, any()))
        .thenThrow(Exception('network dropped'));
    when(() => mockFileRepository.uploadFile(any(that: isNull), 'good.txt', any(), 12, any()))
        .thenAnswer((_) async => 'good-id');

    final firstPushed = await scanner.scanOnce(tempDir.path);
    expect(firstPushed, 1); // only good.txt landed
    expect(mirror.outboxFor('good-id').single.type, SyncChangeType.create);

    // Second, immediate scan: bad.txt is still a "new file" from the
    // mirror's point of view (it was never committed), but backoff must
    // skip it rather than retrying the same failure straight away. The
    // good.txt row is exactly what scan 1's own commit call left behind —
    // untouched by the test.
    clearInteractions(mockFileRepository);

    final secondPushed = await scanner.scanOnce(tempDir.path);

    expect(secondPushed, 0);
    verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any()));
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
    verifyNever(() => mockFileRepository.uploadNewVersion(any(), any(), any(), any()));
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
    verifyNever(() => mockFileRepository.deleteFile(any()));
    verifyNever(() => mockFileRepository.uploadNewVersion(any(), any(), any(), any()));
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
      when(() => mockFileRepository.renameFile('a-id', 'A.txt')).thenAnswer((_) async => FileItem(
            id: 'a-id',
            name: 'A.txt',
            isFolder: false,
            parentId: null,
            createdAt: now,
            updatedAt: now,
          ));

      final pushed = await scanner.scanOnce(tempDir.path);

      expect(pushed, 1);
      verify(() => mockFileRepository.renameFile('a-id', 'A.txt')).called(1);
      verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any()));
      verifyNever(() => mockFileRepository.deleteFile(any()));
      verifyNever(() => mockFileRepository.moveFile(any(), any()));
      expect(mirror.row('a-id')!.localPath, newFile.path);
      expect(mirror.outboxFor('a-id').single.type, SyncChangeType.rename);
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
      when(() => mockFileRepository.renameFile('docs-id', 'docs')).thenAnswer((_) async => FileItem(
            id: 'docs-id',
            name: 'docs',
            isFolder: true,
            parentId: null,
            createdAt: now,
            updatedAt: now,
          ));

      final pushed = await scanner.scanOnce(tempDir.path);

      expect(pushed, 1);
      verify(() => mockFileRepository.renameFile('docs-id', 'docs')).called(1);
      verifyNever(() => mockFileRepository.createFolder(any(), any()));
      verifyNever(() => mockFileRepository.deleteFile(any()));
      verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any()));
      expect(mirror.row('docs-id')!.localPath, docsDir.path);
      expect(mirror.row('child-id')!.localPath, p.join(docsDir.path, 'x.txt'));
      expect(mirror.outboxFor('docs-id').single.type, SyncChangeType.rename);
      expect(mirror.outboxFor('child-id'), isEmpty); // the child itself was never renamed
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
      when(() => mockFileRepository.renameFile('docs-id', 'docs')).thenThrow(Exception('server unreachable'));

      final firstPushed = await scanner.scanOnce(tempDir.path);
      expect(firstPushed, 0);
      verifyNever(() => mockFileRepository.deleteFile(any()));
      verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any()));
      verifyNever(() => mockFileRepository.uploadNewVersion(any(), any(), any(), any()));
      verifyNever(() => mockFileRepository.createFolder(any(), any()));

      scanner.debugClearBackoff();
      clearInteractions(mockFileRepository);
      when(() => mockFileRepository.renameFile('docs-id', 'docs')).thenThrow(Exception('still unreachable'));

      final secondPushed = await scanner.scanOnce(tempDir.path);
      expect(secondPushed, 0);
      verifyNever(() => mockFileRepository.deleteFile(any()));
      verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any()));
      verifyNever(() => mockFileRepository.uploadNewVersion(any(), any(), any(), any()));
      verifyNever(() => mockFileRepository.createFolder(any(), any()));
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
      when(() => mockFileRepository.moveFile('file-a', 'sub-id'))
          .thenThrow(Exception('network dropped'));

      await scanner.scanOnce(tempDir.path);

      verifyNever(() => mockFileRepository.deleteFile(any()));
      verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any()));
      expect(mirror.row('file-a')!.localPath, oldPath);
      expect(mirror.outboxFor('file-a'), isEmpty);
    });

    test('move succeeds but rename throws: neither is enqueued this scan '
        '(the commit that would enqueue both never runs); a retried scan '
        'with getFile now reflecting the already-moved parent skips '
        'moveFile, calls only renameFile, and enqueues both', () async {
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
      when(() => mockFileRepository.moveFile('file-b', 'sub-id')).thenAnswer((_) async => FileItem(
            id: 'file-b',
            name: 'old.txt',
            isFolder: false,
            parentId: 'sub-id',
            createdAt: now,
            updatedAt: now,
          ));
      when(() => mockFileRepository.renameFile('file-b', 'new.txt'))
          .thenThrow(Exception('server unreachable'));

      await scanner.scanOnce(tempDir.path);

      verify(() => mockFileRepository.moveFile('file-b', 'sub-id')).called(1);
      verifyNever(() => mockFileRepository.deleteFile(any()));
      expect(mirror.row('file-b')!.localPath, oldPath); // commit never ran
      expect(mirror.outboxFor('file-b'), isEmpty);

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
      when(() => mockFileRepository.renameFile('file-b', 'new.txt')).thenAnswer((_) async => FileItem(
            id: 'file-b',
            name: 'new.txt',
            isFolder: false,
            parentId: 'sub-id',
            createdAt: now,
            updatedAt: now,
          ));

      await scanner.scanOnce(tempDir.path);

      verifyNever(() => mockFileRepository.moveFile(any(), any()));
      verify(() => mockFileRepository.renameFile('file-b', 'new.txt')).called(1);
      // The local diff still says "moved and renamed" (the mirror row was
      // never updated by the failed first attempt), so both are reported —
      // a duplicate move report is harmless, pull reconciles via getFile.
      expect(mirror.outboxFor('file-b').map((o) => o.type), [SyncChangeType.move, SyncChangeType.rename]);
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

      verifyNever(() => mockFileRepository.deleteFile('file-c'));
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
    verifyNever(() => mockFileRepository.moveFile(any(), any()));
    verifyNever(() => mockFileRepository.renameFile(any(), any()));
    verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any()));
    expect(mirror.row('file-g11'), isNull);
    expect(mirror.outbox, isEmpty);
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
    when(() => mockFileRepository.deleteFile('file-u12')).thenAnswer((_) async {});
    // Backed off so _hashFiles never attempts to hash it (same seam the F2
    // "unreadable new file" test above uses), landing it in the
    // unhashed-new-files check — and forced to report an unknown size
    // there. File.stat() cannot actually throw; it returns size == -1 for
    // a vanished/unreadable file, which a portable test cannot reliably
    // race into existing here (see debugForceUnknownSize's doc comment).
    scanner.debugBackOff(newFile.path);
    scanner.debugForceUnknownSize(newFile.path);

    await scanner.scanOnce(tempDir.path);

    verifyNever(() => mockFileRepository.deleteFile('file-u12'));
  });

  test('finding 2 (folder delete 404): a retried deleteFile 404s once the '
      'server already trashed the folder — still commits, clearing the '
      'mirror row and everything under it, and enqueues the delete', () async {
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
    when(() => mockFileRepository.deleteFile('proj9-id')).thenThrow(dioError(404));

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 0); // already gone server-side too; not a new push
    expect(mirror.rows, isEmpty);
    expect(mirror.outboxFor('proj9-id').single.type, SyncChangeType.delete);
  });

  group('scan 5 / integration: the scan never depends on SyncService being '
      'reachable — sending is the drain\'s job, run separately', () {
    test('upload new version, then a failing push: exactly one server '
        'write across two scans; the mirror is updated by scan 1; the '
        'outbox is drained (and emptied) only once a push finally succeeds',
        () async {
      // Real repository + real PushSyncService talking to a mocked
      // SyncRemoteDataSource — this is the property the outbox design
      // exists for, and a StatefulMirror fake cannot exercise the real
      // drain-and-persist path the way SqfliteSyncMirrorRepository does.
      final mirror = SqfliteSyncMirrorRepository.withDbPath(inMemoryDatabasePath);
      final scanner = LocalChangeScanner(mirror, mockFileRepository, mockDeviceRegistration);
      final mockDataSource = MockSyncRemoteDataSource();
      final push = PushSyncService(mockDataSource, mockDeviceRegistration, mirror);

      final file = File(p.join(tempDir.path, 'tracked1.txt'))
        ..writeAsStringSync('a longer new body');
      await mirror.upsert(SyncMirrorEntry(
        serverId: 'file-v1',
        localPath: file.path,
        isFolder: false,
        sizeBytes: 3, // old content's length
        contentHash: hashOf('old'),
        updatedAt: past,
        syncedAt: past,
      ));
      when(() => mockFileRepository.uploadNewVersion('file-v1', 'tracked1.txt', any(), 17))
          .thenAnswer((_) async {});

      final firstScanPushed = await scanner.scanOnce(tempDir.path);
      expect(firstScanPushed, 1);
      expect((await mirror.getByServerId('file-v1'))!.contentHash, hashOf('a longer new body'));
      expect(await mirror.outboxCount(), 1);

      when(() => mockDataSource.push('dev-1', any(), baseCursor: any(named: 'baseCursor')))
          .thenThrow(Exception('SyncService unreachable'));
      final firstDrainSent = await push.drainOutbox();
      expect(firstDrainSent, 0);
      expect(await mirror.outboxCount(), 1);

      // Scan 2: nothing changed on disk since scan 1's own write updated
      // the mirror's hash — no second uploadNewVersion.
      clearInteractions(mockFileRepository);
      final secondScanPushed = await scanner.scanOnce(tempDir.path);
      expect(secondScanPushed, 0);
      verifyNever(() => mockFileRepository.uploadNewVersion(any(), any(), any(), any()));

      when(() => mockDataSource.push('dev-1', any(), baseCursor: any(named: 'baseCursor')))
          .thenAnswer((_) async => {});
      final secondDrainSent = await push.drainOutbox();
      expect(secondDrainSent, 1);
      expect(await mirror.outboxCount(), 0);
      // Called twice in total across the two drain attempts (the first one
      // threw) — always with the exact same request, since the outbox row
      // itself was only ever written once by scan 1.
      verify(() => mockDataSource.push(
            'dev-1',
            [
              {'fileId': 'file-v1', 'eventType': 1, 'metadata': null},
            ],
            baseCursor: 0, // this device's cursor for 'dev-1' was never set
          )).called(2);
    });
  });
}

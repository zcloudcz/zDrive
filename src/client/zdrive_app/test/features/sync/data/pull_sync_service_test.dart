import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:zdrive_app/features/files/domain/file_item.dart';
import 'package:zdrive_app/features/files/domain/file_repository.dart';
import 'package:zdrive_app/features/sync/data/device_registration_service.dart';
import 'package:zdrive_app/features/sync/data/pull_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_entry.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_repository.dart';

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

class MockDeviceRegistrationService extends Mock implements DeviceRegistrationService {}

class MockSyncMirrorRepository extends Mock implements SyncMirrorRepository {}

class MockFileRepository extends Mock implements FileRepository {}

class FakeSyncMirrorEntry extends Fake implements SyncMirrorEntry {}

void main() {
  late MockSyncRemoteDataSource mockSyncDataSource;
  late MockDeviceRegistrationService mockDeviceRegistration;
  late MockSyncMirrorRepository mockMirror;
  late MockFileRepository mockFileRepository;
  late PullSyncService service;
  late Directory tempDir;

  setUpAll(() => registerFallbackValue(FakeSyncMirrorEntry()));

  setUp(() {
    mockSyncDataSource = MockSyncRemoteDataSource();
    mockDeviceRegistration = MockDeviceRegistrationService();
    mockMirror = MockSyncMirrorRepository();
    mockFileRepository = MockFileRepository();
    service = PullSyncService(
      mockSyncDataSource,
      mockDeviceRegistration,
      mockMirror,
      mockFileRepository,
      // Pin to Linux-CI behaviour regardless of the host running the test —
      // without this the default inherits Platform.isWindows, and four
      // tests once passed only on Windows (PR #12 review round 4, N6).
      isWindows: false,
    );
    tempDir = Directory.systemTemp.createTempSync('pull_sync_test_');

    when(() => mockDeviceRegistration.ensureRegistered()).thenAnswer((_) async => 'dev-1');
    when(() => mockMirror.setCursor(any(), any())).thenAnswer((_) async {});
    when(() => mockMirror.upsert(any())).thenAnswer((_) async {});
    when(() => mockMirror.clearFailedEvent(any())).thenAnswer((_) async {});
    when(() => mockMirror.recordFailedEvent(any(), any(), any())).thenAnswer((_) async {});
    // Bootstrapped by default so existing event-apply tests don't also have
    // to stub the FileService tree walk — tests that care about bootstrap
    // itself override this to false.
    when(() => mockMirror.isBootstrapped(any())).thenAnswer((_) async => true);
    when(() => mockMirror.markBootstrapped(any())).thenAnswer((_) async {});
    // The retry loop at the top of pullOnce (R3/F5) always calls this now —
    // empty by default so existing tests don't also have to stub it; tests
    // that care about quarantine/retry override it.
    when(() => mockMirror.getFailedEvents()).thenAnswer((_) async => []);
  });

  tearDown(() {
    // The R1 traversal test below deliberately lets a reverted fix delete
    // tempDir itself as part of proving the bug — guard against that so
    // teeth-checking doesn't also throw here.
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Map<String, dynamic> page(List<Map<String, dynamic>> events, int newCursor) =>
      {'events': events, 'newCursor': newCursor};

  test('applies a Create event: downloads the file, writes it under the sync folder, '
      'and advances the cursor', () async {
    final bytes = Uint8List.fromList(utf8.encode('hello world'));
    final now = DateTime.utc(2026, 1, 1);

    when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
    when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
          {'id': 1, 'fileId': 'file-1', 'eventType': 'Create', 'metadata': null},
        ], 1));
    when(() => mockFileRepository.getFile('file-1')).thenAnswer((_) async => FileItem(
          id: 'file-1',
          name: 'doc.txt',
          isFolder: false,
          sizeBytes: bytes.length,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockMirror.getByServerId('file-1')).thenAnswer((_) async => null);
    when(() => mockFileRepository.downloadFile('file-1')).thenAnswer((_) async => bytes);

    final applied = await service.pullOnce(tempDir.path);

    expect(applied, 1);
    final written = File(p.join(tempDir.path, 'doc.txt'));
    expect(written.existsSync(), isTrue);
    expect(written.readAsBytesSync(), bytes);

    final upserted = verify(() => mockMirror.upsert(captureAny())).captured.single
        as SyncMirrorEntry;
    expect(upserted.serverId, 'file-1');
    expect(upserted.localPath, written.path);
    expect(upserted.isFolder, isFalse);
    expect(upserted.contentHash, sha256.convert(bytes).toString());

    verify(() => mockMirror.setCursor('dev-1', 1)).called(1);
  });

  test('applies a Delete event: removes the local file and the mirror row, '
      'and advances the cursor', () async {
    final existingFile = File(p.join(tempDir.path, 'old.txt'))..writeAsStringSync('bye');
    final now = DateTime.utc(2026, 1, 1);

    when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
    when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
          {'id': 1, 'fileId': 'file-2', 'eventType': 'Delete', 'metadata': null},
        ], 1));
    when(() => mockMirror.getByServerId('file-2')).thenAnswer((_) async => SyncMirrorEntry(
          serverId: 'file-2',
          localPath: existingFile.path,
          isFolder: false,
          sizeBytes: 3,
          contentHash: 'irrelevant',
          updatedAt: now,
          syncedAt: now,
        ));
    when(() => mockMirror.deleteByServerId('file-2')).thenAnswer((_) async {});

    final applied = await service.pullOnce(tempDir.path);

    expect(applied, 1);
    expect(existingFile.existsSync(), isFalse);
    verify(() => mockMirror.deleteByServerId('file-2')).called(1);
    verify(() => mockMirror.setCursor('dev-1', 1)).called(1);
  });

  test('does not advance the cursor past an event whose apply failed', () async {
    final bytes = Uint8List.fromList(utf8.encode('ok'));
    final now = DateTime.utc(2026, 1, 1);

    when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
    when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
          {'id': 1, 'fileId': 'file-1', 'eventType': 'Create', 'metadata': null},
          {'id': 2, 'fileId': 'file-2', 'eventType': 'Create', 'metadata': null},
        ], 2));
    when(() => mockFileRepository.getFile('file-1')).thenAnswer((_) async => FileItem(
          id: 'file-1',
          name: 'ok.txt',
          isFolder: false,
          sizeBytes: bytes.length,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockMirror.getByServerId('file-1')).thenAnswer((_) async => null);
    when(() => mockFileRepository.downloadFile('file-1')).thenAnswer((_) async => bytes);
    // The second event's lookup fails outright (e.g. a dropped connection —
    // not a 404, which pullOnce treats as "already deleted, reconcile" and
    // is exercised by the Create/Delete tests above).
    when(() => mockFileRepository.getFile('file-2')).thenThrow(Exception('network down'));

    await expectLater(service.pullOnce(tempDir.path), throwsA(isA<Exception>()));

    // Event 1 fully landed (file written, mirror row upserted) before event 2
    // was attempted, so its cursor commit must have happened...
    verify(() => mockMirror.setCursor('dev-1', 1)).called(1);
    // ...but event 2 never landed, so the cursor must never move past it.
    verifyNever(() => mockMirror.setCursor('dev-1', 2));
  });

  test('rejects a traversal name: quarantines the event instead of writing '
      'outside the sync folder (F1)', () async {
    final now = DateTime.utc(2026, 1, 1);

    when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
    when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
          {'id': 1, 'fileId': 'evil-1', 'eventType': 'Create', 'metadata': null},
        ], 1));
    // A name that would otherwise let p.join escape the sync folder — see
    // the PR #12 review's `..\..\..\Documents` / `C:\Users\...` examples.
    when(() => mockFileRepository.getFile('evil-1')).thenAnswer((_) async => FileItem(
          id: 'evil-1',
          name: '../../evil.txt',
          isFolder: false,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockMirror.getByServerId('evil-1')).thenAnswer((_) async => null);

    final applied = await service.pullOnce(tempDir.path);

    // The event was still "applied" in pullOnce's counting sense — it was
    // handled, just quarantined rather than written.
    expect(applied, 1);
    // The name was rejected before any filesystem call — nothing was ever
    // downloaded or written, inside the sync folder or outside it.
    verifyNever(() => mockFileRepository.downloadFile(any()));

    verify(() => mockMirror.recordFailedEvent(
          'evil-1',
          1,
          any(that: contains('unsafe remote name')),
        )).called(1);
    // Quarantined, not blocked: the cursor still advances past it.
    verify(() => mockMirror.setCursor('dev-1', 1)).called(1);
  });

  test('rejects a dots-and-spaces folder name: Win32 trims the trailing '
      'space so it resolves back onto the sync root itself, not merely '
      'outside it, and a real Delete for it must not reach the root (R1 '
      'round 2)', () async {
    final now = DateTime.utc(2026, 1, 1);
    final marker = File(p.join(tempDir.path, 'important.txt'))
      ..writeAsStringSync('do not delete me');

    // A minimal stateful stand-in for the mirror row this fileId would get,
    // so the Delete event below sees whatever the Create event actually
    // stored — exactly like the real sqflite-backed repository would, and
    // unlike a bare stub that can't reflect that without this.
    SyncMirrorEntry? stored;
    when(() => mockMirror.getByServerId('evil-2')).thenAnswer((_) async => stored);
    when(() => mockMirror.upsert(any())).thenAnswer((invocation) async {
      final entry = invocation.positionalArguments[0] as SyncMirrorEntry;
      if (entry.serverId == 'evil-2') stored = entry;
    });
    when(() => mockMirror.deleteByServerId('evil-2')).thenAnswer((_) async {
      stored = null;
    });

    when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
    when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
          {'id': 1, 'fileId': 'evil-2', 'eventType': 'Create', 'metadata': null},
          {'id': 2, 'fileId': 'evil-2', 'eventType': 'Delete', 'metadata': null},
        ], 2));
    // ".. " is not the literal ".." this app already rejected — it is a
    // folder Win32 treats the same way once trailing dots/spaces are
    // trimmed, and p.canonicalize/p.isWithin do not catch that (see
    // _isPlainSegment's doc comment).
    when(() => mockFileRepository.getFile('evil-2')).thenAnswer((_) async => FileItem(
          id: 'evil-2',
          name: '.. ',
          isFolder: true,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));

    final applied = await service.pullOnce(tempDir.path);

    expect(applied, 2);
    // The Create was quarantined before any mirror row was ever recorded
    // for it, so the Delete that followed had nothing to act on — the sync
    // folder and everything already in it are untouched.
    verify(() => mockMirror.recordFailedEvent(
          'evil-2',
          1,
          any(that: contains('unsafe remote name')),
        )).called(1);
    expect(tempDir.existsSync(), isTrue);
    expect(marker.existsSync(), isTrue);
    expect(marker.readAsStringSync(), 'do not delete me');
  });

  test('renames a folder in place instead of recreating it, preserving '
      'children that have no sync event of their own (F2)', () async {
    final now = DateTime.utc(2026, 1, 1);
    final oldDir = Directory(p.join(tempDir.path, 'oldName'))..createSync();
    File(p.join(oldDir.path, 'child.txt')).writeAsStringSync('untouched by any event');
    final newDir = p.join(tempDir.path, 'newName');

    when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
    when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
          {'id': 1, 'fileId': 'folder-1', 'eventType': 'Rename', 'metadata': null},
        ], 1));
    when(() => mockFileRepository.getFile('folder-1')).thenAnswer((_) async => FileItem(
          id: 'folder-1',
          name: 'newName',
          isFolder: true,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockMirror.getByServerId('folder-1')).thenAnswer((_) async => SyncMirrorEntry(
          serverId: 'folder-1',
          localPath: oldDir.path,
          isFolder: true,
          updatedAt: now,
          syncedAt: now,
        ));
    when(() => mockMirror.rePathChildren(any(), any())).thenAnswer((_) async {});

    await service.pullOnce(tempDir.path);

    expect(oldDir.existsSync(), isFalse);
    expect(File(p.join(newDir, 'child.txt')).readAsStringSync(), 'untouched by any event');
    verify(() => mockMirror.rePathChildren(oldDir.path, newDir)).called(1);

    final upserted = verify(() => mockMirror.upsert(captureAny())).captured.single
        as SyncMirrorEntry;
    expect(upserted.serverId, 'folder-1');
    expect(upserted.localPath, newDir);
  });

  test('a local file pull did not write is left alone, and the event is '
      'quarantined instead of overwriting it (F3)', () async {
    final now = DateTime.utc(2026, 1, 1);
    final untrackedFile = File(p.join(tempDir.path, 'existing.txt'))
      ..writeAsStringSync('the user already had this');

    when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
    when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
          {'id': 1, 'fileId': 'file-5', 'eventType': 'Create', 'metadata': null},
        ], 1));
    when(() => mockFileRepository.getFile('file-5')).thenAnswer((_) async => FileItem(
          id: 'file-5',
          name: 'existing.txt',
          isFolder: false,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));
    // Never pulled locally before — this is the "untracked" branch of the
    // conflict check, not the "edited since" branch.
    when(() => mockMirror.getByServerId('file-5')).thenAnswer((_) async => null);

    final applied = await service.pullOnce(tempDir.path);

    expect(applied, 1);
    verifyNever(() => mockFileRepository.downloadFile('file-5'));
    expect(untrackedFile.readAsStringSync(), 'the user already had this');

    verify(() => mockMirror.recordFailedEvent(
          'file-5',
          1,
          any(that: contains('local conflict')),
        )).called(1);
    verify(() => mockMirror.setCursor('dev-1', 1)).called(1);
  });

  test('a file move deletes the stale copy before committing the mirror '
      'row, not after — a crash right after would otherwise leave an '
      'orphaned duplicate forever (F6)', () async {
    final now = DateTime.utc(2026, 1, 1);
    final bytes = Uint8List.fromList(utf8.encode('content'));
    final oldFile = File(p.join(tempDir.path, 'old-name.txt'))..writeAsStringSync('content');

    when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
    when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
          {'id': 1, 'fileId': 'file-1', 'eventType': 'Rename', 'metadata': null},
        ], 1));
    when(() => mockFileRepository.getFile('file-1')).thenAnswer((_) async => FileItem(
          id: 'file-1',
          name: 'new-name.txt',
          isFolder: false,
          sizeBytes: bytes.length,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockMirror.getByServerId('file-1')).thenAnswer((_) async => SyncMirrorEntry(
          serverId: 'file-1',
          localPath: oldFile.path,
          isFolder: false,
          contentHash: sha256.convert(bytes).toString(),
          updatedAt: now,
          syncedAt: now,
        ));
    when(() => mockFileRepository.downloadFile('file-1')).thenAnswer((_) async => bytes);
    // Simulates a crash between the disk write and the mirror commit.
    when(() => mockMirror.upsert(any())).thenThrow(Exception('simulated crash'));

    await expectLater(service.pullOnce(tempDir.path), throwsA(isA<Exception>()));

    // The stale copy is already gone even though the mirror row was never
    // committed — proving cleanup ran before the commit attempt, not after.
    expect(oldFile.existsSync(), isFalse);
    expect(File(p.join(tempDir.path, 'new-name.txt')).readAsBytesSync(), bytes);
  });

  test('a permanent filesystem failure is quarantined and does not block '
      'later events (F5)', () async {
    final now = DateTime.utc(2026, 1, 1);
    final goodBytes = Uint8List.fromList(utf8.encode('fine'));

    when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
    when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
          {'id': 1, 'fileId': 'bad-1', 'eventType': 'Create', 'metadata': null},
          {'id': 2, 'fileId': 'good-1', 'eventType': 'Create', 'metadata': null},
        ], 2));
    when(() => mockFileRepository.getFile('bad-1')).thenAnswer((_) async => FileItem(
          id: 'bad-1',
          // A perfectly legal name — this test is about an OS-level failure
          // unrelated to naming (a path past MAX_PATH, a disk hiccup). A
          // reserved device name like "aux" is now rejected before this
          // point instead (see the "rejects a reserved Win32 device name"
          // test below, B2), so re-using one here would never reach
          // downloadFile at all.
          name: 'stuck-file.bin',
          isFolder: false,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockMirror.getByServerId('bad-1')).thenAnswer((_) async => null);
    // Simulates a name-independent OS-level failure — a path past MAX_PATH,
    // a disk hiccup — not a network error.
    when(() => mockFileRepository.downloadFile('bad-1'))
        .thenThrow(const FileSystemException('The operation could not be completed', 'stuck-file.bin'));

    when(() => mockFileRepository.getFile('good-1')).thenAnswer((_) async => FileItem(
          id: 'good-1',
          name: 'good.txt',
          isFolder: false,
          sizeBytes: goodBytes.length,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockMirror.getByServerId('good-1')).thenAnswer((_) async => null);
    when(() => mockFileRepository.downloadFile('good-1')).thenAnswer((_) async => goodBytes);

    final applied = await service.pullOnce(tempDir.path);

    expect(applied, 2);
    verify(() => mockMirror.recordFailedEvent('bad-1', 1, any())).called(1);
    // The cursor advances past the quarantined event...
    verify(() => mockMirror.setCursor('dev-1', 1)).called(1);
    // ...and the next event still applies normally.
    expect(File(p.join(tempDir.path, 'good.txt')).readAsBytesSync(), goodBytes);
    verify(() => mockMirror.setCursor('dev-1', 2)).called(1);
  });

  test('a quarantined event recovers on a later poll once its cause clears, '
      'instead of staying stuck forever (R3)', () async {
    final now = DateTime.utc(2026, 1, 1);
    final bytes = Uint8List.fromList(utf8.encode('now available'));
    var downloadAttempts = 0;

    // A tiny stand-in for the failed_events table, wired to
    // recordFailedEvent/clearFailedEvent exactly like the real
    // sqflite-backed repository, so pullOnce's own retry loop has something
    // real to read back on the second call.
    final quarantine = <String, SyncFailedEvent>{};
    when(() => mockMirror.recordFailedEvent(any(), any(), any())).thenAnswer((invocation) async {
      final fileId = invocation.positionalArguments[0] as String;
      quarantine[fileId] = SyncFailedEvent(
        fileId: fileId,
        eventId: invocation.positionalArguments[1] as int,
        reason: invocation.positionalArguments[2] as String,
        failedAt: now,
      );
    });
    when(() => mockMirror.clearFailedEvent(any())).thenAnswer((invocation) async {
      quarantine.remove(invocation.positionalArguments[0] as String);
    });
    when(() => mockMirror.getFailedEvents()).thenAnswer((_) async => quarantine.values.toList());

    when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
    when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
          {'id': 1, 'fileId': 'locked-1', 'eventType': 'Create', 'metadata': null},
        ], 1));
    when(() => mockFileRepository.getFile('locked-1')).thenAnswer((_) async => FileItem(
          id: 'locked-1',
          name: 'busy.txt',
          isFolder: false,
          sizeBytes: bytes.length,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockMirror.getByServerId('locked-1')).thenAnswer((_) async => null);
    when(() => mockFileRepository.downloadFile('locked-1')).thenAnswer((_) async {
      downloadAttempts++;
      if (downloadAttempts == 1) {
        // Simulates the file being open elsewhere (e.g. in Word) on the
        // first attempt — a transient FileSystemException, not a permanent
        // one like F5's reserved name.
        throw const FileSystemException('sharing violation', 'busy.txt');
      }
      return bytes;
    });

    final firstApplied = await service.pullOnce(tempDir.path);
    expect(firstApplied, 1);
    expect(File(p.join(tempDir.path, 'busy.txt')).existsSync(), isFalse);
    expect(quarantine.containsKey('locked-1'), isTrue);

    // Second poll: nothing new on the wire, but the retry loop at the top
    // of pullOnce re-applies the quarantined entry by fileId — and this
    // time the write succeeds.
    when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([], 0));
    final secondApplied = await service.pullOnce(tempDir.path);

    // Not counted as an "applied event" — it never came from the event log,
    // it came from the retry loop.
    expect(secondApplied, 0);
    expect(File(p.join(tempDir.path, 'busy.txt')).readAsBytesSync(), bytes);
    expect(quarantine.containsKey('locked-1'), isFalse);
  });

  test('pullOnce is re-entrancy safe at the service level: a second '
      'concurrent call awaits the first instead of racing the cursor '
      '(F4/R6)', () async {
    final now = DateTime.utc(2026, 1, 1);
    final bytes = Uint8List.fromList(utf8.encode('content'));
    final gate = Completer<void>();

    when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
    when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async {
      // Held open until the test releases it, so both pullOnce calls are
      // guaranteed to overlap in time before either completes.
      await gate.future;
      return page([
        {'id': 1, 'fileId': 'file-1', 'eventType': 'Create', 'metadata': null},
      ], 1);
    });
    when(() => mockFileRepository.getFile('file-1')).thenAnswer((_) async => FileItem(
          id: 'file-1',
          name: 'doc.txt',
          isFolder: false,
          sizeBytes: bytes.length,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockMirror.getByServerId('file-1')).thenAnswer((_) async => null);
    when(() => mockFileRepository.downloadFile('file-1')).thenAnswer((_) async => bytes);

    final first = service.pullOnce(tempDir.path);
    final second = service.pullOnce(tempDir.path);

    gate.complete();
    final results = await Future.wait([first, second]);

    expect(results, [1, 1]);
    // If the second call had started its own pull cycle instead of awaiting
    // the first's in-flight future, the wire call below would have happened
    // twice against the same starting cursor.
    verify(() => mockSyncDataSource.pull('dev-1', 0)).called(1);
  });

  group('bootstrap', () {
    test('backfills the designated folder and the mirror from FileService '
        'on this device\'s first sync', () async {
      final now = DateTime.utc(2026, 1, 1);
      final bytes = Uint8List.fromList(utf8.encode('predates the event log'));

      when(() => mockMirror.isBootstrapped('dev-1')).thenAnswer((_) async => false);
      when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
      // Nothing in the event log — this file has never been touched since
      // before sync events existed, which is exactly the gap bootstrap
      // closes (see F8 in the PR #12 review).
      when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([], 0));
      when(() => mockFileRepository.listChildren(null, page: 1)).thenAnswer((_) async => PagedResult(
            items: [
              FileItem(
                id: 'legacy-1',
                name: 'legacy.txt',
                isFolder: false,
                sizeBytes: bytes.length,
                parentId: null,
                createdAt: now,
                updatedAt: now,
              ),
            ],
            totalCount: 1,
            page: 1,
            pageSize: 50,
          ));
      when(() => mockMirror.getByServerId('legacy-1')).thenAnswer((_) async => null);
      when(() => mockFileRepository.downloadFile('legacy-1')).thenAnswer((_) async => bytes);

      await service.pullOnce(tempDir.path);

      expect(File(p.join(tempDir.path, 'legacy.txt')).readAsBytesSync(), bytes);
      final upserted = verify(() => mockMirror.upsert(captureAny())).captured.single
          as SyncMirrorEntry;
      expect(upserted.serverId, 'legacy-1');
      verify(() => mockMirror.markBootstrapped('dev-1')).called(1);
    });

    test('does not run again once a device is marked bootstrapped', () async {
      when(() => mockMirror.isBootstrapped('dev-1')).thenAnswer((_) async => true);
      when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
      when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([], 0));

      await service.pullOnce(tempDir.path);

      verifyNever(() => mockFileRepository.listChildren(any(), page: any(named: 'page')));
      verifyNever(() => mockMirror.markBootstrapped(any()));
    });

    test('a file bootstrap cannot safely write (an untracked local file '
        'already there) is recorded as a failed event, not dropped '
        'silently (R2)', () async {
      final now = DateTime.utc(2026, 1, 1);
      final untrackedFile = File(p.join(tempDir.path, 'report.pdf'))
        ..writeAsStringSync('the user already had this');

      when(() => mockMirror.isBootstrapped('dev-1')).thenAnswer((_) async => false);
      when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
      when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([], 0));
      when(() => mockFileRepository.listChildren(null, page: 1)).thenAnswer((_) async => PagedResult(
            items: [
              FileItem(
                id: 'legacy-2',
                name: 'report.pdf',
                isFolder: false,
                parentId: null,
                createdAt: now,
                updatedAt: now,
              ),
            ],
            totalCount: 1,
            page: 1,
            pageSize: 50,
          ));
      when(() => mockMirror.getByServerId('legacy-2')).thenAnswer((_) async => null);

      final quarantine = <String, SyncFailedEvent>{};
      when(() => mockMirror.recordFailedEvent(any(), any(), any())).thenAnswer((invocation) async {
        final fileId = invocation.positionalArguments[0] as String;
        quarantine[fileId] = SyncFailedEvent(
          fileId: fileId,
          eventId: invocation.positionalArguments[1] as int,
          reason: invocation.positionalArguments[2] as String,
          failedAt: now,
        );
      });
      when(() => mockMirror.getFailedEvents()).thenAnswer((_) async => quarantine.values.toList());

      await service.pullOnce(tempDir.path);

      // The pre-existing file was left alone, not overwritten...
      expect(untrackedFile.readAsStringSync(), 'the user already had this');
      verifyNever(() => mockFileRepository.downloadFile('legacy-2'));
      // ...but unlike a plain silent skip, it is recorded and surfaced
      // through the same list the delta path (F1/F3/F5) uses — closing the
      // gap where the non-empty-folder dialog promised "listed as skipped
      // instead" but bootstrap skips never actually were (PR #12 review R2).
      verify(() => mockMirror.recordFailedEvent(
            'legacy-2',
            any(),
            any(that: contains('local conflict')),
          )).called(1);
      final surfaced = await service.getFailedEvents();
      expect(surfaced.map((f) => f.fileId), contains('legacy-2'));
      // The skip does not block bootstrap from completing and being marked
      // done — there is no per-item retry inside bootstrap itself; recovery
      // comes from the same R3 retry loop that picks up any quarantined
      // entry on a later poll.
      verify(() => mockMirror.markBootstrapped('dev-1')).called(1);
    });
  });

  group('Win32 name rules (B2)', () {
    // The Win32 gate is now an injected decision (see PullSyncService's
    // `isWindows` parameter), not a direct Platform.isWindows read — so
    // these tests pin it explicitly instead of inheriting whatever OS
    // happens to run them. Without this, the four tests below only passed
    // on a Windows dev machine and were silently skipped-by-passing-wrong on
    // Linux CI (they hit the unstubbed downloadFile mock instead of ever
    // exercising the name check).
    PullSyncService serviceWith({required bool isWindows}) => PullSyncService(
          mockSyncDataSource,
          mockDeviceRegistration,
          mockMirror,
          mockFileRepository,
          isWindows: isWindows,
        );

    test('violatesWin32NameRules flags a trailing dot or space, the alias '
        'that let a remote "foo." merge into an existing "foo"', () {
      expect(violatesWin32NameRules('foo.'), isTrue);
      expect(violatesWin32NameRules('foo '), isTrue);
      expect(violatesWin32NameRules('foo'), isFalse);
    });

    test('violatesWin32NameRules flags Win32-illegal characters', () {
      expect(violatesWin32NameRules('Why?.mp4'), isTrue);
      expect(violatesWin32NameRules('a<b>.txt'), isTrue);
      expect(violatesWin32NameRules('normal-name.txt'), isFalse);
    });

    test('violatesWin32NameRules flags reserved device stems regardless of '
        'case or extension, but not a name that merely starts the same way', () {
      expect(violatesWin32NameRules('nul'), isTrue);
      expect(violatesWin32NameRules('NUL'), isTrue);
      expect(violatesWin32NameRules('nul.txt'), isTrue);
      expect(violatesWin32NameRules('com1'), isTrue);
      expect(violatesWin32NameRules('lpt9'), isTrue);
      expect(violatesWin32NameRules('null.txt'), isFalse); // "null", not "nul"
      expect(violatesWin32NameRules('company.txt'), isFalse); // "company", not "com1".."com9"
    });

    test('rejects a Win32-illegal-character file name before ever '
        'downloading it — a download before this fix cost full file '
        'egress on every poll for a name Windows can never write (B2a)',
        () async {
      final now = DateTime.utc(2026, 1, 1);

      when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
      when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
            {'id': 1, 'fileId': 'bad-name-1', 'eventType': 'Create', 'metadata': null},
          ], 1));
      when(() => mockFileRepository.getFile('bad-name-1')).thenAnswer((_) async => FileItem(
            id: 'bad-name-1',
            name: 'Why?.mp4',
            isFolder: false,
            parentId: null,
            createdAt: now,
            updatedAt: now,
          ));
      when(() => mockMirror.getByServerId('bad-name-1')).thenAnswer((_) async => null);

      final applied = await serviceWith(isWindows: true).pullOnce(tempDir.path);

      expect(applied, 1);
      verifyNever(() => mockFileRepository.downloadFile(any()));
      verify(() => mockMirror.recordFailedEvent(
            'bad-name-1',
            1,
            any(that: contains('unsafe remote name')),
          )).called(1);
    });

    test('rejects a reserved Win32 device stem before ever downloading it '
        '(B2a)', () async {
      final now = DateTime.utc(2026, 1, 1);

      when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
      when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
            {'id': 1, 'fileId': 'bad-name-2', 'eventType': 'Create', 'metadata': null},
          ], 1));
      when(() => mockFileRepository.getFile('bad-name-2')).thenAnswer((_) async => FileItem(
            id: 'bad-name-2',
            name: 'nul',
            isFolder: false,
            parentId: null,
            createdAt: now,
            updatedAt: now,
          ));
      when(() => mockMirror.getByServerId('bad-name-2')).thenAnswer((_) async => null);

      await serviceWith(isWindows: true).pullOnce(tempDir.path);

      verifyNever(() => mockFileRepository.downloadFile(any()));
      verify(() => mockMirror.recordFailedEvent(
            'bad-name-2',
            1,
            any(that: contains('unsafe remote name')),
          )).called(1);
    });

    test('rejects a trailing-dot folder name before ever creating a '
        'directory for it, instead of merging into an existing "foo" '
        'sibling (B1/B2)', () async {
      final now = DateTime.utc(2026, 1, 1);
      final existingFoo = Directory(p.join(tempDir.path, 'foo'))..createSync();

      when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
      when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
            {'id': 1, 'fileId': 'folder-dot', 'eventType': 'Create', 'metadata': null},
          ], 1));
      when(() => mockFileRepository.getFile('folder-dot')).thenAnswer((_) async => FileItem(
            id: 'folder-dot',
            name: 'foo.',
            isFolder: true,
            parentId: null,
            createdAt: now,
            updatedAt: now,
          ));
      when(() => mockMirror.getByServerId('folder-dot')).thenAnswer((_) async => null);

      await serviceWith(isWindows: true).pullOnce(tempDir.path);

      verify(() => mockMirror.recordFailedEvent(
            'folder-dot',
            1,
            any(that: contains('unsafe remote name')),
          )).called(1);
      // Untouched — nothing was ever written under it, because "foo." was
      // rejected before any Directory call was made.
      expect(existingFoo.existsSync(), isTrue);
      expect(existingFoo.listSync(), isEmpty);
    });

    test('rejects a rename target Windows cannot write, leaving the old '
        'folder and its untracked content untouched (B1/B2)', () async {
      final now = DateTime.utc(2026, 1, 1);
      final oldDir = Directory(p.join(tempDir.path, 'oldName'))..createSync();
      final untracked = File(p.join(oldDir.path, 'untracked.txt'))
        ..writeAsStringSync('never sent to the server');

      when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
      when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
            {'id': 1, 'fileId': 'folder-1', 'eventType': 'Rename', 'metadata': null},
          ], 1));
      when(() => mockFileRepository.getFile('folder-1')).thenAnswer((_) async => FileItem(
            id: 'folder-1',
            name: 'renamed.', // trailing dot — Win32 cannot write this
            isFolder: true,
            parentId: null,
            createdAt: now,
            updatedAt: now,
          ));
      when(() => mockMirror.getByServerId('folder-1')).thenAnswer((_) async => SyncMirrorEntry(
            serverId: 'folder-1',
            localPath: oldDir.path,
            isFolder: true,
            updatedAt: now,
            syncedAt: now,
          ));

      await serviceWith(isWindows: true).pullOnce(tempDir.path);

      verify(() => mockMirror.recordFailedEvent(
            'folder-1',
            1,
            any(that: contains('unsafe remote name')),
          )).called(1);
      expect(oldDir.existsSync(), isTrue);
      expect(untracked.readAsStringSync(), 'never sent to the server');
      verifyNever(() => mockMirror.rePathChildren(any(), any()));
    });

    test('allows a name Win32 would reject through and writes it when the '
        'injected platform decision is not Windows — the input that '
        'distinguishes "Win32 rules on Windows only" from "Win32 rules '
        'everywhere": a regression enforcing them on macOS/Linux too would '
        'still pass every other test in this group. Uses a reserved device '
        'stem rather than an illegal character (e.g. "?") because the '
        'latter is rejected by the real Windows filesystem itself — even '
        'with isWindows: false — which would prove nothing about this '
        "app's own gate; a reserved stem is flagged by "
        '[violatesWin32NameRules] purely as a defensive check (see its doc '
        'comment) and genuinely writes fine on real Windows, so it isolates '
        'the gate itself from what the OS enforces regardless', () async {
      final now = DateTime.utc(2026, 1, 1);
      final bytes = Uint8List.fromList(utf8.encode('not a Win32 client'));

      when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
      when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
            {'id': 1, 'fileId': 'ok-on-non-windows', 'eventType': 'Create', 'metadata': null},
          ], 1));
      when(() => mockFileRepository.getFile('ok-on-non-windows')).thenAnswer((_) async => FileItem(
            id: 'ok-on-non-windows',
            name: 'com1.txt', // reserved Win32 device stem, rejected only when isWindows
            isFolder: false,
            sizeBytes: bytes.length,
            parentId: null,
            createdAt: now,
            updatedAt: now,
          ));
      when(() => mockMirror.getByServerId('ok-on-non-windows')).thenAnswer((_) async => null);
      when(() => mockFileRepository.downloadFile('ok-on-non-windows')).thenAnswer((_) async => bytes);

      final applied = await serviceWith(isWindows: false).pullOnce(tempDir.path);

      expect(applied, 1);
      final written = File(p.join(tempDir.path, 'com1.txt'));
      expect(written.existsSync(), isTrue);
      expect(written.readAsBytesSync(), bytes);
      verifyNever(() => mockMirror.recordFailedEvent(any(), any(), any()));
    });
  });

  group('quarantine retry backoff, budget and exception boundary (B2b/c)', () {
    test('does not retry a quarantined row inside the backoff window, but '
        'does retry one once it has elapsed', () async {
      final now = DateTime.utc(2026, 1, 1);
      final bytes = Uint8List.fromList(utf8.encode('now available'));

      final recent = SyncFailedEvent(
        fileId: 'recent-1',
        eventId: 1,
        reason: 'still unsafe',
        failedAt: DateTime.now(), // just failed — inside the backoff window
      );
      final stale = SyncFailedEvent(
        fileId: 'stale-1',
        eventId: 2,
        reason: 'was locked',
        failedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      );
      when(() => mockMirror.getFailedEvents()).thenAnswer((_) async => [recent, stale]);
      when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
      when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([], 0));
      when(() => mockFileRepository.getFile('stale-1')).thenAnswer((_) async => FileItem(
            id: 'stale-1',
            name: 'now-available.bin',
            isFolder: false,
            sizeBytes: bytes.length,
            parentId: null,
            createdAt: now,
            updatedAt: now,
          ));
      when(() => mockMirror.getByServerId('stale-1')).thenAnswer((_) async => null);
      when(() => mockFileRepository.downloadFile('stale-1')).thenAnswer((_) async => bytes);

      await service.pullOnce(tempDir.path);

      verifyNever(() => mockFileRepository.getFile('recent-1'));
      verify(() => mockFileRepository.getFile('stale-1')).called(1);
      verify(() => mockMirror.clearFailedEvent('stale-1')).called(1);
    });

    test('retries at most a bounded number of quarantined rows per poll, '
        'oldest-failed first', () async {
      const totalQuarantined = 25;
      const expectedRetriedThisPoll = 20; // must match PullSyncService._maxRetriesPerPoll

      final failedEvents = List.generate(
        totalQuarantined,
        (i) => SyncFailedEvent(
          fileId: 'q-$i',
          eventId: i,
          reason: 'still failing',
          // All comfortably past the backoff window, staggered so ordering
          // is unambiguous: q-0 failed longest ago, q-24 most recently.
          failedAt: DateTime.now().subtract(Duration(minutes: 10 + (totalQuarantined - i))),
        ),
      );

      when(() => mockMirror.getFailedEvents()).thenAnswer((_) async => failedEvents);
      when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
      when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([], 0));
      // Every quarantined row fails the same way again — what matters here
      // is how many getFile calls the retry loop issues, not the outcome.
      when(() => mockFileRepository.getFile(any())).thenThrow(Exception('still broken'));

      await service.pullOnce(tempDir.path);

      final retried = verify(() => mockFileRepository.getFile(captureAny())).captured;
      expect(retried, hasLength(expectedRetriedThisPoll));
      expect(retried, containsAll(List.generate(expectedRetriedThisPoll, (i) => 'q-$i')));
    });

    test('a non-404 exception during a quarantine retry does not abort the '
        'drain — a fresh event in the same poll still applies', () async {
      final now = DateTime.utc(2026, 1, 1);
      final bytes = Uint8List.fromList(utf8.encode('fresh'));

      final stuck = SyncFailedEvent(
        fileId: 'stuck-1',
        eventId: 1,
        reason: 'was a local conflict',
        failedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      );
      when(() => mockMirror.getFailedEvents()).thenAnswer((_) async => [stuck]);
      // Something this loop was never taught to expect — a non-404
      // DioException from a flaky connection, say.
      when(() => mockFileRepository.getFile('stuck-1')).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/files/stuck-1'),
          response: Response(
            requestOptions: RequestOptions(path: '/files/stuck-1'),
            statusCode: 500,
          ),
        ),
      );

      when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
      when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
            {'id': 5, 'fileId': 'fresh-1', 'eventType': 'Create', 'metadata': null},
          ], 5));
      when(() => mockFileRepository.getFile('fresh-1')).thenAnswer((_) async => FileItem(
            id: 'fresh-1',
            name: 'fresh.txt',
            isFolder: false,
            sizeBytes: bytes.length,
            parentId: null,
            createdAt: now,
            updatedAt: now,
          ));
      when(() => mockMirror.getByServerId('fresh-1')).thenAnswer((_) async => null);
      when(() => mockFileRepository.downloadFile('fresh-1')).thenAnswer((_) async => bytes);

      final applied = await service.pullOnce(tempDir.path);

      expect(applied, 1);
      expect(File(p.join(tempDir.path, 'fresh.txt')).readAsBytesSync(), bytes);
      // The quarantined row is still quarantined — re-stamped, not resolved
      // and not left to abort the poll. The reason now reflects this
      // retry's own exception (the DioException from getFile), not the
      // stale first-attempt reason ('was a local conflict') — a later
      // different failure must be visible, not hidden behind whatever
      // tripped first (PR #12 review round 4, N2).
      verify(() => mockMirror.recordFailedEvent(
            'stuck-1',
            1,
            any(that: contains('DioException')),
          )).called(1);
    });
  });

  group('folder delete removes only what pull owns, non-recursively (B1)', () {
    test('leaves an untracked file inside a deleted folder alone, and '
        'quarantines the event instead of destroying the folder', () async {
      final now = DateTime.utc(2026, 1, 1);
      final folderDir = Directory(p.join(tempDir.path, 'Photos'))..createSync();
      final trackedBytes = Uint8List.fromList(utf8.encode('server content'));
      final trackedFile = File(p.join(folderDir.path, 'tracked.jpg'))
        ..writeAsBytesSync(trackedBytes);
      final untrackedFile = File(p.join(folderDir.path, 'my-notes.txt'))
        ..writeAsStringSync('only ever existed on this machine');

      when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
      when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
            {'id': 1, 'fileId': 'folder-del-1', 'eventType': 'Delete', 'metadata': null},
          ], 1));
      when(() => mockMirror.getByServerId('folder-del-1')).thenAnswer((_) async => SyncMirrorEntry(
            serverId: 'folder-del-1',
            localPath: folderDir.path,
            isFolder: true,
            updatedAt: now,
            syncedAt: now,
          ));
      when(() => mockMirror.getChildrenUnder(folderDir.path)).thenAnswer((_) async => [
            SyncMirrorEntry(
              serverId: 'tracked-file-1',
              localPath: trackedFile.path,
              isFolder: false,
              contentHash: sha256.convert(trackedBytes).toString(),
              updatedAt: now,
              syncedAt: now,
            ),
          ]);
      when(() => mockMirror.deleteByServerId('tracked-file-1')).thenAnswer((_) async {});

      final applied = await service.pullOnce(tempDir.path);

      expect(applied, 1);
      // The tracked, unmodified file is gone...
      expect(trackedFile.existsSync(), isFalse);
      verify(() => mockMirror.deleteByServerId('tracked-file-1')).called(1);
      // ...but the untracked one, and the folder holding it, are not.
      expect(untrackedFile.existsSync(), isTrue);
      expect(untrackedFile.readAsStringSync(), 'only ever existed on this machine');
      expect(folderDir.existsSync(), isTrue);
      // The folder's own row is not dropped — it still holds content pull
      // did not clear, so a later retry can finish the job once that
      // resolves on its own.
      verifyNever(() => mockMirror.deleteByServerId('folder-del-1'));
      verify(() => mockMirror.recordFailedEvent(
            'folder-del-1',
            1,
            any(that: contains('untracked or locally modified content')),
          )).called(1);
    });

    test('removes the whole folder once every tracked file inside matches '
        'what was last synced', () async {
      final now = DateTime.utc(2026, 1, 1);
      final folderDir = Directory(p.join(tempDir.path, 'Empty-once-synced'))..createSync();
      final trackedBytes = Uint8List.fromList(utf8.encode('server content'));
      final trackedFile = File(p.join(folderDir.path, 'tracked.jpg'))
        ..writeAsBytesSync(trackedBytes);

      when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
      when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
            {'id': 1, 'fileId': 'folder-del-2', 'eventType': 'Delete', 'metadata': null},
          ], 1));
      when(() => mockMirror.getByServerId('folder-del-2')).thenAnswer((_) async => SyncMirrorEntry(
            serverId: 'folder-del-2',
            localPath: folderDir.path,
            isFolder: true,
            updatedAt: now,
            syncedAt: now,
          ));
      when(() => mockMirror.getChildrenUnder(folderDir.path)).thenAnswer((_) async => [
            SyncMirrorEntry(
              serverId: 'tracked-file-2',
              localPath: trackedFile.path,
              isFolder: false,
              contentHash: sha256.convert(trackedBytes).toString(),
              updatedAt: now,
              syncedAt: now,
            ),
          ]);
      when(() => mockMirror.deleteByServerId('tracked-file-2')).thenAnswer((_) async {});
      when(() => mockMirror.deleteByServerId('folder-del-2')).thenAnswer((_) async {});

      await service.pullOnce(tempDir.path);

      expect(folderDir.existsSync(), isFalse);
      verify(() => mockMirror.deleteByServerId('tracked-file-2')).called(1);
      verify(() => mockMirror.deleteByServerId('folder-del-2')).called(1);
      verifyNever(() => mockMirror.recordFailedEvent(any(), any(), any()));
    });

    test('removes the folder even when only OS metadata files (.DS_Store, '
        'Thumbs.db, desktop.ini) are left behind alongside a matching '
        'tracked file', () async {
      final now = DateTime.utc(2026, 1, 1);
      final folderDir = Directory(p.join(tempDir.path, 'Opened-in-finder'))..createSync();
      final trackedBytes = Uint8List.fromList(utf8.encode('server content'));
      final trackedFile = File(p.join(folderDir.path, 'tracked.jpg'))
        ..writeAsBytesSync(trackedBytes);
      // Regenerable OS metadata, not user data — none of these are tracked
      // by the mirror.
      File(p.join(folderDir.path, '.DS_Store')).writeAsStringSync('finder metadata');
      File(p.join(folderDir.path, 'Thumbs.db')).writeAsStringSync('thumbnail cache');
      File(p.join(folderDir.path, 'desktop.ini')).writeAsStringSync('[.ShellClassInfo]');

      when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
      when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
            {'id': 1, 'fileId': 'folder-del-3', 'eventType': 'Delete', 'metadata': null},
          ], 1));
      when(() => mockMirror.getByServerId('folder-del-3')).thenAnswer((_) async => SyncMirrorEntry(
            serverId: 'folder-del-3',
            localPath: folderDir.path,
            isFolder: true,
            updatedAt: now,
            syncedAt: now,
          ));
      when(() => mockMirror.getChildrenUnder(folderDir.path)).thenAnswer((_) async => [
            SyncMirrorEntry(
              serverId: 'tracked-file-3',
              localPath: trackedFile.path,
              isFolder: false,
              contentHash: sha256.convert(trackedBytes).toString(),
              updatedAt: now,
              syncedAt: now,
            ),
          ]);
      when(() => mockMirror.deleteByServerId('tracked-file-3')).thenAnswer((_) async {});
      when(() => mockMirror.deleteByServerId('folder-del-3')).thenAnswer((_) async {});

      await service.pullOnce(tempDir.path);

      expect(folderDir.existsSync(), isFalse);
      verify(() => mockMirror.deleteByServerId('tracked-file-3')).called(1);
      verify(() => mockMirror.deleteByServerId('folder-del-3')).called(1);
      verifyNever(() => mockMirror.recordFailedEvent(any(), any(), any()));
    });
  });

  group('bootstrap folder create failure does not wedge forever (B3)', () {
    test('a folder the OS refuses to create is recorded as a failed event, '
        'markBootstrapped still runs, and a later sibling is still walked',
        () async {
      final now = DateTime.utc(2026, 1, 1);
      // A real file already occupies the path bootstrap will try to make a
      // directory at — Directory.create(recursive: true) genuinely throws
      // for this, no mocking of dart:io needed.
      File(p.join(tempDir.path, 'blocked')).writeAsStringSync('irrelevant');

      when(() => mockMirror.isBootstrapped('dev-1')).thenAnswer((_) async => false);
      when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
      when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([], 0));
      when(() => mockFileRepository.listChildren(null, page: 1)).thenAnswer((_) async => PagedResult(
            items: [
              FileItem(
                id: 'blocked-folder',
                name: 'blocked',
                isFolder: true,
                parentId: null,
                createdAt: now,
                updatedAt: now,
              ),
              FileItem(
                id: 'ok-folder',
                name: 'ok',
                isFolder: true,
                parentId: null,
                createdAt: now,
                updatedAt: now,
              ),
            ],
            totalCount: 2,
            page: 1,
            pageSize: 50,
          ));
      when(() => mockMirror.getByServerId('blocked-folder')).thenAnswer((_) async => null);
      when(() => mockMirror.getByServerId('ok-folder')).thenAnswer((_) async => null);
      // "ok" has no children of its own — the walk into it just finds an
      // empty page.
      when(() => mockFileRepository.listChildren('ok-folder', page: 1)).thenAnswer((_) async => PagedResult(
            items: [],
            totalCount: 0,
            page: 1,
            pageSize: 50,
          ));

      await service.pullOnce(tempDir.path);

      // "blocked" failed and is recorded, not silently dropped...
      verify(() => mockMirror.recordFailedEvent('blocked-folder', any(), any())).called(1);
      // ...but the walk did not stop there: "ok", listed right after it,
      // still got created — proving the failure did not escape
      // _bootstrapFolder's loop.
      expect(Directory(p.join(tempDir.path, 'ok')).existsSync(), isTrue);
      // And bootstrap is marked complete. Before this fix, the escaped
      // exception meant this line never ran, and every later poll
      // re-walked the whole tree only to fail at "blocked" again, forever.
      verify(() => mockMirror.markBootstrapped('dev-1')).called(1);
    });
  });
}

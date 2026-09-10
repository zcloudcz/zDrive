import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

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
          name: 'aux',
          isFolder: false,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockMirror.getByServerId('bad-1')).thenAnswer((_) async => null);
    // Simulates a name the OS refuses outright (e.g. a reserved device name
    // on Windows, or a path past MAX_PATH) — not a network error.
    when(() => mockFileRepository.downloadFile('bad-1'))
        .thenThrow(const FileSystemException('The filename is invalid', 'aux'));

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
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:zdrive_app/features/files/domain/file_item.dart';
import 'package:zdrive_app/features/files/domain/file_repository.dart';
import 'package:zdrive_app/features/sync/data/local_change_scanner.dart';
import 'package:zdrive_app/features/sync/data/push_sync_service.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_entry.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_repository.dart';

class MockSyncMirrorRepository extends Mock implements SyncMirrorRepository {}

class MockFileRepository extends Mock implements FileRepository {}

class MockPushSyncService extends Mock implements PushSyncService {}

class FakeSyncMirrorEntry extends Fake implements SyncMirrorEntry {}

void main() {
  late MockSyncMirrorRepository mockMirror;
  late MockFileRepository mockFileRepository;
  late MockPushSyncService mockPush;
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

  LocalChangeScanner scannerWith({required bool isWindows, bool isCaseInsensitive = false}) =>
      LocalChangeScanner(
        mockMirror,
        mockFileRepository,
        mockPush,
        isWindows: isWindows,
        isCaseInsensitive: isCaseInsensitive,
      );

  setUpAll(() {
    registerFallbackValue(FakeSyncMirrorEntry());
    registerFallbackValue(const Stream<List<int>>.empty());
    registerFallbackValue(SyncChangeType.create);
  });

  setUp(() {
    mockMirror = MockSyncMirrorRepository();
    mockFileRepository = MockFileRepository();
    mockPush = MockPushSyncService();
    scanner = scannerWith(isWindows: false);
    tempDir = Directory.systemTemp.createTempSync('local_change_scanner_test_');

    when(() => mockMirror.upsert(any())).thenAnswer((_) async {});
    when(() => mockMirror.deleteByServerId(any())).thenAnswer((_) async {});
    when(() => mockPush.reportChange(any(), any())).thenAnswer((_) async {});
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('new file at root: uploads, upserts the mirror, reports a create',
      () async {
    final file = File(p.join(tempDir.path, 'new.txt'))..writeAsStringSync('hello');

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => []);
    when(() => mockFileRepository.uploadFile(any(that: isNull), 'new.txt', any(), 5, any()))
        .thenAnswer((_) async => 'file-1');

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    final upserted =
        verify(() => mockMirror.upsert(captureAny())).captured.single as SyncMirrorEntry;
    expect(upserted.serverId, 'file-1');
    expect(upserted.localPath, file.path);
    expect(upserted.isFolder, isFalse);
    expect(upserted.sizeBytes, 5);
    expect(upserted.contentHash, hashOf('hello'));
    verify(() => mockPush.reportChange('file-1', SyncChangeType.create)).called(1);
  });

  test('new file inside a new subfolder: creates the folder first, then '
      'uploads into it', () async {
    final subDir = Directory(p.join(tempDir.path, 'sub'))..createSync();
    File(p.join(subDir.path, 'new.txt')).writeAsStringSync('x');

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => []);
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
    verify(() => mockPush.reportChange('file-2', SyncChangeType.create)).called(1);
  });

  test('tracked file edited (different bytes): uploads a new version, '
      'reports an update; no create, no delete', () async {
    final file = File(p.join(tempDir.path, 'tracked.txt'))
      ..writeAsStringSync('a longer new body');

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
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
    verify(() => mockPush.reportChange('file-3', SyncChangeType.update)).called(1);
    verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any()));
    verifyNever(() => mockFileRepository.deleteFile(any()));
  });

  test('tracked file unchanged (same size, not modified since it was last '
      'synced): no server calls at all', () async {
    final file = File(p.join(tempDir.path, 'same.txt'))..writeAsStringSync('same');

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
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
    verifyNever(() => mockMirror.upsert(any()));
    verifyNever(() => mockPush.reportChange(any(), any()));
  });

  test('tracked file deleted: deletes server-side, removes the mirror row, '
      'reports a delete', () async {
    final goneePath = p.join(tempDir.path, 'gone.txt'); // never created on disk

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
          SyncMirrorEntry(
            serverId: 'file-5',
            localPath: goneePath,
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
    verify(() => mockMirror.deleteByServerId('file-5')).called(1);
    verify(() => mockPush.reportChange('file-5', SyncChangeType.delete)).called(1);
  });

  test('tracked file renamed in place (same bytes): renames only — no '
      'upload, no delete; mirror path updated; reports a rename', () async {
    final oldPath = p.join(tempDir.path, 'old.txt'); // no longer on disk
    final newFile = File(p.join(tempDir.path, 'new.txt'))
      ..writeAsStringSync('same bytes');

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
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
    final upserted =
        verify(() => mockMirror.upsert(captureAny())).captured.single as SyncMirrorEntry;
    expect(upserted.localPath, newFile.path);
    expect(upserted.serverId, 'file-6');
    verify(() => mockPush.reportChange('file-6', SyncChangeType.rename)).called(1);
  });

  test('tracked file moved into another tracked folder: moves only, '
      'reports a move', () async {
    final subDir = Directory(p.join(tempDir.path, 'sub'))..createSync();
    final oldPath = p.join(tempDir.path, 'file.txt'); // no longer on disk
    final movedFile = File(p.join(subDir.path, 'file.txt'))
      ..writeAsStringSync('payload');

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
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
    final upserted =
        verify(() => mockMirror.upsert(captureAny())).captured.single as SyncMirrorEntry;
    expect(upserted.localPath, movedFile.path);
    verify(() => mockPush.reportChange('file-7', SyncChangeType.move)).called(1);
  });

  test('moved and renamed: moves first, then renames', () async {
    final subDir = Directory(p.join(tempDir.path, 'sub'))..createSync();
    final oldPath = p.join(tempDir.path, 'old.txt'); // no longer on disk
    File(p.join(subDir.path, 'new.txt')).writeAsStringSync('payload');

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
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
    verify(() => mockPush.reportChange('file-8', SyncChangeType.move)).called(1);
    verify(() => mockPush.reportChange('file-8', SyncChangeType.rename)).called(1);
  });

  test('ambiguous hash match (two missing tracked files share content with '
      'one new file): no move — the new file is uploaded and both missing '
      'files are deleted', () async {
    final dupeAPath = p.join(tempDir.path, 'dupeA.txt'); // no longer on disk
    final dupeBPath = p.join(tempDir.path, 'dupeB.txt'); // no longer on disk
    File(p.join(tempDir.path, 'newdupe.txt')).writeAsStringSync('shared content');

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
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

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
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
      'it — folder and children — is removed', () async {
    final projPath = p.join(tempDir.path, 'proj'); // whole tree gone from disk
    final aPath = p.join(projPath, 'a.txt');
    final subPath = p.join(projPath, 'sub');
    final bPath = p.join(subPath, 'b.txt');

    final projEntry = SyncMirrorEntry(
      serverId: 'proj-id',
      localPath: projPath,
      isFolder: true,
      updatedAt: past,
      syncedAt: past,
    );
    final aEntry = SyncMirrorEntry(
      serverId: 'a-id',
      localPath: aPath,
      isFolder: false,
      sizeBytes: 1,
      contentHash: hashOf('a'),
      updatedAt: past,
      syncedAt: past,
    );
    final subEntry = SyncMirrorEntry(
      serverId: 'sub-id',
      localPath: subPath,
      isFolder: true,
      updatedAt: past,
      syncedAt: past,
    );
    final bEntry = SyncMirrorEntry(
      serverId: 'b-id',
      localPath: bPath,
      isFolder: false,
      sizeBytes: 1,
      contentHash: hashOf('b'),
      updatedAt: past,
      syncedAt: past,
    );

    when(() => mockMirror.getChildrenUnder(tempDir.path))
        .thenAnswer((_) async => [projEntry, aEntry, subEntry, bEntry]);
    when(() => mockMirror.getChildrenUnder(projPath))
        .thenAnswer((_) async => [aEntry, subEntry, bEntry]);
    when(() => mockFileRepository.deleteFile('proj-id')).thenAnswer((_) async {});

    final pushed = await scanner.scanOnce(tempDir.path);

    expect(pushed, 1);
    verify(() => mockFileRepository.deleteFile('proj-id')).called(1);
    verifyNever(() => mockFileRepository.deleteFile('a-id'));
    verifyNever(() => mockFileRepository.deleteFile('b-id'));
    verifyNever(() => mockFileRepository.deleteFile('sub-id'));
    verify(() => mockMirror.deleteByServerId('proj-id')).called(1);
    verify(() => mockMirror.deleteByServerId('a-id')).called(1);
    verify(() => mockMirror.deleteByServerId('sub-id')).called(1);
    verify(() => mockMirror.deleteByServerId('b-id')).called(1);
    verify(() => mockPush.reportChange('proj-id', SyncChangeType.delete)).called(1);
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

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => []);

    final pushed = await scannerWith(isWindows: true).scanOnce(tempDir.path);

    expect(pushed, 0);
    verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any()));
    verifyNever(() => mockFileRepository.createFolder(any(), any()));
    verifyNever(() => mockPush.reportChange(any(), any()));
  });

  test('new file 409 (name already exists server-side): uploads a new '
      'version into the existing file, reports an update', () async {
    File(p.join(tempDir.path, 'shared.txt')).writeAsStringSync('local content');

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => []);
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
    verify(() => mockPush.reportChange('existing-id', SyncChangeType.update)).called(1);
  });

  test('changed file whose uploadNewVersion 404s (deleted server-side '
      'meanwhile): re-created via uploadFile, old mirror row removed',
      () async {
    final file = File(p.join(tempDir.path, 'edited.txt'))
      ..writeAsStringSync('new local content');

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
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
    verify(() => mockMirror.deleteByServerId('stale-id')).called(1);
    verify(() => mockPush.reportChange('fresh-id', SyncChangeType.create)).called(1);
  });

  test('one failing upload does not stop the next file; the failed path is '
      'skipped on an immediate second scan (backoff)', () async {
    File(p.join(tempDir.path, 'bad.txt')).writeAsStringSync('will fail');
    File(p.join(tempDir.path, 'good.txt')).writeAsStringSync('will succeed');

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => []);
    when(() => mockFileRepository.uploadFile(any(that: isNull), 'bad.txt', any(), 9, any()))
        .thenThrow(Exception('network dropped'));
    when(() => mockFileRepository.uploadFile(any(that: isNull), 'good.txt', any(), 12, any()))
        .thenAnswer((_) async => 'good-id');

    final firstPushed = await scanner.scanOnce(tempDir.path);
    expect(firstPushed, 1); // only good.txt landed
    verify(() => mockPush.reportChange('good-id', SyncChangeType.create)).called(1);

    // Second, immediate scan: bad.txt is still a "new file" from the
    // mirror's point of view (it was never upserted), but backoff must
    // skip it rather than retrying the same failure straight away.
    clearInteractions(mockFileRepository);
    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
          SyncMirrorEntry(
            serverId: 'good-id',
            localPath: p.join(tempDir.path, 'good.txt'),
            isFolder: false,
            sizeBytes: 12,
            contentHash: hashOf('will succeed'),
            updatedAt: now,
            syncedAt: future,
          ),
        ]);

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

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
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

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
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

  test('case-only folder rename on a case-insensitive platform (F4): '
      'renames instead of create-then-delete, re-paths children, and ends '
      'the scan', () async {
    // Real disk either way — on Linux CI (case-sensitive) this only tests
    // anything because the seam below forces case-insensitive handling on;
    // the rename itself is genuinely applied to the filesystem, matching
    // what a user would see on Windows/macOS.
    final docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync();
    File(p.join(docsDir.path, 'child.txt')).writeAsStringSync('x');
    final oldDocsPath = p.join(tempDir.path, 'Docs'); // tracked path, no longer on disk
    final oldChildPath = p.join(oldDocsPath, 'child.txt');

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
          SyncMirrorEntry(
            serverId: 'docs-id',
            localPath: oldDocsPath,
            isFolder: true,
            updatedAt: past,
            syncedAt: past,
          ),
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
    when(() => mockMirror.rePathChildren(oldDocsPath, docsDir.path)).thenAnswer((_) async {});

    await scannerWith(isWindows: false, isCaseInsensitive: true).scanOnce(tempDir.path);

    verify(() => mockFileRepository.renameFile('docs-id', 'docs')).called(1);
    verify(() => mockPush.reportChange('docs-id', SyncChangeType.rename)).called(1);
    verify(() => mockMirror.rePathChildren(oldDocsPath, docsDir.path)).called(1);
    verifyNever(() => mockFileRepository.createFolder(any(), any()));
    verifyNever(() => mockFileRepository.deleteFile(any()));
    final upserted =
        verify(() => mockMirror.upsert(captureAny())).captured.single as SyncMirrorEntry;
    expect(upserted.serverId, 'docs-id');
    expect(upserted.localPath, docsDir.path);
  });

  group('F2: a failed move does not delete the source, and a partial move '
      'is idempotent on retry', () {
    test('moveFile throws: no deleteFile for the source, no upload of the '
        'new file, mirror row unchanged', () async {
      final subDir = Directory(p.join(tempDir.path, 'sub'))..createSync();
      final oldPath = p.join(tempDir.path, 'file.txt'); // no longer on disk
      File(p.join(subDir.path, 'file.txt')).writeAsStringSync('payload');

      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
            SyncMirrorEntry(
              serverId: 'sub-id',
              localPath: subDir.path,
              isFolder: true,
              updatedAt: past,
              syncedAt: past,
            ),
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
      verifyNever(() => mockMirror.upsert(any()));
    });

    test('move succeeds but rename throws: no deleteFile; a retried scan '
        'with getFile now returning the already-moved parent calls only '
        'renameFile', () async {
      final subDir = Directory(p.join(tempDir.path, 'sub'))..createSync();
      final oldPath = p.join(tempDir.path, 'old.txt'); // no longer on disk
      File(p.join(subDir.path, 'new.txt')).writeAsStringSync('payload');

      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
            SyncMirrorEntry(
              serverId: 'sub-id',
              localPath: subDir.path,
              isFolder: true,
              updatedAt: past,
              syncedAt: past,
            ),
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
      verify(() => mockPush.reportChange('file-b', SyncChangeType.move)).called(1);
      verifyNever(() => mockFileRepository.deleteFile(any()));

      // Retry: backoff cleared, and getFile now reflects the half that
      // already landed (parentId is 'sub-id'; the rename never made it).
      scanner.debugClearBackoff();
      clearInteractions(mockFileRepository);
      clearInteractions(mockPush);
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
    });

    test('an unreadable/backed-off new file with the same size as a missing '
        'file: no deleteFile for that missing file', () async {
      final oldPath = p.join(tempDir.path, 'gone.bin'); // no longer on disk
      final newFile = File(p.join(tempDir.path, 'unreadable.bin'))
        ..writeAsBytesSync(List.filled(9, 1));

      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
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

  group('F6: report before mirror commit', () {
    test('reportChange throws after a new-file upload: mirror not '
        'upserted, so the next scan retries the whole upload', () async {
      File(p.join(tempDir.path, 'flaky.txt')).writeAsStringSync('x');

      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => []);
      when(() => mockFileRepository.uploadFile(any(that: isNull), 'flaky.txt', any(), 1, any()))
          .thenAnswer((_) async => 'flaky-id');
      when(() => mockPush.reportChange('flaky-id', SyncChangeType.create))
          .thenThrow(Exception('server unreachable'));

      final pushed = await scanner.scanOnce(tempDir.path);

      expect(pushed, 0);
      verifyNever(() => mockMirror.upsert(any()));
    });

    test('delete whose deleteFile 404s still reports the delete before '
        'clearing the mirror row', () async {
      final gonePath = p.join(tempDir.path, 'gone404.txt'); // never created on disk

      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
            SyncMirrorEntry(
              serverId: 'file-404',
              localPath: gonePath,
              isFolder: false,
              sizeBytes: 3,
              contentHash: hashOf('bye'),
              updatedAt: past,
              syncedAt: past,
            ),
          ]);
      when(() => mockFileRepository.deleteFile('file-404')).thenThrow(dioError(404));

      final pushed = await scanner.scanOnce(tempDir.path);

      expect(pushed, 0); // already gone server-side too; not a new push
      verifyInOrder([
        () => mockPush.reportChange('file-404', SyncChangeType.delete),
        () => mockMirror.deleteByServerId('file-404'),
      ]);
    });
  });

  group('PR #14 review round 2: a report that fails after its server write '
      'succeeded is retried on the next scan, not the write (findings 1-3)', () {
    test('upload new version: scan 2 sends exactly one reportChange(update) '
        'and makes no second uploadNewVersion; the mirror row is written '
        'only after the report', () async {
      final file = File(p.join(tempDir.path, 'tracked1.txt'))
        ..writeAsStringSync('a longer new body');

      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
            SyncMirrorEntry(
              serverId: 'file-v1',
              localPath: file.path,
              isFolder: false,
              sizeBytes: 3, // old content's length
              contentHash: hashOf('old'),
              updatedAt: past,
              syncedAt: past,
            ),
          ]);
      when(() => mockFileRepository.uploadNewVersion('file-v1', 'tracked1.txt', any(), 17))
          .thenAnswer((_) async {});
      when(() => mockPush.reportChange('file-v1', SyncChangeType.update))
          .thenThrow(Exception('server unreachable'));

      final firstPushed = await scanner.scanOnce(tempDir.path);

      expect(firstPushed, 0);
      verify(() => mockFileRepository.uploadNewVersion('file-v1', 'tracked1.txt', any(), 17)).called(1);
      verifyNever(() => mockMirror.upsert(any()));

      // Scan 2: reportChange now succeeds. From the mirror's point of view
      // this scan starts with the row the flush is about to overwrite — a
      // real SQLite upsert would already show the new size/hash by the
      // time classify reads it, so the stub mirrors that end state.
      clearInteractions(mockFileRepository);
      clearInteractions(mockPush);
      when(() => mockPush.reportChange('file-v1', SyncChangeType.update)).thenAnswer((_) async {});
      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
            SyncMirrorEntry(
              serverId: 'file-v1',
              localPath: file.path,
              isFolder: false,
              sizeBytes: 17,
              contentHash: hashOf('a longer new body'),
              updatedAt: past,
              syncedAt: future,
            ),
          ]);

      final secondPushed = await scanner.scanOnce(tempDir.path);

      expect(secondPushed, 1);
      verify(() => mockPush.reportChange('file-v1', SyncChangeType.update)).called(1);
      verify(() => mockMirror.upsert(any())).called(1);
      verifyNever(() => mockFileRepository.uploadNewVersion(any(), any(), any(), any()));
    });

    test('new file upload: scan 2 -> exactly one reportChange(create), no '
        'second uploadFile', () async {
      final file = File(p.join(tempDir.path, 'brandnew2.txt'))..writeAsStringSync('hello');

      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => []);
      when(() => mockFileRepository.uploadFile(any(that: isNull), 'brandnew2.txt', any(), 5, any()))
          .thenAnswer((_) async => 'new2-id');
      when(() => mockPush.reportChange('new2-id', SyncChangeType.create))
          .thenThrow(Exception('server unreachable'));

      final firstPushed = await scanner.scanOnce(tempDir.path);

      expect(firstPushed, 0);
      verify(() => mockFileRepository.uploadFile(any(that: isNull), 'brandnew2.txt', any(), 5, any()))
          .called(1);
      verifyNever(() => mockMirror.upsert(any()));

      clearInteractions(mockFileRepository);
      clearInteractions(mockPush);
      when(() => mockPush.reportChange('new2-id', SyncChangeType.create)).thenAnswer((_) async {});
      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
            SyncMirrorEntry(
              serverId: 'new2-id',
              localPath: file.path,
              isFolder: false,
              sizeBytes: 5,
              contentHash: hashOf('hello'),
              updatedAt: past,
              syncedAt: future,
            ),
          ]);

      final secondPushed = await scanner.scanOnce(tempDir.path);

      expect(secondPushed, 1);
      verify(() => mockPush.reportChange('new2-id', SyncChangeType.create)).called(1);
      verify(() => mockMirror.upsert(any())).called(1);
      verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any()));
    });

    test('rename: scan 2 -> exactly one reportChange(rename), no second '
        'renameFile; mirror path updated after it', () async {
      final oldPath = p.join(tempDir.path, 'old3.txt');
      final newFile = File(p.join(tempDir.path, 'new3.txt'))..writeAsStringSync('same bytes 3');

      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
            SyncMirrorEntry(
              serverId: 'file-r3',
              localPath: oldPath,
              isFolder: false,
              sizeBytes: 12,
              contentHash: hashOf('same bytes 3'),
              updatedAt: past,
              syncedAt: past,
            ),
          ]);
      when(() => mockFileRepository.getFile('file-r3')).thenAnswer((_) async => FileItem(
            id: 'file-r3',
            name: 'old3.txt',
            isFolder: false,
            parentId: null,
            createdAt: now,
            updatedAt: now,
          ));
      when(() => mockFileRepository.renameFile('file-r3', 'new3.txt')).thenAnswer((_) async => FileItem(
            id: 'file-r3',
            name: 'new3.txt',
            isFolder: false,
            parentId: null,
            createdAt: now,
            updatedAt: now,
          ));
      when(() => mockPush.reportChange('file-r3', SyncChangeType.rename))
          .thenThrow(Exception('server unreachable'));

      final firstPushed = await scanner.scanOnce(tempDir.path);

      expect(firstPushed, 0);
      verify(() => mockFileRepository.renameFile('file-r3', 'new3.txt')).called(1);
      verifyNever(() => mockMirror.upsert(any()));

      clearInteractions(mockFileRepository);
      clearInteractions(mockPush);
      when(() => mockPush.reportChange('file-r3', SyncChangeType.rename)).thenAnswer((_) async {});
      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
            SyncMirrorEntry(
              serverId: 'file-r3',
              localPath: newFile.path,
              isFolder: false,
              sizeBytes: 12,
              contentHash: hashOf('same bytes 3'),
              updatedAt: past,
              syncedAt: future,
            ),
          ]);

      final secondPushed = await scanner.scanOnce(tempDir.path);

      expect(secondPushed, 1);
      verify(() => mockPush.reportChange('file-r3', SyncChangeType.rename)).called(1);
      final upserted = verify(() => mockMirror.upsert(captureAny())).captured.single as SyncMirrorEntry;
      expect(upserted.localPath, newFile.path);
      verifyNever(() => mockFileRepository.renameFile(any(), any()));
    });

    test('move: scan 2 -> exactly one reportChange(move), no second '
        'moveFile', () async {
      final subDir = Directory(p.join(tempDir.path, 'sub4'))..createSync();
      final oldPath = p.join(tempDir.path, 'file4.txt');
      final movedFile = File(p.join(subDir.path, 'file4.txt'))..writeAsStringSync('move payload');
      final subEntry = SyncMirrorEntry(
        serverId: 'sub4-id',
        localPath: subDir.path,
        isFolder: true,
        updatedAt: past,
        syncedAt: past,
      );

      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
            subEntry,
            SyncMirrorEntry(
              serverId: 'file-m4',
              localPath: oldPath,
              isFolder: false,
              sizeBytes: 12,
              contentHash: hashOf('move payload'),
              updatedAt: past,
              syncedAt: past,
            ),
          ]);
      when(() => mockFileRepository.getFile('file-m4')).thenAnswer((_) async => FileItem(
            id: 'file-m4',
            name: 'file4.txt',
            isFolder: false,
            parentId: null,
            createdAt: now,
            updatedAt: now,
          ));
      when(() => mockFileRepository.moveFile('file-m4', 'sub4-id')).thenAnswer((_) async => FileItem(
            id: 'file-m4',
            name: 'file4.txt',
            isFolder: false,
            parentId: 'sub4-id',
            createdAt: now,
            updatedAt: now,
          ));
      when(() => mockPush.reportChange('file-m4', SyncChangeType.move))
          .thenThrow(Exception('server unreachable'));

      final firstPushed = await scanner.scanOnce(tempDir.path);

      expect(firstPushed, 0);
      verify(() => mockFileRepository.moveFile('file-m4', 'sub4-id')).called(1);
      verifyNever(() => mockMirror.upsert(any()));

      clearInteractions(mockFileRepository);
      clearInteractions(mockPush);
      when(() => mockPush.reportChange('file-m4', SyncChangeType.move)).thenAnswer((_) async {});
      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
            subEntry,
            SyncMirrorEntry(
              serverId: 'file-m4',
              localPath: movedFile.path,
              isFolder: false,
              sizeBytes: 12,
              contentHash: hashOf('move payload'),
              updatedAt: past,
              syncedAt: future,
            ),
          ]);

      final secondPushed = await scanner.scanOnce(tempDir.path);

      expect(secondPushed, 1);
      verify(() => mockPush.reportChange('file-m4', SyncChangeType.move)).called(1);
      verify(() => mockMirror.upsert(any())).called(1);
      verifyNever(() => mockFileRepository.moveFile(any(), any()));
    });

    test('delete file: scan 2 -> one reportChange(delete), no second '
        'deleteFile, mirror row removed after it', () async {
      final gonePath = p.join(tempDir.path, 'gone5.txt');

      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
            SyncMirrorEntry(
              serverId: 'file-d5',
              localPath: gonePath,
              isFolder: false,
              sizeBytes: 3,
              contentHash: hashOf('bye'),
              updatedAt: past,
              syncedAt: past,
            ),
          ]);
      when(() => mockFileRepository.deleteFile('file-d5')).thenAnswer((_) async {});
      when(() => mockPush.reportChange('file-d5', SyncChangeType.delete))
          .thenThrow(Exception('server unreachable'));

      final firstPushed = await scanner.scanOnce(tempDir.path);

      expect(firstPushed, 0);
      verify(() => mockFileRepository.deleteFile('file-d5')).called(1);
      verifyNever(() => mockMirror.deleteByServerId(any()));

      clearInteractions(mockFileRepository);
      clearInteractions(mockPush);
      clearInteractions(mockMirror);
      when(() => mockPush.reportChange('file-d5', SyncChangeType.delete)).thenAnswer((_) async {});
      // The flush already cleared this row by the time classify runs.
      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => []);

      final secondPushed = await scanner.scanOnce(tempDir.path);

      expect(secondPushed, 1);
      verify(() => mockPush.reportChange('file-d5', SyncChangeType.delete)).called(1);
      verify(() => mockMirror.deleteByServerId('file-d5')).called(1);
      verifyNever(() => mockFileRepository.deleteFile(any()));
    });

    test('delete folder: scan 2 -> one reportChange(delete), no second '
        'deleteFile, mirror rows for the folder and its children removed', () async {
      final projPath = p.join(tempDir.path, 'proj6');
      final aPath = p.join(projPath, 'a.txt');
      final projEntry = SyncMirrorEntry(
        serverId: 'proj6-id',
        localPath: projPath,
        isFolder: true,
        updatedAt: past,
        syncedAt: past,
      );
      final aEntry = SyncMirrorEntry(
        serverId: 'a6-id',
        localPath: aPath,
        isFolder: false,
        sizeBytes: 1,
        contentHash: hashOf('a'),
        updatedAt: past,
        syncedAt: past,
      );

      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [projEntry, aEntry]);
      when(() => mockMirror.getChildrenUnder(projPath)).thenAnswer((_) async => [aEntry]);
      when(() => mockFileRepository.deleteFile('proj6-id')).thenAnswer((_) async {});
      when(() => mockPush.reportChange('proj6-id', SyncChangeType.delete))
          .thenThrow(Exception('server unreachable'));

      final firstPushed = await scanner.scanOnce(tempDir.path);

      expect(firstPushed, 0);
      verify(() => mockFileRepository.deleteFile('proj6-id')).called(1);
      verifyNever(() => mockMirror.deleteByServerId(any()));

      clearInteractions(mockFileRepository);
      clearInteractions(mockPush);
      clearInteractions(mockMirror);
      when(() => mockPush.reportChange('proj6-id', SyncChangeType.delete)).thenAnswer((_) async {});
      // The flush's mirror effect re-reads getChildrenUnder(projPath) to
      // find the children to clear.
      when(() => mockMirror.getChildrenUnder(projPath)).thenAnswer((_) async => [aEntry]);
      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => []);

      final secondPushed = await scanner.scanOnce(tempDir.path);

      expect(secondPushed, 1);
      verify(() => mockPush.reportChange('proj6-id', SyncChangeType.delete)).called(1);
      verify(() => mockMirror.deleteByServerId('proj6-id')).called(1);
      verify(() => mockMirror.deleteByServerId('a6-id')).called(1);
      verifyNever(() => mockFileRepository.deleteFile(any()));
    });

    test('a flush that keeps failing stops the scan before anything else '
        'runs: no server calls for any other local change in that scan', () async {
      File(p.join(tempDir.path, 'pending7.txt')).writeAsStringSync('x');

      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => []);
      when(() => mockFileRepository.uploadFile(any(that: isNull), 'pending7.txt', any(), 1, any()))
          .thenAnswer((_) async => 'pending7-id');
      when(() => mockPush.reportChange('pending7-id', SyncChangeType.create))
          .thenThrow(Exception('server unreachable'));

      final firstPushed = await scanner.scanOnce(tempDir.path);
      expect(firstPushed, 0);
      verify(() => mockFileRepository.uploadFile(any(that: isNull), 'pending7.txt', any(), 1, any()))
          .called(1);

      // Scan 2: SyncService is still unreachable, and an unrelated local
      // change (a second new file) has shown up since scan 1.
      File(p.join(tempDir.path, 'other7.txt')).writeAsStringSync('y');
      clearInteractions(mockFileRepository);
      clearInteractions(mockPush);
      when(() => mockPush.reportChange('pending7-id', SyncChangeType.create))
          .thenThrow(Exception('still unreachable'));

      final secondPushed = await scanner.scanOnce(tempDir.path);

      expect(secondPushed, 0);
      verify(() => mockPush.reportChange('pending7-id', SyncChangeType.create)).called(1);
      verifyNever(() => mockFileRepository.uploadFile(any(), any(), any(), any(), any()));
    });

    test('restart path (no pending state): a rename already applied '
        'server-side is still reported, without calling renameFile again', () async {
      final oldPath = p.join(tempDir.path, 'old8.txt');
      final newFile = File(p.join(tempDir.path, 'new8.txt'))..writeAsStringSync('same bytes 8');

      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
            SyncMirrorEntry(
              serverId: 'file-r8',
              localPath: oldPath,
              isFolder: false,
              sizeBytes: 12,
              contentHash: hashOf('same bytes 8'),
              updatedAt: past,
              syncedAt: past,
            ),
          ]);
      // getFile already reflects the new name — the server side of an
      // earlier, only-partially-completed attempt at this exact rename
      // (renameFile had succeeded, but the app restarted before
      // reportChange was ever attempted, losing the in-memory
      // _pendingReports entry that same-session retries use instead).
      when(() => mockFileRepository.getFile('file-r8')).thenAnswer((_) async => FileItem(
            id: 'file-r8',
            name: 'new8.txt',
            isFolder: false,
            parentId: null,
            createdAt: now,
            updatedAt: now,
          ));

      final pushed = await scanner.scanOnce(tempDir.path);

      expect(pushed, 1);
      verifyNever(() => mockFileRepository.renameFile(any(), any()));
      verify(() => mockPush.reportChange('file-r8', SyncChangeType.rename)).called(1);
      final upserted = verify(() => mockMirror.upsert(captureAny())).captured.single as SyncMirrorEntry;
      expect(upserted.localPath, newFile.path);
    });

    test('restart path (no pending state): a folder deleteFile that '
        '404s still reports, and mirror rows under it are removed', () async {
      final projPath = p.join(tempDir.path, 'proj9');
      final aPath = p.join(projPath, 'a9.txt');
      final projEntry = SyncMirrorEntry(
        serverId: 'proj9-id',
        localPath: projPath,
        isFolder: true,
        updatedAt: past,
        syncedAt: past,
      );
      final aEntry = SyncMirrorEntry(
        serverId: 'a9-id',
        localPath: aPath,
        isFolder: false,
        sizeBytes: 1,
        contentHash: hashOf('a'),
        updatedAt: past,
        syncedAt: past,
      );

      when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [projEntry, aEntry]);
      when(() => mockMirror.getChildrenUnder(projPath)).thenAnswer((_) async => [aEntry]);
      when(() => mockFileRepository.deleteFile('proj9-id')).thenThrow(dioError(404));

      final pushed = await scanner.scanOnce(tempDir.path);

      expect(pushed, 0); // already gone server-side too; not a new push
      verify(() => mockPush.reportChange('proj9-id', SyncChangeType.delete)).called(1);
      verify(() => mockMirror.deleteByServerId('proj9-id')).called(1);
      verify(() => mockMirror.deleteByServerId('a9-id')).called(1);
    });
  });

  test('finding 4: a case-only folder rename whose renameFile throws does '
      'not crash the scan, and backs the path off', () async {
    final docsDir = Directory(p.join(tempDir.path, 'docs10'))..createSync();
    File(p.join(docsDir.path, 'child.txt')).writeAsStringSync('x');
    final oldDocsPath = p.join(tempDir.path, 'Docs10');

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
          SyncMirrorEntry(
            serverId: 'docs10-id',
            localPath: oldDocsPath,
            isFolder: true,
            updatedAt: past,
            syncedAt: past,
          ),
        ]);
    when(() => mockFileRepository.renameFile('docs10-id', 'docs10'))
        .thenThrow(Exception('server unreachable'));

    final caseScanner = scannerWith(isWindows: false, isCaseInsensitive: true);

    final firstPushed = await caseScanner.scanOnce(tempDir.path);
    expect(firstPushed, 0); // did not throw out of scanOnce

    final secondPushed = await caseScanner.scanOnce(tempDir.path);
    expect(secondPushed, 0);

    // Backed off: only the first scan attempted the rename.
    verify(() => mockFileRepository.renameFile('docs10-id', 'docs10')).called(1);
  });

  test('finding 5: a getFile 404 during a move drops the stale mirror row '
      'instead of calling moveFile/renameFile', () async {
    final subDir = Directory(p.join(tempDir.path, 'sub11'))..createSync();
    final oldPath = p.join(tempDir.path, 'file11.txt');
    File(p.join(subDir.path, 'file11.txt')).writeAsStringSync('gone payload');

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
          SyncMirrorEntry(
            serverId: 'sub11-id',
            localPath: subDir.path,
            isFolder: true,
            updatedAt: past,
            syncedAt: past,
          ),
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
    verify(() => mockMirror.deleteByServerId('file-g11')).called(1);
    verifyNever(() => mockPush.reportChange(any(), any()));
  });

  test('finding 6: an unhashed new file whose stat reports an unknown size '
      'protects same-size missing files instead of deleting them', () async {
    final oldPath = p.join(tempDir.path, 'gone12.bin');
    final newFile = File(p.join(tempDir.path, 'unknown12.bin'))..writeAsBytesSync(List.filled(9, 1));

    when(() => mockMirror.getChildrenUnder(tempDir.path)).thenAnswer((_) async => [
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
}

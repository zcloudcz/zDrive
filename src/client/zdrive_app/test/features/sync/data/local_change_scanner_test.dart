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

  LocalChangeScanner scannerWith({required bool isWindows}) =>
      LocalChangeScanner(mockMirror, mockFileRepository, mockPush, isWindows: isWindows);

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
}

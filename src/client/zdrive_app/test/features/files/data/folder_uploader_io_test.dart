import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/files/data/file_dtos.dart';
import 'package:zdrive_app/features/files/data/file_remote_data_source.dart';
import 'package:zdrive_app/features/files/data/file_upload_data_source.dart';
import 'package:zdrive_app/features/files/data/folder_uploader_io.dart';
import 'package:zdrive_app/features/files/domain/file_item.dart';
import 'package:zdrive_app/features/files/domain/file_repository.dart';

class MockFileRepository extends Mock implements FileRepository {}

class MockFileUploadDataSource extends Mock implements FileUploadDataSource {}

class MockFileRemoteDataSource extends Mock implements FileRemoteDataSource {}

void main() {
  late MockFileRepository repository;
  late MockFileUploadDataSource uploadDataSource;
  late MockFileRemoteDataSource remoteDataSource;
  late Directory tempRoot;

  final now = DateTime(2026, 1, 1);

  FileItem fileItem(String id, String name, {bool isFolder = false}) => FileItem(
        id: id,
        name: name,
        isFolder: isFolder,
        createdAt: now,
        updatedAt: now,
      );

  PagedResult<FileItem> paged(List<FileItem> items) => PagedResult(
        items: items,
        totalCount: items.length,
        page: 1,
        pageSize: 200,
      );

  setUpAll(() {
    registerFallbackValue(const Stream<List<int>>.empty());
  });

  setUp(() async {
    repository = MockFileRepository();
    uploadDataSource = MockFileUploadDataSource();
    remoteDataSource = MockFileRemoteDataSource();
    tempRoot = await Directory.systemTemp.createTemp('folder_uploader_test_');
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('creates missing remote folders and uploads new files under them', () async {
    // root/
    //   top.txt
    //   sub/
    //     nested.txt
    await File('${tempRoot.path}/top.txt').writeAsString('top-content');
    final subDir = Directory('${tempRoot.path}/sub')..createSync();
    await File('${subDir.path}/nested.txt').writeAsString('nested-content');

    when(() => repository.listChildren('root-id', page: 1, pageSize: 200))
        .thenAnswer((_) async => paged([]));
    when(() => repository.listChildren('sub-id', page: 1, pageSize: 200))
        .thenAnswer((_) async => paged([]));
    when(() => repository.createFolder('root-id', 'sub'))
        .thenAnswer((_) async => fileItem('sub-id', 'sub', isFolder: true));
    when(() => repository.uploadFile(any(), any(), any(), any(), any()))
        .thenAnswer((_) async => 'new-file-id');

    await mirrorDirectory(repository, uploadDataSource, remoteDataSource, tempRoot, 'root-id');

    verify(() => repository.createFolder('root-id', 'sub')).called(1);
    verify(() => repository.uploadFile('root-id', 'top.txt', any(), 'top-content'.length, null))
        .called(1);
    verify(() => repository.uploadFile('sub-id', 'nested.txt', any(), 'nested-content'.length, null))
        .called(1);
    // Nothing to skip in a fresh upload, so the manifest-comparison path is
    // never even consulted.
    verifyNever(() => uploadDataSource.tryGetManifest(any()));
  });

  test('reuses an existing remote folder with the same name instead of creating a duplicate',
      () async {
    Directory('${tempRoot.path}/sub').createSync();

    when(() => repository.listChildren('root-id', page: 1, pageSize: 200)).thenAnswer(
        (_) async => paged([fileItem('sub-id', 'sub', isFolder: true)]));
    when(() => repository.listChildren('sub-id', page: 1, pageSize: 200))
        .thenAnswer((_) async => paged([]));

    await mirrorDirectory(repository, uploadDataSource, remoteDataSource, tempRoot, 'root-id');

    verifyNever(() => repository.createFolder('root-id', 'sub'));
  });

  test('skips a file whose remote manifest already matches its local content', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    await File('${tempRoot.path}/same.bin').writeAsBytes(bytes);
    final hash = sha256.convert(bytes).toString();

    when(() => repository.listChildren('root-id', page: 1, pageSize: 200)).thenAnswer(
        (_) async => paged([fileItem('existing-id', 'same.bin')]));
    when(() => uploadDataSource.tryGetManifest('existing-id')).thenAnswer((_) async =>
        ManifestDto(totalSize: bytes.length, chunks: [ManifestChunkDto(hash: hash, index: 0)]));

    await mirrorDirectory(repository, uploadDataSource, remoteDataSource, tempRoot, 'root-id');

    verifyNever(() => repository.uploadFile(any(), any(), any(), any(), any()));
    verifyNever(() => uploadDataSource.uploadFile(any(), any(), any(), any()));
  });

  test('re-uploads into the same node when the remote manifest no longer matches', () async {
    final bytes = Uint8List.fromList([9, 9, 9]);
    await File('${tempRoot.path}/changed.bin').writeAsBytes(bytes);

    when(() => repository.listChildren('root-id', page: 1, pageSize: 200)).thenAnswer(
        (_) async => paged([fileItem('existing-id', 'changed.bin')]));
    // Remote manifest reflects different (stale) content.
    when(() => uploadDataSource.tryGetManifest('existing-id')).thenAnswer((_) async =>
        const ManifestDto(
            totalSize: 999, chunks: [ManifestChunkDto(hash: 'stale-hash', index: 0)]));
    when(() => uploadDataSource.uploadFile('existing-id', 'changed.bin', any(), bytes.length))
        .thenAnswer((_) async =>
            const UploadCompleteDto(blobPath: 'p', manifestHash: 'new-hash', totalSize: 3));
    when(() => remoteDataSource.createFileVersion(
          'existing-id',
          blobVersionId: any(named: 'blobVersionId'),
          sizeBytes: any(named: 'sizeBytes'),
          manifestHash: any(named: 'manifestHash'),
        )).thenAnswer((_) async => <String, dynamic>{});

    await mirrorDirectory(repository, uploadDataSource, remoteDataSource, tempRoot, 'root-id');

    verify(() => uploadDataSource.uploadFile('existing-id', 'changed.bin', any(), bytes.length))
        .called(1);
    verify(() => remoteDataSource.createFileVersion('existing-id',
        blobVersionId: 'new-hash', sizeBytes: 3, manifestHash: 'new-hash')).called(1);
    // Must not also go through the fresh-upload path — FileService rejects
    // a second createFile() with a name that already exists in this folder.
    verifyNever(() => repository.uploadFile(any(), any(), any(), any(), any()));
  });

  test('one failed file does not abort the rest of the directory', () async {
    await File('${tempRoot.path}/a.txt').writeAsString('a');
    await File('${tempRoot.path}/b.txt').writeAsString('b');

    when(() => repository.listChildren('root-id', page: 1, pageSize: 200))
        .thenAnswer((_) async => paged([]));
    // Simulates e.g. the 409 a local directory's namesake file would hit.
    when(() => repository.uploadFile('root-id', 'a.txt', any(), 1, null))
        .thenThrow(Exception('409 Conflict'));
    when(() => repository.uploadFile('root-id', 'b.txt', any(), 1, null))
        .thenAnswer((_) async => 'b-id');

    await mirrorDirectory(repository, uploadDataSource, remoteDataSource, tempRoot, 'root-id');

    // Without per-item isolation, a.txt's exception would propagate out of
    // mirrorDirectory before b.txt (sorted after it) is ever reached.
    verify(() => repository.uploadFile('root-id', 'b.txt', any(), 1, null)).called(1);
  });

  test('does not follow a symlink, so it cannot loop back into an ancestor', () async {
    // Point a symlink inside the root back at the root itself — the exact
    // "infinite recursion" hazard BackupRunner.cs's ReparsePoint check
    // guards against. A sibling-target symlink instead of this
    // self-reference could pass even without the fix, if recursion happened
    // to terminate on its own.
    await Link('${tempRoot.path}/loop').create(tempRoot.path);

    when(() => repository.listChildren(any(), page: 1, pageSize: 200))
        .thenAnswer((_) async => paged([]));

    await mirrorDirectory(repository, uploadDataSource, remoteDataSource, tempRoot, 'root-id')
        .timeout(const Duration(seconds: 5));

    verifyNever(() => repository.createFolder(any(), 'loop'));
  });

  test('uploadDirectoryAsRoot uploads under a remote folder named after the picked directory',
      () async {
    // Mirrors downloadFolder, which saves a downloaded tree into
    // `<destination>/<folder.name>` rather than scattering it directly into
    // the destination.
    final picked = Directory('${tempRoot.path}/Photos')..createSync();
    await File('${picked.path}/pic.jpg').writeAsString('data');

    when(() => repository.listChildren('parent-id', page: 1, pageSize: 200))
        .thenAnswer((_) async => paged([]));
    when(() => repository.createFolder('parent-id', 'Photos'))
        .thenAnswer((_) async => fileItem('photos-id', 'Photos', isFolder: true));
    when(() => repository.listChildren('photos-id', page: 1, pageSize: 200))
        .thenAnswer((_) async => paged([]));
    when(() => repository.uploadFile('photos-id', 'pic.jpg', any(), 4, null))
        .thenAnswer((_) async => 'pic-id');

    await uploadDirectoryAsRoot(repository, uploadDataSource, remoteDataSource, picked, 'parent-id');

    verify(() => repository.createFolder('parent-id', 'Photos')).called(1);
    verify(() => repository.uploadFile('photos-id', 'pic.jpg', any(), 4, null)).called(1);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/files/data/file_dtos.dart';
import 'package:zdrive_app/features/files/data/file_remote_data_source.dart';
import 'package:zdrive_app/features/files/data/file_repository_impl.dart';
import 'package:zdrive_app/features/files/data/file_upload_data_source.dart';

class MockFileRemoteDataSource extends Mock implements FileRemoteDataSource {}

class MockFileUploadDataSource extends Mock implements FileUploadDataSource {}

void main() {
  late MockFileRemoteDataSource remote;
  late MockFileUploadDataSource upload;
  late FileRepositoryImpl repository;

  final now = DateTime(2026, 1, 1);

  FileDto fileDto(String id, String name, {bool isFolder = false}) => FileDto(
        id: id,
        name: name,
        isFolder: isFolder,
        createdAt: now,
        updatedAt: now,
      );

  PagedResultDto paged(List<FileDto> items) => PagedResultDto(
        items: items.map((e) => e.toJson()).toList(),
        totalCount: items.length,
        page: 1,
        pageSize: 200,
      );

  setUpAll(() {
    registerFallbackValue(const Stream<List<int>>.empty());
  });

  setUp(() {
    remote = MockFileRemoteDataSource();
    upload = MockFileUploadDataSource();
    repository = FileRepositoryImpl(remote, upload);
  });

  test('uploadFile creates a new node when no file with that name exists', () async {
    when(() => remote.listChildren(null, page: 1, pageSize: 200))
        .thenAnswer((_) async => paged([]));
    when(() => remote.createFile(
          name: 'report.pdf',
          isFolder: false,
          parentId: null,
          sizeBytes: 10,
        )).thenAnswer((_) async => fileDto('new-id', 'report.pdf'));
    when(() => upload.uploadFile('new-id', 'report.pdf', any(), 10,
            onProgress: any(named: 'onProgress')))
        .thenAnswer((_) async =>
            const UploadCompleteDto(blobPath: 'p', manifestHash: 'hash-1', totalSize: 10));
    when(() => remote.createFileVersion('new-id',
        blobVersionId: 'hash-1',
        sizeBytes: 10,
        manifestHash: 'hash-1')).thenAnswer((_) async => <String, dynamic>{});

    final id = await repository.uploadFile(null, 'report.pdf', const Stream.empty(), 10, null);

    expect(id, 'new-id');
    verify(() => remote.createFile(
          name: 'report.pdf',
          isFolder: false,
          parentId: null,
          sizeBytes: 10,
        )).called(1);
  });

  test(
      'uploadFile reuses the node a previously failed attempt already created, '
      'instead of hitting the duplicate-name 409 on retry', () async {
    // A chunk upload that died mid-transfer (e.g. the rate-limit pause in
    // dio_client.dart) leaves the node createFile() made with no manifest —
    // exactly what a retry of the same file finds here.
    when(() => remote.listChildren(null, page: 1, pageSize: 200))
        .thenAnswer((_) async => paged([fileDto('orphan-id', 'report.pdf')]));
    when(() => upload.uploadFile('orphan-id', 'report.pdf', any(), 10,
            onProgress: any(named: 'onProgress')))
        .thenAnswer((_) async =>
            const UploadCompleteDto(blobPath: 'p', manifestHash: 'hash-2', totalSize: 10));
    when(() => remote.createFileVersion('orphan-id',
        blobVersionId: 'hash-2',
        sizeBytes: 10,
        manifestHash: 'hash-2')).thenAnswer((_) async => <String, dynamic>{});

    final id = await repository.uploadFile(null, 'report.pdf', const Stream.empty(), 10, null);

    expect(id, 'orphan-id');
    // Must not go through createFile — CreateFileCommandHandler.cs rejects a
    // second call with this name in this folder as a duplicate (409).
    verifyNever(() => remote.createFile(
          name: any(named: 'name'),
          isFolder: any(named: 'isFolder'),
          parentId: any(named: 'parentId'),
          sizeBytes: any(named: 'sizeBytes'),
        ));
  });
}

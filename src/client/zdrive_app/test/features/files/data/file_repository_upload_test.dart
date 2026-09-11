import 'package:dio/dio.dart';
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

  FileDto fileDto(String id, String name,
          {bool isFolder = false, String? manifestHash}) =>
      FileDto(
        id: id,
        name: name,
        isFolder: isFolder,
        manifestHash: manifestHash,
        createdAt: now,
        updatedAt: now,
      );

  PagedResultDto paged(List<FileDto> items) => PagedResultDto(
        items: items.map((e) => e.toJson()).toList(),
        totalCount: items.length,
        page: 1,
        pageSize: 200,
      );

  // FileService's CreateFileCommandHandler rejects a duplicate name in the
  // same folder with a 409 (ConflictException) — this is what a real
  // createFile() call throws through Dio's default validateStatus.
  DioException conflict409() => DioException(
        requestOptions: RequestOptions(path: '/api/v1/files'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/v1/files'),
          statusCode: 409,
        ),
        type: DioExceptionType.badResponse,
      );

  setUpAll(() {
    registerFallbackValue(const Stream<List<int>>.empty());
  });

  setUp(() {
    remote = MockFileRemoteDataSource();
    upload = MockFileUploadDataSource();
    repository = FileRepositoryImpl(remote, upload);
  });

  test('uploadFile creates a new node when no name conflict occurs', () async {
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
    // The happy path must never list children: that lookup is only for
    // resolving a 409, and doing it unconditionally is what made folder
    // uploads quadratic (round-2 review finding 4).
    verifyNever(() => remote.listChildren(any(), page: any(named: 'page'), pageSize: any(named: 'pageSize')));
  });

  test(
      'uploadFile reuses the conflicting node on a 409 when it is an orphan '
      '(manifestHash null) from a previously failed upload', () async {
    when(() => remote.createFile(
          name: 'report.pdf',
          isFolder: false,
          parentId: null,
          sizeBytes: 10,
        )).thenThrow(conflict409());
    when(() => remote.listChildren(null, page: 1, pageSize: 200)).thenAnswer(
        (_) async => paged([fileDto('orphan-id', 'report.pdf', manifestHash: null)]));
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
  });

  test(
      'uploadFile surfaces the 409 unchanged when the conflicting node already '
      'has content (manifestHash non-null) — a genuine duplicate, not an orphan',
      () async {
    when(() => remote.createFile(
          name: 'report.pdf',
          isFolder: false,
          parentId: null,
          sizeBytes: 10,
        )).thenThrow(conflict409());
    when(() => remote.listChildren(null, page: 1, pageSize: 200)).thenAnswer(
        (_) async => paged(
            [fileDto('existing-id', 'report.pdf', manifestHash: 'already-uploaded-hash')]));

    await expectLater(
      repository.uploadFile(null, 'report.pdf', const Stream.empty(), 10, null),
      throwsA(isA<DioException>()),
    );

    // Must not touch the completed file's content — displacing it silently
    // is exactly the data-loss bug this reuse logic must not reintroduce
    // (round-2 review finding 3).
    verifyNever(() => upload.uploadFile(any(), any(), any(), any(),
        onProgress: any(named: 'onProgress')));
  });
}

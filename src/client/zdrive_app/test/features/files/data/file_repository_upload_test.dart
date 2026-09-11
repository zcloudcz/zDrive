import 'dart:async';
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
      'uploadFile surfaces the 409 unchanged when the conflicting node has '
      'manifestHash null but this instance never created it — e.g. another '
      'device\'s upload is still running, or an orphan from a previous app '
      'run (round-3 review finding 1: manifestHash null alone must not '
      'trigger reuse)', () async {
    when(() => remote.createFile(
          name: 'report.pdf',
          isFolder: false,
          parentId: null,
          sizeBytes: 10,
        )).thenThrow(conflict409());
    when(() => remote.listChildren(null, page: 1, pageSize: 200)).thenAnswer(
        (_) async => paged([fileDto('stranger-id', 'report.pdf', manifestHash: null)]));
    // Stubbed so that, if the guard under test regresses and reuse happens
    // anyway, the test fails on a clean "did not throw" assertion instead of
    // an incidental MissingStubError from an unstubbed downstream mock call.
    when(() => upload.uploadFile('stranger-id', 'report.pdf', any(), 10,
            onProgress: any(named: 'onProgress')))
        .thenAnswer((_) async =>
            const UploadCompleteDto(blobPath: 'p', manifestHash: 'hash-x', totalSize: 10));
    when(() => remote.createFileVersion('stranger-id',
        blobVersionId: 'hash-x',
        sizeBytes: 10,
        manifestHash: 'hash-x')).thenAnswer((_) async => <String, dynamic>{});

    await expectLater(
      repository.uploadFile(null, 'report.pdf', const Stream.empty(), 10, null),
      throwsA(isA<DioException>()),
    );

    // Must not touch the node another upload might still be writing into.
    verifyNever(() => upload.uploadFile(any(), any(), any(), any(),
        onProgress: any(named: 'onProgress')));
  });

  test(
      'uploadFile reuses the conflicting node on a 409 only when this '
      'instance itself created that exact node and then failed to upload '
      'into it (round-3 review finding 1: the fix for the case above)',
      () async {
    when(() => remote.createFile(
          name: 'report.pdf',
          isFolder: false,
          parentId: null,
          sizeBytes: 10,
        )).thenAnswer((_) async => fileDto('retry-id', 'report.pdf'));
    when(() => upload.uploadFile('retry-id', 'report.pdf', any(), 10,
            onProgress: any(named: 'onProgress')))
        .thenThrow(Exception('network dropped mid-transfer'));

    // First attempt: this instance creates 'retry-id' and then fails to
    // upload into it — that failure is what makes the id eligible for reuse.
    await expectLater(
      repository.uploadFile(null, 'report.pdf', const Stream.empty(), 10, null),
      throwsException,
    );

    // Second attempt, same name: createFile 409s against the still-existing
    // node from attempt 1. Because this instance remembers creating and
    // failing that exact node, it reuses it instead of surfacing the 409.
    when(() => remote.createFile(
          name: 'report.pdf',
          isFolder: false,
          parentId: null,
          sizeBytes: 10,
        )).thenThrow(conflict409());
    when(() => remote.listChildren(null, page: 1, pageSize: 200)).thenAnswer(
        (_) async => paged([fileDto('retry-id', 'report.pdf', manifestHash: null)]));
    when(() => upload.uploadFile('retry-id', 'report.pdf', any(), 10,
            onProgress: any(named: 'onProgress')))
        .thenAnswer((_) async =>
            const UploadCompleteDto(blobPath: 'p', manifestHash: 'hash-2', totalSize: 10));
    when(() => remote.createFileVersion('retry-id',
        blobVersionId: 'hash-2',
        sizeBytes: 10,
        manifestHash: 'hash-2')).thenAnswer((_) async => <String, dynamic>{});

    final id = await repository.uploadFile(null, 'report.pdf', const Stream.empty(), 10, null);

    expect(id, 'retry-id');
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

  test(
      'uploadFile hands a failed node out at most once: while one retry is '
      'still uploading into it, a third upload of the same name gets the 409 '
      'instead of reusing the node too (round-4 review)', () async {
    // Attempt 1: this instance creates retry-id and fails to fill it, which
    // is what makes retry-id eligible for reuse.
    when(() => remote.createFile(
          name: 'report.pdf',
          isFolder: false,
          parentId: null,
          sizeBytes: 10,
        )).thenAnswer((_) async => fileDto('retry-id', 'report.pdf'));
    when(() => upload.uploadFile('retry-id', 'report.pdf', any(), 10,
            onProgress: any(named: 'onProgress')))
        .thenThrow(Exception('network dropped mid-transfer'));
    await expectLater(
      repository.uploadFile(null, 'report.pdf', const Stream.empty(), 10, null),
      throwsException,
    );
    clearInteractions(upload);

    // From here on createFile 409s against retry-id, which is still empty,
    // and an upload into it blocks until released, so attempt 2 stays in
    // flight while attempt 3 runs.
    final release = Completer<UploadCompleteDto>();
    when(() => remote.createFile(
          name: 'report.pdf',
          isFolder: false,
          parentId: null,
          sizeBytes: 10,
        )).thenThrow(conflict409());
    when(() => remote.listChildren(null, page: 1, pageSize: 200)).thenAnswer(
        (_) async => paged([fileDto('retry-id', 'report.pdf', manifestHash: null)]));
    when(() => upload.uploadFile('retry-id', 'report.pdf', any(), 10,
            onProgress: any(named: 'onProgress')))
        .thenAnswer((_) => release.future);
    when(() => remote.createFileVersion('retry-id',
        blobVersionId: 'hash-2',
        sizeBytes: 10,
        manifestHash: 'hash-2')).thenAnswer((_) async => <String, dynamic>{});

    // Attempt 2 reuses retry-id and blocks inside the upload.
    final second =
        repository.uploadFile(null, 'report.pdf', const Stream.empty(), 10, null);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    // Attempt 3, same name, while attempt 2 is still uploading into retry-id:
    // must get the 409, not a second claim on the same node.
    await expectLater(
      repository.uploadFile(null, 'report.pdf', const Stream.empty(), 10, null),
      throwsA(isA<DioException>()),
    );
    verify(() => upload.uploadFile('retry-id', 'report.pdf', any(), 10,
        onProgress: any(named: 'onProgress'))).called(1);

    release.complete(
        const UploadCompleteDto(blobPath: 'p', manifestHash: 'hash-2', totalSize: 10));
    expect(await second, 'retry-id');
  });

  group('uploadNewVersion', () {
    test('uploads into the given id and records a version, without creating '
        'a node', () async {
      when(() => upload.uploadFile('existing-id', 'doc.txt', any(), 10,
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async =>
              const UploadCompleteDto(blobPath: 'p', manifestHash: 'hash-3', totalSize: 10));
      when(() => remote.createFileVersion('existing-id',
          blobVersionId: 'hash-3',
          sizeBytes: 10,
          manifestHash: 'hash-3')).thenAnswer((_) async => <String, dynamic>{});

      await repository.uploadNewVersion(
          'existing-id', 'doc.txt', const Stream.empty(), 10);

      verify(() => remote.createFileVersion('existing-id',
          blobVersionId: 'hash-3', sizeBytes: 10, manifestHash: 'hash-3')).called(1);
      verifyNever(() => remote.createFile(
          name: any(named: 'name'),
          isFolder: any(named: 'isFolder'),
          parentId: any(named: 'parentId'),
          sizeBytes: any(named: 'sizeBytes')));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/files/data/file_remote_data_source.dart';
import 'package:zdrive_app/features/files/data/file_repository_impl.dart';
import 'package:zdrive_app/features/files/data/file_upload_data_source.dart';

class MockFileRemoteDataSource extends Mock implements FileRemoteDataSource {}

class MockFileUploadDataSource extends Mock implements FileUploadDataSource {}

void main() {
  late MockFileRemoteDataSource remote;
  late FileRepositoryImpl repository;

  Map<String, dynamic> versionJson({
    String id = 'version-1',
    int number = 1,
    String blobVersionId = 'manifest-hash-1',
    int sizeBytes = 100,
    String? comment,
  }) =>
      {
        'id': id,
        'fileId': 'file-1',
        'versionNumber': number,
        'blobVersionId': blobVersionId,
        'sizeBytes': sizeBytes,
        'manifestHash': blobVersionId,
        'createdBy': 'user-1',
        'comment': comment,
        'createdAt': '2026-06-11T10:00:00Z',
      };

  setUp(() {
    remote = MockFileRemoteDataSource();
    repository = FileRepositoryImpl(remote, MockFileUploadDataSource());
  });

  test('getVersions maps the API payload to domain models', () async {
    when(() => remote.getFileVersions('file-1')).thenAnswer((_) async => [
          versionJson(id: 'v2', number: 2, sizeBytes: 200, comment: 'second'),
          versionJson(id: 'v1', number: 1),
        ]);

    final versions = await repository.getVersions('file-1');

    expect(versions, hasLength(2));
    expect(versions.first.versionNumber, 2);
    expect(versions.first.comment, 'second');
    expect(versions.last.blobVersionId, 'manifest-hash-1');
    expect(versions.last.createdAt, DateTime.parse('2026-06-11T10:00:00Z'));
  });

  test('restoreVersion restores metadata first, then the blob manifest', () async {
    when(() => remote.restoreFileVersion('file-1', 'v1')).thenAnswer(
      (_) async => versionJson(
        id: 'v3',
        number: 3,
        blobVersionId: 'manifest-hash-1',
        comment: 'Restored from version 1',
      ),
    );
    when(() => remote.restoreStorageManifest('file-1', 'manifest-hash-1'))
        .thenAnswer((_) async {});

    final restored = await repository.restoreVersion('file-1', 'v1');

    expect(restored.versionNumber, 3);
    expect(restored.comment, 'Restored from version 1');

    // Order matters: FileService validates ownership before the blob flips.
    verifyInOrder([
      () => remote.restoreFileVersion('file-1', 'v1'),
      () => remote.restoreStorageManifest('file-1', 'manifest-hash-1'),
    ]);
  });

  test('restoreVersion does not flip the blob manifest when metadata restore fails',
      () async {
    when(() => remote.restoreFileVersion('file-1', 'missing'))
        .thenThrow(Exception('404'));

    await expectLater(
      repository.restoreVersion('file-1', 'missing'),
      throwsA(isA<Exception>()),
    );

    verifyNever(() => remote.restoreStorageManifest(any(), any()));
  });
}

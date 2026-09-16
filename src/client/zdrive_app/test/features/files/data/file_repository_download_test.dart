import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/files/data/file_dtos.dart';
import 'package:zdrive_app/features/files/data/file_remote_data_source.dart';
import 'package:zdrive_app/features/files/data/file_repository_impl.dart';
import 'package:zdrive_app/features/files/data/file_upload_data_source.dart';

class MockRemote extends Mock implements FileRemoteDataSource {}
class MockDio extends Mock implements Dio {}

void main() {
  for (final hash in <String?>[null, '', 'invalid']) {
    test('Download_UncommittedMetadata($hash)_DoesNotContactStorage', () async {
      final remote = MockRemote();
      final dio = MockDio();
      final repository = FileRepositoryImpl(remote, FileUploadDataSource(dio));
      final now = DateTime.utc(2026);
      when(() => remote.getFile('f1')).thenAnswer((_) async => FileDto(
        id: 'f1', name: 'incomplete', isFolder: false,
        manifestHash: hash, createdAt: now, updatedAt: now,
      ));
      await expectLater(repository.downloadFile('f1'), throwsStateError);
      verifyZeroInteractions(dio);
    });
  }

  test('Download_AfterRestoreFlipFails_ReadsCommittedSnapshot', () async {
    final remote = MockRemote();
    final dio = MockDio();
    final repository = FileRepositoryImpl(remote, FileUploadDataSource(dio));
    final committedHash = 'a' * 64;
    final restored = Uint8List.fromList([1, 2, 3]);
    final latest = Uint8List.fromList([4, 5, 6]);
    final now = DateTime.utc(2026);
    when(() => remote.restoreFileVersion('f1', 'v1')).thenAnswer((_) async => {
      'id': 'v3', 'fileId': 'f1', 'versionNumber': 3,
      'blobVersionId': committedHash, 'manifestHash': committedHash,
      'sizeBytes': 3, 'createdAt': now.toIso8601String(),
    });
    when(() => remote.restoreStorageManifest('f1', committedHash))
        .thenThrow(Exception('latest flip failed'));
    when(() => remote.getFile('f1')).thenAnswer((_) async => FileDto(
      id: 'f1', name: 'file.bin', isFolder: false, sizeBytes: 3,
      manifestHash: committedHash, createdAt: now, updatedAt: now,
    ));
    when(() => dio.get('/storage/download/f1/manifest',
      queryParameters: any(named: 'queryParameters'),
    )).thenAnswer((call) async {
      final query = call.namedArguments[#queryParameters] as Map<String, dynamic>?;
      final bytes = query?['manifestHash'] == committedHash ? restored : latest;
      return Response(data: {'success': true, 'data': {
        'manifestHash': query?['manifestHash'], 'totalSize': 3, 'chunks': [{'index': 0, 'hash': sha256.convert(bytes).toString()}],
      }}, requestOptions: RequestOptions(path: 'manifest'));
    });
    registerFallbackValue(Options());
    for (final bytes in [restored, latest]) {
      when(() => dio.get<List<int>>('/storage/download/f1/chunk/${sha256.convert(bytes)}/bytes',
        options: any(named: 'options'),
      )).thenAnswer((_) async => Response(data: bytes, requestOptions: RequestOptions(path: 'chunk')));
    }

    await expectLater(repository.restoreVersion('f1', 'v1'), throwsException);
    expect(await repository.downloadFile('f1'), restored);
  });
}

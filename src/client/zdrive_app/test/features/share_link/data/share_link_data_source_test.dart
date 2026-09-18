import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/share_link/data/share_link_data_source.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late ShareLinkDataSource ds;

  Response<dynamic> ok(dynamic data, String path) => Response<dynamic>(
        data: {'success': true, 'data': data, 'error': null},
        statusCode: 200,
        requestOptions: RequestOptions(path: path),
      );

  final fileJson = {
    'id': 'f1',
    'name': 'report.pdf',
    'isFolder': false,
    'sizeBytes': 10,
    'mimeType': 'application/pdf',
    'parentId': null,
    'manifestHash': 'h1',
    'createdAt': '2026-01-01T00:00:00.000Z',
    'updatedAt': '2026-01-01T00:00:00.000Z',
    'isDeleted': false,
  };
  final shareJson = {
    'id': 's1',
    'fileId': 'f1',
    'permission': 'read',
    'linkToken': 'tok123',
    'expiresAt': null,
  };

  setUpAll(() => registerFallbackValue(Options()));

  setUp(() {
    dio = MockDio();
    ds = ShareLinkDataSource(dio);
  });

  test('getShareLink GETs /shares/link/{token} and unwraps share + file', () async {
    when(() => dio.get('/shares/link/tok123')).thenAnswer(
        (_) async => ok({'share': shareJson, 'file': fileJson}, '/shares/link/tok123'));

    final result = await ds.getShareLink('tok123');

    expect(result.share.linkToken, 'tok123');
    expect(result.file.name, 'report.pdf');
  });

  test('getChildren GETs /shares/link/{token}/children with folderId when given', () async {
    when(() => dio.get('/shares/link/tok123/children',
        queryParameters: {'folderId': 'd1'})).thenAnswer(
        (_) async => ok([fileJson], '/shares/link/tok123/children'));

    final children = await ds.getChildren('tok123', folderId: 'd1');

    expect(children.single.id, 'f1');
  });

  test('getChildren omits folderId query parameter for the shared root', () async {
    when(() => dio.get('/shares/link/tok123/children', queryParameters: null))
        .thenAnswer((_) async => ok(<dynamic>[], '/shares/link/tok123/children'));

    await ds.getChildren('tok123');

    verify(() => dio.get('/shares/link/tok123/children', queryParameters: null)).called(1);
  });

  test('requestDownloadGrant POSTs {fileId} to /shares/link/{token}/download-grant', () async {
    when(() => dio.post('/shares/link/tok123/download-grant', data: any(named: 'data')))
        .thenAnswer((_) async => ok({
              'grant': 'g1',
              'expiresAt': '2026-01-01T00:05:00.000Z',
              'fileId': 'f1',
              'fileName': 'report.pdf',
              'sizeBytes': 10,
              'manifestHash': 'h1',
            }, '/shares/link/tok123/download-grant'));

    final grant = await ds.requestDownloadGrant('tok123', 'f1');

    expect(grant.grant, 'g1');
    verify(() => dio.post('/shares/link/tok123/download-grant',
        data: {'fileId': 'f1'})).called(1);
  });

  test('getManifest sends the grant as X-Share-Grant', () async {
    when(() => dio.get('/storage/shared/manifest', options: any(named: 'options')))
        .thenAnswer((_) async => ok({
              'totalSize': 3,
              'chunks': [
                {'index': 0, 'hash': 'a' * 64}
              ],
              'manifestHash': null,
            }, '/storage/shared/manifest'));

    await ds.getManifest('grant-1');

    final options = verify(() => dio.get('/storage/shared/manifest',
        options: captureAny(named: 'options'))).captured.single as Options;
    expect(options.headers![shareGrantHeader], 'grant-1');
  });

  // Teeth check: dropping shareGrantHeader from the chunk request must fail
  // this assertion on its own — not on a mock argument-matcher mismatch —
  // so it proves the header is actually sent, not just plumbed somewhere.
  test('downloadChunkBytes sends the grant as X-Share-Grant', () async {
    when(() => dio.get<List<int>>('/storage/shared/chunk/hash1/bytes',
        options: any(named: 'options'))).thenAnswer(
        (_) async => Response(data: <int>[1, 2, 3], statusCode: 200,
            requestOptions: RequestOptions(path: '/storage/shared/chunk/hash1/bytes')));

    final bytes = await ds.downloadChunkBytes('grant-1', 'hash1');

    expect(bytes, Uint8List.fromList([1, 2, 3]));
    final options = verify(() => dio.get<List<int>>('/storage/shared/chunk/hash1/bytes',
        options: captureAny(named: 'options'))).captured.single as Options;
    expect(options.headers![shareGrantHeader], 'grant-1');
  });

  test('downloadFile fetches a grant, verifies chunks, and saves under the grant\'s fileName',
      () async {
    when(() => dio.post('/shares/link/tok123/download-grant', data: any(named: 'data')))
        .thenAnswer((_) async => ok({
              'grant': 'g1',
              'expiresAt': '2026-01-01T00:05:00.000Z',
              'fileId': 'f1',
              'fileName': 'report.pdf',
              'sizeBytes': 3,
              'manifestHash': null,
            }, '/shares/link/tok123/download-grant'));
    when(() => dio.get('/storage/shared/manifest', options: any(named: 'options')))
        .thenAnswer((_) async => ok({
              'totalSize': 3,
              'chunks': [
                {'index': 0, 'hash': _sha256Hex}
              ],
              'manifestHash': null,
            }, '/storage/shared/manifest'));
    when(() => dio.get<List<int>>('/storage/shared/chunk/$_sha256Hex/bytes',
        options: any(named: 'options'))).thenAnswer((_) async => Response(
        data: [1, 2, 3],
        statusCode: 200,
        requestOptions: RequestOptions(path: '/storage/shared/chunk/$_sha256Hex/bytes')));

    String? savedName;
    Uint8List? savedBytes;
    final progress = <double>[];
    await ds.downloadFile('tok123', 'f1', onProgress: progress.add,
        save: (fileName, content) async {
      savedName = fileName;
      final builder = BytesBuilder();
      await for (final chunk in content) {
        builder.add(chunk);
      }
      savedBytes = builder.takeBytes();
    });

    expect(savedName, 'report.pdf');
    expect(savedBytes, Uint8List.fromList([1, 2, 3]));
    expect(progress, [1.0]);
  });
}

// SHA-256 of [1, 2, 3] — computed once via crypto's sha256, not retyped by
// hand, so a transcription slip here can't make the test assert the wrong
// thing.
final _sha256Hex = sha256.convert([1, 2, 3]).toString();

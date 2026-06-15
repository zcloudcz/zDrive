import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/files/data/file_upload_data_source.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late FileUploadDataSource ds;

  Response<dynamic> ok(dynamic data, String path) => Response<dynamic>(
        data: {'success': true, 'data': data, 'error': null},
        statusCode: 200,
        requestOptions: RequestOptions(path: path),
      );

  setUpAll(() => registerFallbackValue(Options()));

  setUp(() {
    dio = MockDio();
    ds = FileUploadDataSource(dio);
  });

  test('initUpload posts fileId/fileName/totalChunks to /storage/upload/init', () async {
    when(() => dio.post(ApiInit, data: any(named: 'data'))).thenAnswer((_) async =>
        ok({'sessionId': 's1', 'sasUploadUrl': 'http://blob/upload'}, ApiInit));

    final session = await ds.initUpload('f1', 'doc.txt', 1);

    expect(session.sessionId, 's1');
    expect(session.sasUploadUrl, 'http://blob/upload');
    verify(() => dio.post(ApiInit,
        data: {'fileId': 'f1', 'fileName': 'doc.txt', 'totalChunks': 1})).called(1);
  });

  test('uploadChunk PUTs raw bytes with the real SHA-256 in X-Chunk-Hash', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    final expectedHash = sha256.convert(bytes).toString();

    when(() => dio.put(
          '/storage/upload/s1/chunk/0',
          data: any(named: 'data'),
          options: any(named: 'options'),
          onSendProgress: any(named: 'onSendProgress'),
        )).thenAnswer((_) async => ok(
        {'sessionId': 's1', 'chunkIndex': 0, 'chunkHash': expectedHash, 'accepted': true},
        '/storage/upload/s1/chunk/0'));

    await ds.uploadChunk('s1', 0, bytes);

    final opts = verify(() => dio.put(
          '/storage/upload/s1/chunk/0',
          data: any(named: 'data'),
          options: captureAny(named: 'options'),
          onSendProgress: any(named: 'onSendProgress'),
        )).captured.single as Options;
    expect(opts.headers!['X-Chunk-Hash'], expectedHash);
    expect(opts.headers!['Content-Type'], 'application/octet-stream');
  });

  test('completeUpload returns manifest hash and size', () async {
    when(() => dio.post('/storage/upload/s1/complete')).thenAnswer((_) async => ok(
        {'blobPath': 't/u/files/f1', 'manifestHash': 'abc123', 'totalSize': 1234},
        '/storage/upload/s1/complete'));

    final result = await ds.completeUpload('s1');

    expect(result.manifestHash, 'abc123');
    expect(result.totalSize, 1234);
  });

  test('getDownloadUrl returns the SAS url from the envelope', () async {
    when(() => dio.get('/storage/download/f1')).thenAnswer((_) async => ok(
        {'sasUrl': 'http://blob/download?sig=x', 'expiresAt': '2026-01-01T00:00:00.000Z'},
        '/storage/download/f1'));

    final url = await ds.getDownloadUrl('f1');

    expect(url, 'http://blob/download?sig=x');
  });
}

const ApiInit = '/storage/upload/init';

import 'dart:convert';
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
    when(() => dio.post(apiInit, data: any(named: 'data'))).thenAnswer((_) async =>
        ok({'sessionId': 's1', 'sasUploadUrl': 'http://blob/upload'}, apiInit));

    final session = await ds.initUpload('f1', 'doc.txt', 1);

    expect(session.sessionId, 's1');
    expect(session.sasUploadUrl, 'http://blob/upload');
    verify(() => dio.post(apiInit,
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

  group('downloadFile (chunk reassembly)', () {
    late MockDio blobDio;

    setUp(() => blobDio = MockDio());

    // The manifest StorageService writes is raw `JsonSerializer.Serialize`
    // output (no naming policy), i.e. PascalCase — see the doc comment on
    // ManifestDto. This mirrors that shape rather than the camelCase
    // envelope the other DTOs get from the ASP.NET controllers.
    String manifestJson(List<Map<String, Object>> chunks, int totalSize) =>
        jsonEncode({'TotalSize': totalSize, 'Chunks': chunks});

    void stubManifest(String fileId, String manifestUrl, String json) {
      when(() => dio.get('/storage/download/$fileId')).thenAnswer((_) async => ok(
          {'sasUrl': manifestUrl, 'expiresAt': '2026-01-01T00:00:00.000Z'},
          '/storage/download/$fileId'));
      when(() => blobDio.get<String>(manifestUrl, options: any(named: 'options')))
          .thenAnswer((_) async => Response<String>(
                data: json,
                statusCode: 200,
                requestOptions: RequestOptions(path: manifestUrl),
              ));
    }

    void stubChunk(String fileId, String hash, String chunkUrl, Uint8List bytes) {
      when(() => dio.get('/storage/download/$fileId/chunk/$hash')).thenAnswer((_) async => ok(
          {'sasUrl': chunkUrl, 'expiresAt': '2026-01-01T00:00:00.000Z'},
          '/storage/download/$fileId/chunk/$hash'));
      when(() => blobDio.get<List<int>>(chunkUrl, options: any(named: 'options')))
          .thenAnswer((_) async => Response<List<int>>(
                data: bytes,
                statusCode: 200,
                requestOptions: RequestOptions(path: chunkUrl),
              ));
    }

    test('reassembles chunks in manifest index order, not array order', () async {
      final chunk0 = Uint8List.fromList([1, 2, 3]);
      final chunk1 = Uint8List.fromList([4, 5, 6]);
      final hash0 = sha256.convert(chunk0).toString();
      final hash1 = sha256.convert(chunk1).toString();

      stubManifest(
        'f1',
        'http://blob/manifest',
        // Listed out of index order on purpose — reassembly must sort by
        // Index, not trust the array's order.
        manifestJson([
          {'Hash': hash1, 'Index': 1},
          {'Hash': hash0, 'Index': 0},
        ], chunk0.length + chunk1.length),
      );
      stubChunk('f1', hash0, 'http://blob/chunk0', chunk0);
      stubChunk('f1', hash1, 'http://blob/chunk1', chunk1);

      final bytes = await ds.downloadFile('f1', blobFetcher: blobDio);

      expect(bytes, Uint8List.fromList([...chunk0, ...chunk1]));
    });

    test('throws ChunkHashMismatchException when a chunk does not match its recorded hash',
        () async {
      final corrupted = Uint8List.fromList([1, 2, 3]);
      const recordedHash = 'not-the-real-hash';

      stubManifest(
        'f1',
        'http://blob/manifest',
        manifestJson([
          {'Hash': recordedHash, 'Index': 0},
        ], corrupted.length),
      );
      stubChunk('f1', recordedHash, 'http://blob/chunk0', corrupted);

      await expectLater(
        ds.downloadFile('f1', blobFetcher: blobDio),
        throwsA(isA<ChunkHashMismatchException>()),
      );
    });

    test('propagates the error when a chunk fetch fails partway through', () async {
      final chunk0 = Uint8List.fromList([1, 2, 3]);
      final hash0 = sha256.convert(chunk0).toString();
      const hash1 = 'chunk-1-hash';

      stubManifest(
        'f1',
        'http://blob/manifest',
        manifestJson([
          {'Hash': hash0, 'Index': 0},
          {'Hash': hash1, 'Index': 1},
        ], chunk0.length + 10),
      );
      stubChunk('f1', hash0, 'http://blob/chunk0', chunk0);
      when(() => dio.get('/storage/download/f1/chunk/$hash1'))
          .thenThrow(Exception('network down'));

      await expectLater(
        ds.downloadFile('f1', blobFetcher: blobDio),
        throwsA(isException),
      );
    });
  });
}

const apiInit = '/storage/upload/init';

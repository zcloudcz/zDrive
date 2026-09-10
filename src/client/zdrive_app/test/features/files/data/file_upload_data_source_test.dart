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

  group('downloadFile (chunk reassembly)', () {
    // Manifest and chunks now come through this app's own API (proxied by
    // StorageService), camelCase like every other controller response — see
    // the doc comment on ManifestDto — not a SAS URL fetched cross-origin.
    void stubManifest(String fileId, List<Map<String, Object>> chunks, int totalSize) {
      when(() => dio.get('/storage/download/$fileId/manifest')).thenAnswer((_) async => ok(
          {'totalSize': totalSize, 'chunks': chunks}, '/storage/download/$fileId/manifest'));
    }

    void stubChunk(String fileId, String hash, Uint8List bytes) {
      when(() => dio.get<List<int>>(
            '/storage/download/$fileId/chunk/$hash/bytes',
            options: any(named: 'options'),
          )).thenAnswer((_) async => Response<List<int>>(
            data: bytes,
            statusCode: 200,
            requestOptions: RequestOptions(path: '/storage/download/$fileId/chunk/$hash/bytes'),
          ));
    }

    test('reassembles chunks in manifest index order, not array order', () async {
      final chunk0 = Uint8List.fromList([1, 2, 3]);
      final chunk1 = Uint8List.fromList([4, 5, 6]);
      final hash0 = sha256.convert(chunk0).toString();
      final hash1 = sha256.convert(chunk1).toString();

      stubManifest(
        'f1',
        // Listed out of index order on purpose — reassembly must sort by
        // index, not trust the array's order.
        [
          {'hash': hash1, 'index': 1},
          {'hash': hash0, 'index': 0},
        ],
        chunk0.length + chunk1.length,
      );
      stubChunk('f1', hash0, chunk0);
      stubChunk('f1', hash1, chunk1);

      final bytes = await ds.downloadFile('f1');

      expect(bytes, Uint8List.fromList([...chunk0, ...chunk1]));

      // Teeth on the request shape, not just the outcome: dropping
      // ResponseType.bytes would silently hand back a decoded string instead
      // of raw chunk bytes.
      final opts = verify(() => dio.get<List<int>>(
            '/storage/download/f1/chunk/$hash0/bytes',
            options: captureAny(named: 'options'),
          )).captured.single as Options;
      expect(opts.responseType, ResponseType.bytes);
    });

    test('throws ChunkHashMismatchException when a chunk does not match its recorded hash',
        () async {
      final corrupted = Uint8List.fromList([1, 2, 3]);
      const recordedHash = 'not-the-real-hash';

      stubManifest('f1', [
        {'hash': recordedHash, 'index': 0},
      ], corrupted.length);
      stubChunk('f1', recordedHash, corrupted);

      await expectLater(
        ds.downloadFile('f1'),
        throwsA(isA<ChunkHashMismatchException>()),
      );
    });

    test('propagates the error when a chunk fetch fails partway through', () async {
      final chunk0 = Uint8List.fromList([1, 2, 3]);
      final hash0 = sha256.convert(chunk0).toString();
      const hash1 = 'chunk-1-hash';

      stubManifest('f1', [
        {'hash': hash0, 'index': 0},
        {'hash': hash1, 'index': 1},
      ], chunk0.length + 10);
      stubChunk('f1', hash0, chunk0);
      when(() => dio.get<List<int>>(
            '/storage/download/f1/chunk/$hash1/bytes',
            options: any(named: 'options'),
          )).thenThrow(Exception('network down'));

      await expectLater(
        ds.downloadFile('f1'),
        throwsA(isException),
      );
    });

    test('throws ManifestSizeMismatchException when the assembled length does not match TotalSize',
        () async {
      // A chunk missing server-side: the manifest still claims the original
      // total, but only one chunk's worth of bytes actually comes back. Each
      // chunk individually hashes correctly, so only a length check catches
      // this — this is the regression test for that check.
      final chunk0 = Uint8List.fromList([1, 2, 3]);
      final hash0 = sha256.convert(chunk0).toString();

      stubManifest('f1', [
        {'hash': hash0, 'index': 0},
      ], chunk0.length + 10);
      stubChunk('f1', hash0, chunk0);

      await expectLater(
        ds.downloadFile('f1'),
        throwsA(isA<ManifestSizeMismatchException>()),
      );
    });

    test('throws ManifestChunkIndexException when the manifest repeats an index',
        () async {
      // The counterexample the length check cannot see. Chunks are a fixed
      // size, so a manifest listing index 0 twice assembles to chunk0||chunk0
      // at exactly the total a correct two-chunk file would have, and both
      // copies hash correctly. Only the index check catches it — silent
      // corruption otherwise, since the file would save and look plausible.
      final chunk0 = Uint8List.fromList([1, 2, 3]);
      final hash0 = sha256.convert(chunk0).toString();

      stubManifest('f1', [
        {'hash': hash0, 'index': 0},
        {'hash': hash0, 'index': 0},
      ], chunk0.length * 2);
      stubChunk('f1', hash0, chunk0);

      await expectLater(
        ds.downloadFile('f1'),
        throwsA(isA<ManifestChunkIndexException>()),
      );
    });
  });
}

const apiInit = '/storage/upload/init';

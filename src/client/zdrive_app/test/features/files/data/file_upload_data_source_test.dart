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

  for (final echo in <String?>[null, 'b' * 64]) {
    test('DownloadStream_MissingOrWrongSnapshotEcho($echo)_RejectsBeforeChunks', () async {
      final hash = 'a' * 64;
      when(() => dio.get('/storage/download/f1/manifest',
        queryParameters: {'manifestHash': hash},
      )).thenAnswer((_) async => ok({
        'manifestHash': echo, 'totalSize': 3,
        'chunks': [{'index': 0, 'hash': 'chunk-hash'}],
      }, 'manifest'));

      await expectLater(ds.downloadFileStream('f1', manifestHash: hash), emitsError(isStateError));
      verifyNever(() => dio.get<List<int>>(any(), options: any(named: 'options')));
    });
  }

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

  group('uploadFile (multi-chunk upload)', () {
    // Session/chunk-PUT/complete stubs generic enough to serve any of the
    // sizes/streams below — these tests care about totalChunks and the
    // byte-count check, not about individual chunk paths.
    void stubUploadSession() {
      when(() => dio.post(apiInit, data: any(named: 'data'))).thenAnswer(
          (_) async => ok({'sessionId': 's1', 'sasUploadUrl': 'x'}, apiInit));
      when(() => dio.put(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
            onSendProgress: any(named: 'onSendProgress'),
          )).thenAnswer((_) async => ok(
          {'sessionId': 's1', 'chunkIndex': 0, 'chunkHash': 'h', 'accepted': true}, ''));
      when(() => dio.post('/storage/upload/s1/complete')).thenAnswer((_) async =>
          ok({'blobPath': 'p', 'manifestHash': 'h1', 'totalSize': 0}, ''));
    }

    test('derives totalChunks from sizeBytes instead of hard-coding 1, when '
        'the stream actually produces that many bytes', () async {
      stubUploadSession();
      const chunkSize = FileUploadDataSource.chunkSize;

      for (final size in [0, chunkSize, chunkSize + 1, chunkSize * 3]) {
        await ds.uploadFile('f1', 'x.bin', Stream.value(Uint8List(size)), size);
      }

      final totalChunksSent = verify(
        () => dio.post(apiInit, data: captureAny(named: 'data')),
      ).captured.map((data) => (data as Map)['totalChunks']).toList();

      expect(totalChunksSent, [1, 1, 2, 3]);
    });

    test('UploadFile_AcknowledgedChunks_ReportsProgressWithoutTransportEvents', () async {
      stubUploadSession();
      final progress = <double>[];
      const size = FileUploadDataSource.chunkSize + 1;

      await ds.uploadFile('f1', 'x.bin', Stream.value(Uint8List(size)), size,
          onProgress: progress.add);

      expect(progress, [FileUploadDataSource.chunkSize / size, 1.0]);
    });

    test('UploadFile_FailedChunk_DoesNotCompleteOrReportAcknowledgement', () async {
      stubUploadSession();
      when(() => dio.put(any(), data: any(named: 'data'),
          options: any(named: 'options'),
          onSendProgress: any(named: 'onSendProgress')))
          .thenThrow(StateError('upload failed'));
      final progress = <double>[];

      await expectLater(ds.uploadFile('f1', 'x.bin',
          Stream.value(Uint8List.fromList([1, 2, 3])), 3,
          onProgress: progress.add), throwsStateError);

      expect(progress, isEmpty);
      verifyNever(() => dio.post('/storage/upload/s1/complete'));
    });

    test(
        'throws UploadSizeMismatchException when the stream produces fewer '
        'bytes than sizeBytes declared, even though the chunk count still '
        'comes out to 1 either way (round-3 review finding 2 — this used to '
        'be exactly the input the old "derives totalChunks" test fed in and '
        'expected to succeed)', () async {
      stubUploadSession();

      await expectLater(
        ds.uploadFile('f1', 'x.bin', const Stream<List<int>>.empty(),
            FileUploadDataSource.chunkSize),
        throwsA(isA<UploadSizeMismatchException>()),
      );

      verifyNever(() => dio.post('/storage/upload/s1/complete'));
    });

    test(
        'throws UploadSizeMismatchException when the stream is short by a '
        'few bytes but still produces the same chunk count as declared — '
        'the input that distinguishes a byte-count check from a chunk-count '
        'check (round-3 review finding 2)', () async {
      stubUploadSession();
      const chunkSize = FileUploadDataSource.chunkSize;
      final shortContent = Uint8List(chunkSize - 100);

      await expectLater(
        ds.uploadFile('f1', 'x.bin', Stream.value(shortContent), chunkSize),
        throwsA(isA<UploadSizeMismatchException>()),
      );

      verifyNever(() => dio.post('/storage/upload/s1/complete'));
    });

    test('a multi-chunk upload round-trips through downloadFile', () async {
      // Three chunks from uneven source pieces, including an oversized piece — big
      // enough that a hard-coded single-chunk upload (the old behaviour)
      // would silently drop everything past the first ChunkSize bytes.
      final content = Uint8List.fromList(
          List.generate(FileUploadDataSource.chunkSize * 2 + 10, (i) => i % 256));

      when(() => dio.post(apiInit, data: any(named: 'data'))).thenAnswer(
          (_) async => ok({'sessionId': 's1', 'sasUploadUrl': 'x'}, apiInit));

      final uploadedChunks = <int, Uint8List>{};
      for (final index in [0, 1, 2]) {
        when(() => dio.put(
              '/storage/upload/s1/chunk/$index',
              data: any(named: 'data'),
              options: any(named: 'options'),
              onSendProgress: any(named: 'onSendProgress'),
            )).thenAnswer((invocation) async {
          final stream = invocation.namedArguments[#data] as Stream<List<int>>;
          final bytes = Uint8List.fromList((await stream.toList()).expand((e) => e).toList());
          final options = invocation.namedArguments[#options] as Options;
          expect(options.headers!['X-Chunk-Hash'], sha256.convert(bytes).toString());
          uploadedChunks[index] = bytes;
          return ok({'sessionId': 's1', 'chunkIndex': index, 'chunkHash': 'h', 'accepted': true},
              '/storage/upload/s1/chunk/$index');
        });
      }

      when(() => dio.post('/storage/upload/s1/complete')).thenAnswer((_) async =>
          ok({'blobPath': 'p', 'manifestHash': 'h1', 'totalSize': content.length}, ''));

      final complete = await ds.uploadFile('f1', 'big.bin', Stream.fromIterable([
        Uint8List.sublistView(content, 0, 3),
        Uint8List.sublistView(content, 3),
      ]), content.length);

      expect(complete.totalSize, content.length);
      expect(uploadedChunks.keys.toList(), [0, 1, 2]);
      expect(uploadedChunks[0]!.length, FileUploadDataSource.chunkSize);
      expect(uploadedChunks[1]!.length, FileUploadDataSource.chunkSize);
      expect(uploadedChunks[2]!.length, 10);
      expect([...uploadedChunks[0]!, ...uploadedChunks[1]!, ...uploadedChunks[2]!], content);

      // Now serve those same chunks back through the manifest/download
      // endpoints downloadFile already exercises (see the group below), and
      // check the round trip reproduces the exact original bytes.
      when(() => dio.get('/storage/download/f1/manifest')).thenAnswer((_) async => ok({
            'totalSize': content.length,
            'chunks': [
              for (final entry in uploadedChunks.entries)
                {'hash': sha256.convert(entry.value).toString(), 'index': entry.key},
            ],
          }, '/storage/download/f1/manifest'));
      for (final entry in uploadedChunks.entries) {
        final hash = sha256.convert(entry.value).toString();
        when(() => dio.get<List<int>>(
              '/storage/download/f1/chunk/$hash/bytes',
              options: any(named: 'options'),
            )).thenAnswer((_) async => Response<List<int>>(
              data: entry.value,
              statusCode: 200,
              requestOptions:
                  RequestOptions(path: '/storage/download/f1/chunk/$hash/bytes'),
            ));
      }

      final downloaded = await ds.downloadFile('f1');
      expect(downloaded, content);
    });
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

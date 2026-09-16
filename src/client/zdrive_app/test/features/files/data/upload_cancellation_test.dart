import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/core/network/dio_client.dart';
import 'package:zdrive_app/features/files/data/file_upload_data_source.dart';

class BlockingChunkAdapter implements HttpClientAdapter {
  final chunkStarted = Completer<void>();
  final adapterCancelled = Completer<void>();
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    paths.add(options.path);
    if (options.method == 'DELETE') {
      expect(options.cancelToken!.isCancelled, isFalse);
      return ResponseBody.fromString('', 200);
    }
    if (options.path.endsWith('/init')) {
      return ResponseBody.fromString(
        '{"success":true,"data":{"sessionId":"s1","sasUploadUrl":"unused"}}',
        200, headers: {Headers.contentTypeHeader: ['application/json']});
    }
    if (requestStream != null) await requestStream.drain<void>();
    chunkStarted.complete();
    await cancelFuture;
    adapterCancelled.complete();
    throw options.cancelToken!.cancelError!;
  }

  @override
  void close({bool force = false}) {}
}

class ObservableErrorHandler extends ErrorInterceptorHandler {
  Future<dynamic> get completion => future;
}

void main() {
  test('UploadFile_CancelActiveChunk_AbortsAdapterWithoutCompleting', () async {
    final adapter = BlockingChunkAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(RetryInterceptor(dio: dio));
    addTearDown(dio.close);
    final token = CancelToken();
    final upload = FileUploadDataSource(dio).uploadFile(
      'f1', 'big.bin', Stream.value([1, 2, 3]), 3, cancelToken: token);
    final assertion = expectLater(upload, throwsA(isA<DioException>()
      .having((e) => e.type, 'type', DioExceptionType.cancel)));
    await adapter.chunkStarted.future.timeout(const Duration(seconds: 5));
    token.cancel('file removed');
    await assertion.timeout(const Duration(seconds: 1));
    await adapter.adapterCancelled.future.timeout(const Duration(seconds: 1));
    expect(adapter.paths, ['/storage/upload/init', '/storage/upload/s1/chunk/0', '/storage/upload/s1']);
  });

  test('Retry_CancelDuringRetryAfter_ReleasesWaitWithoutRetry', () async {
    final adapter = BlockingChunkAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    final retry = RetryInterceptor(dio: dio);
    final token = CancelToken();
    final options = RequestOptions(path: '/chunk', cancelToken: token);
    final handler = ObservableErrorHandler();
    final handled = expectLater(handler.completion, throwsA(anything));
    final pending = retry.onError(
      DioException(requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: options, statusCode: 429,
          headers: Headers.fromMap({'retry-after': ['60']}))),
      handler,
    );
    await Future<void>.delayed(Duration.zero);
    token.cancel('file removed');
    // Await the interceptor itself: Dio also races cancellation externally,
    // which alone would hide a sleeping interceptor and a leaked timer.
    await pending.timeout(const Duration(seconds: 1));
    await handled;
    expect(adapter.paths, isEmpty);
    expect(options.extra['retryCount'], isNull);
  });
}

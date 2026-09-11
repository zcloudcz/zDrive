import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/core/network/dio_client.dart';

class _ScriptedResponse {
  const _ScriptedResponse(this.statusCode, {this.headers = const {}});

  final int statusCode;
  final Map<String, List<String>> headers;
}

/// Replays a fixed script of responses for every request, in order, so
/// tests can assert exactly how many times RetryInterceptor re-issues a
/// request without hitting the network.
///
/// Unlike a bodyless GET, the real chunk upload (file_upload_data_source.dart
/// `uploadChunk`) PUTs a `Stream.fromIterable` body — draining [requestStream]
/// here on every call is what makes a retry meaningful to assert on: if
/// re-listening the request's body stream on retry ever broke (see the
/// review's note that `Stream.fromIterable` is multi-subscription in Dart
/// 3.11), a later call here would read an empty/short stream instead of
/// throwing outright, which is exactly why the byte count is recorded rather
/// than merely "did fetch get called again".
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.responses);

  final List<_ScriptedResponse> responses;
  int callCount = 0;
  final List<int> requestBodyLengths = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    var length = 0;
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        length += chunk.length;
      }
    }
    requestBodyLengths.add(length);

    final scripted = responses[callCount];
    callCount++;
    return ResponseBody.fromString('', scripted.statusCode, headers: scripted.headers);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('RetryInterceptor', () {
    late Dio dio;
    late _ScriptedAdapter adapter;

    Dio buildDio(List<_ScriptedResponse> responses) {
      adapter = _ScriptedAdapter(responses);
      dio = Dio()..httpClientAdapter = adapter;
      dio.interceptors.add(RetryInterceptor(dio: dio, maxRetries: 3));
      return dio;
    }

    Future<Response<String>> putChunk() {
      return dio.put<String>(
        '/storage/upload/x/chunk/0',
        data: Stream.fromIterable([
          Uint8List.fromList([1, 2, 3, 4]),
        ]),
        options: Options(
          contentType: 'application/octet-stream',
          headers: {Headers.contentLengthHeader: 4},
          validateStatus: (code) => code == 200,
        ),
      );
    }

    test('onError_TooManyRequests_RetriesUntilSuccess', () async {
      buildDio([
        _ScriptedResponse(429),
        _ScriptedResponse(429),
        _ScriptedResponse(200),
      ]);

      final response = await putChunk();

      expect(response.statusCode, 200);
      expect(adapter.callCount, 3, reason: 'two 429s, then the successful retry');
      // Every attempt sent the full chunk body — a broken multi-subscription
      // re-listen would show up here as a shorter (or zero) later length.
      expect(adapter.requestBodyLengths, [4, 4, 4]);
    });

    test('onError_TooManyRequests_HonoursRetryAfterInsteadOfExponentialBackoff', () async {
      // The gateway's fixed window (dio_client.dart's comment: up to 60s) is
      // longer than any hand-tuned exponential schedule can safely assume,
      // so a 429 with a Retry-After header must wait that long, not the
      // interceptor's own 200/400/800ms schedule.
      buildDio([
        _ScriptedResponse(429, headers: {
          'retry-after': ['2'],
        }),
        _ScriptedResponse(200),
      ]);

      final stopwatch = Stopwatch()..start();
      final response = await putChunk();
      stopwatch.stop();

      expect(response.statusCode, 200);
      expect(
        stopwatch.elapsed,
        greaterThanOrEqualTo(const Duration(seconds: 2)),
        reason: 'must wait the full Retry-After, not the 200ms exponential backoff',
      );
    });

    test('onError_ServerError_StillRetries', () async {
      buildDio([_ScriptedResponse(503), _ScriptedResponse(200)]);

      final response = await putChunk();

      expect(response.statusCode, 200);
      expect(adapter.callCount, 2);
    });

    test('onError_TooManyRequests_GivesUpAfterMaxRetries', () async {
      buildDio(List.generate(5, (_) => const _ScriptedResponse(429)));

      await expectLater(putChunk(), throwsA(isA<DioException>()));
      // Initial attempt + 3 retries = 4 calls, then it gives up.
      expect(adapter.callCount, 4);
    });

    test('onError_ClientError_IsNotRetried', () async {
      buildDio([_ScriptedResponse(400)]);

      await expectLater(putChunk(), throwsA(isA<DioException>()));
      expect(adapter.callCount, 1, reason: '400 is not 429 or >=500, so no retry');
    });

    test(
        'retryAfterDelay_HeaderAboveTheCeiling_IsClampedInsteadOfHonouredAsIs',
        () {
      // Nothing between the app and the gateway (ingress, a WAF, a CDN — or
      // our own middleware misconfigured) is trusted to send a sane
      // Retry-After. Checked directly against the pure function rather than
      // by actually waiting the delay out: the production ceiling is 120s,
      // and a test that really awaited that (let alone an unclamped 86400s)
      // would be useless as a fast regression check.
      final interceptor = RetryInterceptor(dio: Dio());
      final response = Response<void>(
        requestOptions: RequestOptions(path: '/x'),
        headers: Headers.fromMap({
          'retry-after': ['86400'], // a full day
        }),
      );

      expect(
        interceptor.retryAfterDelay(response),
        const Duration(seconds: 120),
        reason: 'a hostile or misconfigured Retry-After must not be honoured as-is',
      );
    });

    test('retryAfterDelay_HeaderUnderTheCeiling_IsHonouredAsIs', () {
      final interceptor = RetryInterceptor(dio: Dio());
      final response = Response<void>(
        requestOptions: RequestOptions(path: '/x'),
        headers: Headers.fromMap({
          'retry-after': ['5'],
        }),
      );

      expect(interceptor.retryAfterDelay(response), const Duration(seconds: 5));
    });
  });
}

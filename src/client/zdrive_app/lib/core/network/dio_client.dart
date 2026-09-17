import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import '../diagnostics/diagnostics.dart';
import '../diagnostics/network_diagnostics.dart';
import 'api_constants.dart';
import 'auth_interceptor.dart';

@module
abstract class NetworkModule {
  @lazySingleton
  Dio dio(AuthInterceptor authInterceptor) {
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    dio.interceptors.add(NetworkDiagnostics());
    dio.interceptors.add(authInterceptor);

    dio.interceptors.add(RetryInterceptor(dio: dio));

    return dio;
  }
}

class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;

  // A cap on how long a Retry-After header can pause a request. Nothing
  // between here and the gateway is trusted to send a sane value — a
  // misconfigured or hostile 429 from ingress/a WAF/a CDN could otherwise
  // park an upload for as long as it likes, with no cancel path and no
  // receiveTimeout (that only covers time waiting on a response, not the
  // delay between requests). 120s is 2x the gateway's 1-minute fixed window,
  // so it never cuts off a legitimate wait.
  static const _maxRetryAfter = Duration(seconds: 120);

  RetryInterceptor({required this.dio, this.maxRetries = 3});

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final cancelToken = err.requestOptions.cancelToken;
    if (err.type == DioExceptionType.cancel ||
        (cancelToken?.isCancelled ?? false)) {
      return handler.next(cancelToken?.cancelError ?? err);
    }
    final statusCode = err.response?.statusCode;
    // 429 is retried alongside 5xx: the gateway's rate limiter now rejects
    // per authenticated user rather than globally (see ApiGateway/Program.cs),
    // but a single large chunked upload can still legitimately outrun its own
    // per-minute budget. The rejection happens in gateway middleware before
    // the request reaches any service handler, so — unlike a 5xx, which might
    // have partially executed — retrying it can never double-apply a write.
    if (statusCode != null && (statusCode >= 500 || statusCode == 429)) {
      final extra = err.requestOptions.extra;
      final retryCount = (extra['retryCount'] as int?) ?? 0;

      if (retryCount < maxRetries) {
        // For a 429, the gateway names the exact wait via Retry-After (its
        // fixed window, e.g. 60s, is longer than any fixed backoff schedule
        // could safely assume) — honour it instead of guessing. Fall back to
        // the exponential schedule for a 429 with no header, and use it
        // unconditionally for 5xx.
        final delay = statusCode == 429
            ? retryAfterDelay(err.response) ??
                  Duration(milliseconds: 200 * (1 << retryCount))
            : Duration(milliseconds: 200 * (1 << retryCount));
        Diagnostics.event('http.retry', {
          'requestId': extra['_diagnosticId'],
          'retry': retryCount + 1,
          'delayMs': delay.inMilliseconds,
        });
        final waiting = Completer<void>();
        final timer = Timer(delay, waiting.complete);
        try {
          await Future.any<void>([
            waiting.future,
            if (cancelToken != null) cancelToken.whenCancel.then((_) {}),
          ]);
        } finally {
          timer.cancel();
        }
        if (cancelToken?.isCancelled ?? false) {
          return handler.next(cancelToken!.cancelError!);
        }

        err.requestOptions.extra['retryCount'] = retryCount + 1;
        try {
          final response = await dio.fetch(err.requestOptions);
          return handler.resolve(response);
        } on DioException catch (e) {
          return handler.next(e);
        }
      }
    }
    return handler.next(err);
  }

  // Not private so the ceiling can be asserted directly without waiting out
  // a real 120s delay in a test.
  @visibleForTesting
  Duration? retryAfterDelay(Response<dynamic>? response) {
    final header = response?.headers.value('retry-after');
    if (header == null) return null;
    final seconds = int.tryParse(header);
    if (seconds == null) return null;
    final delay = Duration(seconds: seconds);
    return delay > _maxRetryAfter ? _maxRetryAfter : delay;
  }
}

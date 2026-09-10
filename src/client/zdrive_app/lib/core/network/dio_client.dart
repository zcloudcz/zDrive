import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

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

    dio.interceptors.add(authInterceptor);

    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(requestBody: true, responseBody: true),
      );
    }

    dio.interceptors.add(RetryInterceptor(dio: dio));

    return dio;
  }
}

class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;

  RetryInterceptor({required this.dio, this.maxRetries = 3});

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
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
        final delay = Duration(milliseconds: 200 * (1 << retryCount));
        await Future<void>.delayed(delay);

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
}

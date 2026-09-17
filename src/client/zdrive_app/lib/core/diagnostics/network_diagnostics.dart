import 'package:dio/dio.dart';
import 'diagnostics.dart';

/// Route categories are fixed literals; never log a URL, query, header or body.
String diagnosticRoute(String path) {
  final segments = Uri.tryParse(path)?.pathSegments ?? const <String>[];
  const allowed = {
    'auth',
    'files',
    'folders',
    'storage',
    'sync',
    'photos',
    'albums',
    'notifications',
    'sharing',
    'devices',
    'users',
    'tenants',
  };
  for (final segment in segments.take(3)) {
    if (allowed.contains(segment)) return segment;
  }
  return 'other';
}

class NetworkDiagnostics extends Interceptor {
  static int _nextId = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['_diagnosticId'] = ++_nextId;
    options.extra['_diagnosticClock'] = Stopwatch()..start();
    const methods = {
      'GET',
      'POST',
      'PUT',
      'PATCH',
      'DELETE',
      'HEAD',
      'OPTIONS',
    };
    final method = methods.contains(options.method) ? options.method : 'OTHER';
    Diagnostics.event('http.start.$method.${diagnosticRoute(options.path)}', {
      'requestId': _nextId,
      'retry': options.extra['retryCount'] ?? 0,
    });
    handler.next(options);
  }

  void _finish(RequestOptions options, int? status, bool cancelled) {
    Diagnostics.event('http.finish', {
      'requestId': options.extra['_diagnosticId'],
      'durationMs': (options.extra['_diagnosticClock'] as Stopwatch?)
          ?.elapsedMilliseconds,
      'status': status,
      'cancelled': cancelled,
      'retry': options.extra['retryCount'] ?? 0,
    });
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _finish(response.requestOptions, response.statusCode, false);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _finish(
      err.requestOptions,
      err.response?.statusCode,
      CancelToken.isCancel(err),
    );
    Diagnostics.error('http.error', err);
    handler.next(err);
  }
}

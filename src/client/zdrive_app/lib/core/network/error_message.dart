import 'package:dio/dio.dart';

/// Turns a caught error into text safe to show a user. `DioException.toString()`
/// dumps internal plumbing (status code, `RequestOptions`, `validateStatus`)
/// that means nothing outside this codebase — a dependency returning 502
/// (PhotoService/NotificationService are not deployed at MVP scope and the
/// gateway still proxies to them) must not surface as that dump.
///
/// Any other exception type is left as `toString()`, matching how the rest
/// of the app already surfaces errors (e.g. `file_browser_bloc.dart`) — this
/// only narrows the one case that reads as an internal-plumbing leak.
String describeError(Object error) {
  if (error is DioException) {
    final statusCode = error.response?.statusCode;
    if (statusCode != null && statusCode >= 500) {
      return 'This feature is temporarily unavailable. Please try again later.';
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Could not reach the server. Check your connection and try again.';
    }
  }
  return error.toString();
}

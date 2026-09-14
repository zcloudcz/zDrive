import 'package:dio/dio.dart';

import '../../shared/l10n/app_localizations.dart';

/// Turns a caught error into text safe to show a user. `DioException.toString()`
/// dumps internal plumbing (status code, `RequestOptions`, `validateStatus`)
/// that means nothing outside this codebase — a dependency returning 502
/// (PhotoService/NotificationService are not deployed at MVP scope and the
/// gateway still proxies to them) must not surface as that dump.
///
/// Takes [AppLocalizations] rather than returning English prose: this app is
/// fully localized, so a hardcoded sentence here would be the only English
/// string a Czech user sees. Call it from the widget that renders the error,
/// not from a bloc — blocs carry the error object, pages turn it into text.
///
/// EVERY `DioException` is mapped, not just 5xx and timeouts: anything left
/// falling through to `toString()` is exactly the leak this function exists to
/// stop, and a 4xx from a service the user cannot influence reads no better
/// than a 502. Other exception types keep `toString()`, matching how the rest
/// of the app surfaces errors.
String describeError(Object error, AppLocalizations l10n) {
  if (error is DioException) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return l10n.errorNoConnection;
    }
    final statusCode = error.response?.statusCode;
    if (statusCode != null && statusCode >= 500) {
      return l10n.errorServiceUnavailable;
    }
    return l10n.errorRequestFailed;
  }
  return error.toString();
}

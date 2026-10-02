import 'package:dio/dio.dart';

import '../../shared/l10n/app_localizations.dart';

/// Turns a caught error into text safe to show a user. `DioException.toString()`
/// dumps internal plumbing (status code, `RequestOptions`, `validateStatus`)
/// that means nothing outside this codebase. Server and runtime errors may
/// also contain internal details, so unknown errors use a localized fallback.
///
/// Takes [AppLocalizations] rather than returning English prose: this app is
/// fully localized, so a hardcoded sentence here would be the only English
/// string a Czech user sees. Call it from the widget that renders the error,
/// not from a bloc — blocs carry the error object, pages turn it into text.
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
  return l10n.errorRequestFailed;
}

/// Same contract as [describeError], but for the auth endpoints
/// (`/auth/login`, `/auth/register`, `/auth/entra`) — their status codes
/// mean something more specific than "request failed", and the backend's
/// own message text (may contain emails or other internal detail; see
/// `ExceptionHandlingMiddleware`) must never reach the user directly.
/// Falls back to [describeError] for anything not covered below.
String describeAuthError(Object error, AppLocalizations l10n) {
  if (error is DioException) {
    final statusCode = error.response?.statusCode;
    if (statusCode == 429) {
      return l10n.authTooManyAttempts;
    }
    final path = error.requestOptions.path;
    if (path == '/auth/login' && (statusCode == 404 || statusCode == 401)) {
      return l10n.authInvalidCredentials;
    }
    if (path == '/auth/login/2fa' && statusCode == 400) {
      // The backend answers 400 for both a wrong code and a challenge that is
      // unknown / expired / used up; the second cannot be fixed by retyping.
      return _hasValidationError(error, 'challengeToken')
          ? l10n.authTwoFactorChallengeExpired
          : l10n.authTwoFactorInvalidCode;
    }
    if (path == '/users/me/2fa/confirm' && statusCode == 400) {
      return l10n.authTwoFactorInvalidCode;
    }
    if (path == '/users/me/2fa/setup' && statusCode == 400) {
      return l10n.twoFactorPasswordInvalid;
    }
    if (path == '/users/me/2fa/disable' && statusCode == 400) {
      // One answer for a wrong password, a wrong code and a refused attempt:
      // the server deliberately does not say which.
      return l10n.twoFactorInvalidPasswordOrCode;
    }
    if (path == '/auth/register' && statusCode == 409) {
      return l10n.authEmailAlreadyRegistered;
    }
    if (path == '/auth/entra') {
      switch (statusCode) {
        case 409:
          return l10n.authEntraAccountExists;
        case 403:
          return l10n.authEntraVerificationFailed;
        case 404:
          return l10n.authEntraUnavailable;
      }
    }
  }
  return describeError(error, l10n);
}

/// True when a 400 from `ExceptionHandlingMiddleware` carries a validation
/// error for [field] (`error.validationErrors` is keyed by property name).
bool _hasValidationError(DioException error, String field) {
  final body = error.response?.data;
  if (body is! Map) return false;
  final errors = (body['error'] as Map?)?['validationErrors'];
  return errors is Map && errors.containsKey(field);
}

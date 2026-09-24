import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:injectable/injectable.dart';

import '../auth/entra_token_exchange.dart';
import '../auth/token_storage.dart';
import 'api_constants.dart';

@lazySingleton
class AuthInterceptor extends Interceptor {
  final TokenStorage _tokenStorage;
  bool _isRefreshing = false;

  // Not constructor-injected: EntraTokenExchange isn't itself a registered
  // DI dependency (it's a plain Dio wrapper other Entra call sites also
  // build ad hoc — see entra_callback_page.dart). Settable so a test can
  // swap in a fake without pulling that through the injectable graph.
  @visibleForTesting
  EntraTokenExchange entraTokenExchange = EntraTokenExchange();

  AuthInterceptor(this._tokenStorage);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokenStorage.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refreshToken = await _tokenStorage.refreshToken;
        if (refreshToken == null) {
          _isRefreshing = false;
          return handler.next(err);
        }

        final dio = Dio(
          BaseOptions(baseUrl: ApiConstants.baseUrl),
        );
        Map<String, dynamic> tokens;
        try {
          final response = await dio.post(
            ApiConstants.authRefresh,
            data: {'refreshToken': refreshToken},
          );
          // Refresh runs on a bare Dio (no envelope interceptor) to avoid
          // recursion, so unwrap the { success, data } envelope by hand.
          final envelope = response.data as Map<String, dynamic>;
          tokens = envelope['data'] as Map<String, dynamic>;
        } on DioException {
          // The zDrive refresh token's 24h absolute cap on an Entra-derived
          // session (ADR 0003) is the expected reason this fails on native.
          // One silent Entra-side renewal attempt before giving up; rethrows
          // (StateError on web / no stored token, or any Entra-side
          // failure) fall straight through to the outer catch below, which
          // clears storage and logs out exactly as before this existed.
          tokens = await _renewViaEntra(dio);
        }
        final newAccess = tokens['accessToken'] as String;
        final newRefresh = tokens['refreshToken'] as String;
        await _tokenStorage.saveTokens(
          accessToken: newAccess,
          refreshToken: newRefresh,
        );

        err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
        final retryResponse = await dio.fetch(err.requestOptions);
        _isRefreshing = false;
        return handler.resolve(retryResponse);
      } catch (_) {
        _isRefreshing = false;
        await _tokenStorage.clear();
      }
    }
    return handler.next(err);
  }

  /// Silent renewal (ADR 0003, native only): redeem the stored Entra
  /// refresh token at Entra's own token endpoint, then re-run `/auth/entra`
  /// with the new access token to get a fresh zDrive session. Throws to let
  /// the caller fall through to the normal logout path when there is no
  /// Entra refresh token (web, or a password-login session), or when Entra
  /// itself refuses the token (revoked/expired identity) — that failure
  /// must surface as a normal logout, not be swallowed here.
  Future<Map<String, dynamic>> _renewViaEntra(Dio dio) async {
    if (kIsWeb) {
      throw StateError('no Entra refresh token on web');
    }
    final entraRefreshToken = await _tokenStorage.entraRefreshToken;
    if (entraRefreshToken == null) {
      throw StateError('no stored Entra refresh token');
    }

    final entraResult = await entraTokenExchange.refreshNativeTokens(
      refreshToken: entraRefreshToken,
    );
    if (entraResult.refreshToken != null) {
      // Entra rotates refresh tokens; persist the new one so the NEXT
      // silent renewal doesn't replay an already-consumed token.
      await _tokenStorage.saveEntraRefreshToken(entraResult.refreshToken!);
    }

    final response = await dio.post(
      ApiConstants.authEntraExchange,
      data: {'accessToken': entraResult.accessToken},
    );
    final envelope = response.data as Map<String, dynamic>;
    return envelope['data'] as Map<String, dynamic>;
  }
}

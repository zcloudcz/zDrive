import 'package:dio/dio.dart';

import 'entra_config.dart';

/// Thrown when Entra's token endpoint returns a 200 with no usable
/// access_token — distinguished from [DioException] (network/4xx/5xx),
/// which the caller handles with the app's normal [describeError].
class EntraTokenExchangeException implements Exception {
  const EntraTokenExchangeException(this.message);
  final String message;

  @override
  String toString() => 'EntraTokenExchangeException: $message';
}

/// The pair a native (ADR 0003) token or refresh response yields — web's
/// `exchangeCodeForAccessToken` only ever needs the access token, so it
/// keeps returning a bare `String` and this type is native-only.
class EntraTokenResult {
  const EntraTokenResult({required this.accessToken, this.refreshToken});
  final String accessToken;
  final String? refreshToken;
}

/// Exchanges an Entra authorization code (or refresh token) for tokens. A
/// plain [Dio] instance, not the app's shared one: that one is bound to the
/// zDrive API gateway's base URL and auth interceptor, neither of which
/// applies to a call against Entra's own token endpoint.
class EntraTokenExchange {
  EntraTokenExchange({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<String> exchangeCodeForAccessToken({
    required String code,
    required String codeVerifier,
  }) async {
    final result = await _requestTokens({
      'grant_type': 'authorization_code',
      'client_id': kEntraClientId,
      'code': code,
      'redirect_uri': entraRedirectUri(),
      'code_verifier': codeVerifier,
      'scope': kEntraApiScope.isEmpty ? 'openid' : 'openid $kEntraApiScope',
    });
    return result.accessToken;
  }

  /// Native variant (ADR 0003): [redirectUri] differs per platform (see
  /// `entra_config.dart`) and the scope always includes `offline_access`,
  /// so the response — and this method's return value — also carries the
  /// refresh token native clients store for silent renewal. Web never
  /// requests `offline_access` (no secure storage in a browser to hold a
  /// long-lived credential), so it keeps using the method above.
  Future<EntraTokenResult> exchangeCodeForNativeTokens({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) {
    return _requestTokens({
      'grant_type': 'authorization_code',
      'client_id': kEntraClientId,
      'code': code,
      'redirect_uri': redirectUri,
      'code_verifier': codeVerifier,
      'scope': _nativeScope,
    });
  }

  /// Redeems a stored Entra refresh token for a new access token (silent
  /// renewal — `auth_interceptor.dart`, ADR 0003 step 5). Entra rotates
  /// refresh tokens; the caller must persist a non-null
  /// [EntraTokenResult.refreshToken] from the result, and treat any failure
  /// (revoked/expired identity) as "silent renewal failed," falling back to
  /// a normal logout.
  Future<EntraTokenResult> refreshNativeTokens({required String refreshToken}) {
    return _requestTokens({
      'grant_type': 'refresh_token',
      'client_id': kEntraClientId,
      'refresh_token': refreshToken,
      'scope': _nativeScope,
    });
  }

  static String get _nativeScope =>
      'openid offline_access${kEntraApiScope.isEmpty ? '' : ' $kEntraApiScope'}';

  Future<EntraTokenResult> _requestTokens(Map<String, String> body) async {
    final response = await _dio.post(
      entraTokenUrl,
      data: body,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final data = response.data;
    final accessToken = data is Map ? data['access_token'] : null;
    if (accessToken is! String || accessToken.isEmpty) {
      throw const EntraTokenExchangeException(
        'Entra token response had no access_token',
      );
    }
    final refreshToken = data is Map ? data['refresh_token'] : null;
    return EntraTokenResult(
      accessToken: accessToken,
      refreshToken: refreshToken is String ? refreshToken : null,
    );
  }
}

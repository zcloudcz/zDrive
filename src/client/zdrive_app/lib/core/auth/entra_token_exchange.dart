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

/// Exchanges an Entra authorization code for an access token. A plain [Dio]
/// instance, not the app's shared one: that one is bound to the zDrive API
/// gateway's base URL and auth interceptor, neither of which applies to a
/// call against Entra's own token endpoint.
class EntraTokenExchange {
  EntraTokenExchange({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<String> exchangeCodeForAccessToken({
    required String code,
    required String codeVerifier,
  }) async {
    final response = await _dio.post(
      entraTokenUrl,
      data: {
        'grant_type': 'authorization_code',
        'client_id': kEntraClientId,
        'code': code,
        'redirect_uri': entraRedirectUri(),
        'code_verifier': codeVerifier,
        'scope': kEntraApiScope.isEmpty ? 'openid' : 'openid $kEntraApiScope',
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final accessToken = response.data is Map
        ? response.data['access_token']
        : null;
    if (accessToken is! String || accessToken.isEmpty) {
      throw const EntraTokenExchangeException(
        'Entra token response had no access_token',
      );
    }
    return accessToken;
  }
}

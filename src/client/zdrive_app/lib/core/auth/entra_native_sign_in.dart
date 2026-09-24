import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'entra_config.dart';
import 'entra_pkce.dart';
import 'entra_token_exchange.dart';

/// Thrown for failures specific to the native browser step — Entra reported
/// `error=`, or the returned `state` doesn't match what was sent (CSRF
/// check). Distinguished from [EntraTokenExchangeException]/[DioException]
/// the token exchange step throws, so the caller can tell "Entra/CSRF
/// rejected this" apart from "the exchange call itself failed."
class EntraNativeSignInException implements Exception {
  const EntraNativeSignInException(this.message);
  final String message;

  @override
  String toString() => 'EntraNativeSignInException: $message';
}

/// Runs the whole PKCE flow for native platforms (iOS, Android, Windows —
/// ADR 0003) in one call. Unlike the web flow (`entra_sign_in.dart`), there
/// is no separate page navigation between "open Entra" and "receive the
/// callback" — `FlutterWebAuth2.authenticate()` is a single awaited call —
/// so the verifier/state pair only needs to live in local variables for its
/// duration; sessionStorage (web's mechanism) has no native equivalent and
/// isn't needed here.
class EntraNativeSignIn {
  EntraNativeSignIn({
    EntraTokenExchange? tokenExchange,
    Future<String> Function({
      required String url,
      required String callbackUrlScheme,
      required FlutterWebAuth2Options options,
    })?
    authenticate,
  }) : _tokenExchange = tokenExchange ?? EntraTokenExchange(),
       _authenticate = authenticate ?? _defaultAuthenticate;

  final EntraTokenExchange _tokenExchange;

  // Threaded through a field (not called directly) so a test can fake the
  // browser step without a real browser or platform channel — ADR 0003 step
  // 9 asks for the callback-URL parsing (success, state mismatch, error=,
  // cancel) to be tested "with FlutterWebAuth2 behind a fake".
  final Future<String> Function({
    required String url,
    required String callbackUrlScheme,
    required FlutterWebAuth2Options options,
  })
  _authenticate;

  static Future<String> _defaultAuthenticate({
    required String url,
    required String callbackUrlScheme,
    required FlutterWebAuth2Options options,
  }) => FlutterWebAuth2.authenticate(
    url: url,
    callbackUrlScheme: callbackUrlScheme,
    options: options,
  );

  Future<EntraTokenResult> signIn() async {
    final verifier = EntraPkce.generateCodeVerifier();
    final state = EntraPkce.generateState();
    final redirectUri = nativeRedirectUri();
    final authorizeUrl = Uri.parse(entraAuthorizeUrl).replace(
      queryParameters: {
        'client_id': kEntraClientId,
        'redirect_uri': redirectUri,
        // offline_access (unlike web) — native stores the resulting refresh
        // token for silent renewal (ADR 0003).
        'scope':
            'openid offline_access${kEntraApiScope.isEmpty ? '' : ' $kEntraApiScope'}',
        'response_type': 'code',
        'response_mode': 'query',
        'code_challenge_method': 'S256',
        'code_challenge': EntraPkce.codeChallenge(verifier),
        'state': state,
      },
    );

    final callbackUrl = await _authenticate(
      url: authorizeUrl.toString(),
      callbackUrlScheme: nativeCallbackUrlScheme(),
      options: nativeOptions(),
    );

    final query = Uri.parse(callbackUrl).queryParameters;
    if (query.containsKey('error')) {
      throw EntraNativeSignInException(query['error']!);
    }
    if (query['state'] != state) {
      throw const EntraNativeSignInException('state mismatch');
    }
    final code = query['code'];
    if (code == null) {
      throw const EntraNativeSignInException('missing code');
    }

    return _tokenExchange.exchangeCodeForNativeTokens(
      code: code,
      codeVerifier: verifier,
      redirectUri: redirectUri,
    );
  }

  /// Threaded through a function (not inlined) so a test can assert its
  /// per-platform shape without depending on [defaultTargetPlatform], which
  /// a widget/unit test can't retarget to iOS/Android/Windows.
  @visibleForTesting
  static String nativeRedirectUri({TargetPlatform? platform}) =>
      (platform ?? defaultTargetPlatform) == TargetPlatform.windows
      ? kEntraWindowsRedirectUri
      : kEntraMobileRedirectUri;

  @visibleForTesting
  static String nativeCallbackUrlScheme({TargetPlatform? platform}) =>
      (platform ?? defaultTargetPlatform) == TargetPlatform.windows
      ? kEntraWindowsCallbackScheme
      : 'cz.zcloud.zdrive';

  /// Windows defaults to an embedded webview (`useWebview: true`);
  /// `false` switches to the loopback HTTP listener + system browser the
  /// ADR requires (RFC 8252 §7.3 — a webview shares neither the system
  /// browser's cookie jar nor its separate process, so it can't offer the
  /// same phishing resistance). iOS/Android are unaffected by this option —
  /// they always use ASWebAuthenticationSession / Chrome Custom Tabs.
  @visibleForTesting
  static FlutterWebAuth2Options nativeOptions({TargetPlatform? platform}) =>
      (platform ?? defaultTargetPlatform) == TargetPlatform.windows
      ? const FlutterWebAuth2Options(useWebview: false)
      : const FlutterWebAuth2Options();
}

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'entra_browser.dart';
import 'entra_config.dart';
import 'entra_pkce.dart';
import 'entra_session_storage.dart';

/// Drives the browser-side half of Entra's authorization code + PKCE flow:
/// starting it (generate verifier/state, stash them, redirect to Entra) and
/// completing it (verify the returned state against what was stashed).
///
/// The actual token exchange (POST to Entra's token endpoint) is a separate
/// step — see EntraTokenExchange — kept out of this class so the CSRF check
/// here stays pure and testable without a fake HTTP client.
class EntraSignIn {
  const EntraSignIn({EntraSessionStorage storage = const EntraSessionStorage()})
    : _storage = storage;

  final EntraSessionStorage _storage;

  @visibleForTesting
  static const String stateStorageKey = 'zdrive-entra-pkce-state';
  @visibleForTesting
  static const String verifierStorageKey = 'zdrive-entra-pkce-verifier';

  /// Generates a fresh verifier/state pair, stashes them in sessionStorage,
  /// then redirects the browser to Entra's authorize endpoint.
  void beginSignIn() {
    final verifier = EntraPkce.generateCodeVerifier();
    final state = EntraPkce.generateState();
    _storage.setItem(verifierStorageKey, verifier);
    _storage.setItem(stateStorageKey, state);
    final url = buildAuthorizeUrl(
      challenge: EntraPkce.codeChallenge(verifier),
      state: state,
    );
    navigateToEntraAuthorize(url.toString());
  }

  /// The authorize URL Entra expects — factored out as a static, pure
  /// function (no sessionStorage/browser dependency) so its shape can be
  /// asserted directly in a test. Mirrors the working pilot diagnostic
  /// (docs/identity-pilot-test/index.html) rather than a guessed shape.
  static Uri buildAuthorizeUrl({
    required String challenge,
    required String state,
  }) {
    final scope = kEntraApiScope.isEmpty ? 'openid' : 'openid $kEntraApiScope';
    return Uri.parse(entraAuthorizeUrl).replace(
      queryParameters: {
        'client_id': kEntraClientId,
        'redirect_uri': entraRedirectUri(),
        'scope': scope,
        'response_type': 'code',
        'response_mode': 'query',
        'code_challenge_method': 'S256',
        'code_challenge': challenge,
        'state': state,
      },
    );
  }

  /// Verifies [returnedState] against what [beginSignIn] stashed, and clears
  /// the stashed values either way — a PKCE verifier is single-use whether
  /// the check passes or not. Returns the code_verifier to exchange with, or
  /// null when nothing was stashed or the state does not match (CSRF
  /// rejection — the caller must not proceed to the token exchange).
  String? consumeVerifierIfStateMatches(String? returnedState) {
    final savedState = _storage.getItem(stateStorageKey);
    final verifier = _storage.getItem(verifierStorageKey);
    _storage.removeItem(stateStorageKey);
    _storage.removeItem(verifierStorageKey);
    if (savedState == null || verifier == null) return null;
    if (savedState != returnedState) return null;
    return verifier;
  }
}

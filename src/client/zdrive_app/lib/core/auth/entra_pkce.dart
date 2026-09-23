import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PKCE helpers (RFC 7636) for Entra's authorization code flow. Implemented
/// directly rather than pulling in MSAL.js: Entra CIAM SPA registrations
/// support browser calls to the authorize/token endpoints with PKCE and no
/// client secret (see ADR 0002).
class EntraPkce {
  static final Random _random = Random.secure();

  /// A cryptographically random code_verifier. base64url without padding is
  /// a subset of RFC 7636's allowed "unreserved" characters, and 32 random
  /// bytes encode to 43 characters — the RFC's minimum length.
  static String generateCodeVerifier() => _randomBase64Url(32);

  /// SHA-256 of [verifier], base64url-encoded without padding — RFC 7636's
  /// S256 code_challenge_method transform.
  static String codeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// A random CSRF state value. No length requirement from the spec; 16
  /// random bytes is plenty to be unguessable.
  static String generateState() => _randomBase64Url(16);

  static String _randomBase64Url(int byteLength) {
    final bytes = List<int>.generate(byteLength, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/core/auth/entra_pkce.dart';

void main() {
  group('EntraPkce.generateCodeVerifier', () {
    test('length is within RFC 7636\'s 43-128 char range', () {
      final verifier = EntraPkce.generateCodeVerifier();
      expect(verifier.length, inInclusiveRange(43, 128));
    });

    test('uses only RFC 7636 unreserved characters', () {
      final verifier = EntraPkce.generateCodeVerifier();
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(verifier), isTrue);
    });

    test('two calls produce different verifiers', () {
      expect(
        EntraPkce.generateCodeVerifier(),
        isNot(EntraPkce.generateCodeVerifier()),
      );
    });
  });

  group('EntraPkce.codeChallenge', () {
    test('is the SHA-256/base64url(no padding) transform of the verifier '
        '(RFC 7636 S256), verified against a manual computation', () {
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      final expected = base64Url
          .encode(sha256.convert(utf8.encode(verifier)).bytes)
          .replaceAll('=', '');

      expect(EntraPkce.codeChallenge(verifier), expected);
      // This verifier/challenge pair is also RFC 7636's own worked example
      // (Appendix B) — an independent check that the manual computation
      // above matches the spec, not just itself.
      expect(
        EntraPkce.codeChallenge(verifier),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('has no base64 padding characters', () {
      final challenge = EntraPkce.codeChallenge(
        EntraPkce.generateCodeVerifier(),
      );
      expect(challenge.contains('='), isFalse);
    });
  });

  group('EntraPkce.generateState', () {
    test(
      'two calls produce different state values (unguessable, not fixed)',
      () {
        expect(EntraPkce.generateState(), isNot(EntraPkce.generateState()));
      },
    );

    test('is non-empty', () {
      expect(EntraPkce.generateState(), isNotEmpty);
    });
  });
}

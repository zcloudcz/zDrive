import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/core/auth/entra_session_storage.dart';
import 'package:zdrive_app/core/auth/entra_sign_in.dart';

class FakeEntraSessionStorage extends EntraSessionStorage {
  final Map<String, String> store = {};

  @override
  void setItem(String key, String value) => store[key] = value;

  @override
  String? getItem(String key) => store[key];

  @override
  void removeItem(String key) => store.remove(key);
}

void main() {
  group('EntraSignIn.buildAuthorizeUrl', () {
    test('follows the Entra CIAM authorize endpoint shape from the working '
        'pilot diagnostic (docs/identity-pilot-test/index.html)', () {
      final uri = EntraSignIn.buildAuthorizeUrl(
        challenge: 'test-challenge',
        state: 'test-state',
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'zcloudcz.ciamlogin.com');
      expect(
        uri.path,
        '/37a15516-3c13-4bc8-a606-63226859b29a/oauth2/v2.0/authorize',
      );
      expect(uri.queryParameters['response_type'], 'code');
      expect(uri.queryParameters['response_mode'], 'query');
      expect(uri.queryParameters['code_challenge_method'], 'S256');
      expect(uri.queryParameters['code_challenge'], 'test-challenge');
      expect(uri.queryParameters['state'], 'test-state');
    });

    test('scope is just openid when no ENTRA_API_SCOPE is configured '
        '(default build)', () {
      final uri = EntraSignIn.buildAuthorizeUrl(challenge: 'c', state: 's');
      expect(uri.queryParameters['scope'], 'openid');
    });
  });

  group('EntraSignIn.consumeVerifierIfStateMatches', () {
    test('returns the stashed verifier when the returned state matches', () {
      final storage = FakeEntraSessionStorage();
      final signIn = EntraSignIn(storage: storage);
      signIn.beginSignIn();
      final stashedState = storage.store[EntraSignIn.stateStorageKey];
      final stashedVerifier = storage.store[EntraSignIn.verifierStorageKey];

      final result = signIn.consumeVerifierIfStateMatches(stashedState);

      expect(result, stashedVerifier);
    });

    test('rejects (returns null) when the returned state does not match — '
        'the CSRF check', () {
      final storage = FakeEntraSessionStorage();
      final signIn = EntraSignIn(storage: storage);
      signIn.beginSignIn();

      final result = signIn.consumeVerifierIfStateMatches(
        'attacker-supplied-state',
      );

      expect(result, isNull);
    });

    test(
      'clears the stashed values either way, so a verifier is single-use',
      () {
        final storage = FakeEntraSessionStorage();
        final signIn = EntraSignIn(storage: storage);
        signIn.beginSignIn();

        signIn.consumeVerifierIfStateMatches('attacker-supplied-state');

        expect(storage.store[EntraSignIn.stateStorageKey], isNull);
        expect(storage.store[EntraSignIn.verifierStorageKey], isNull);
      },
    );

    test(
      'returns null when nothing was stashed (no prior beginSignIn call)',
      () {
        final signIn = EntraSignIn(storage: FakeEntraSessionStorage());

        expect(signIn.consumeVerifierIfStateMatches('some-state'), isNull);
      },
    );
  });
}

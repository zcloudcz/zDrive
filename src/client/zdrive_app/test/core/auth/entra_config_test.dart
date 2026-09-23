import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/core/auth/entra_config.dart';

void main() {
  test('kEntraSignInVisible is false by default — no ENTRA_CLIENT_ID is '
      'passed in a normal `flutter test` run, and no production Entra app '
      'registration exists yet (ADR 0002)', () {
    expect(kEntraClientId, isEmpty);
    expect(kEntraApiScope, isEmpty);
    expect(kEntraSignInVisible, isFalse);
  });

  group('computeEntraSignInVisible', () {
    test('false when not web, even with both configured', () {
      expect(computeEntraSignInVisible(isWeb: false, clientId: 'id', scope: 'scope'), isFalse);
    });

    test('false with a client id but no scope — round-1 review of PR #70: '
        'redirecting through Entra with no scope fails far from the cause '
        '(missing access_token, or an audience the backend rejects)', () {
      expect(computeEntraSignInVisible(isWeb: true, clientId: 'id', scope: ''), isFalse);
    });

    test('false with a scope but no client id', () {
      expect(computeEntraSignInVisible(isWeb: true, clientId: '', scope: 'scope'), isFalse);
    });

    test('true only once web, client id and scope are all set', () {
      expect(computeEntraSignInVisible(isWeb: true, clientId: 'id', scope: 'scope'), isTrue);
    });
  });

  group('entraRedirectUri', () {
    test('drops query and fragment instead of leaving a bare "?#" — round-1 '
        'review of PR #70: Uri.replace(query: "", fragment: "") sets them '
        'present-but-empty, which still serializes as a trailing "?#" and '
        'would never exact-match a redirect_uri registered with Entra', () {
      // Uri.base in a plain `flutter test` run has no real browser location,
      // but the fix is in how entraRedirectUri rebuilds path/query/fragment
      // regardless of what Uri.base carries — this exercises that directly.
      final uri = entraRedirectUri();
      expect(uri, isNot(contains('?')));
      expect(uri, isNot(contains('#')));
      expect(uri, endsWith('/'));
    });
  });
}

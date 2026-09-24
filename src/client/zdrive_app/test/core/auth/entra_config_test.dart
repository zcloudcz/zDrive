import 'package:flutter/foundation.dart' show TargetPlatform;
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
    test('false with a client id but no scope — round-1 review of PR #70: '
        'redirecting through Entra with no scope fails far from the cause '
        '(missing access_token, or an audience the backend rejects)', () {
      expect(
        computeEntraSignInVisible(
          isWeb: true,
          platform: TargetPlatform.android,
          clientId: 'id',
          scope: '',
        ),
        isFalse,
      );
    });

    test('false with a scope but no client id', () {
      expect(
        computeEntraSignInVisible(
          isWeb: true,
          platform: TargetPlatform.android,
          clientId: '',
          scope: 'scope',
        ),
        isFalse,
      );
    });

    test('true on web regardless of platform, once configured', () {
      expect(
        computeEntraSignInVisible(
          isWeb: true,
          platform: TargetPlatform.linux,
          clientId: 'id',
          scope: 'scope',
        ),
        isTrue,
      );
    });

    // ADR 0003 — iOS, Android and Windows get a native redirect URI; macOS
    // and Linux have no app registration entry for one and stay
    // password-only, even fully configured.
    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.windows,
    ]) {
      test('true on native $platform, once configured (ADR 0003)', () {
        expect(
          computeEntraSignInVisible(
            isWeb: false,
            platform: platform,
            clientId: 'id',
            scope: 'scope',
          ),
          isTrue,
        );
      });
    }

    for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
      test('false on native $platform even when configured — no app '
          'registration entry for it (ADR 0003 NOT list)', () {
        expect(
          computeEntraSignInVisible(
            isWeb: false,
            platform: platform,
            clientId: 'id',
            scope: 'scope',
          ),
          isFalse,
        );
      });
    }
  });

  group('entraForwardTarget', () {
    test('null with no code/error in the query, regardless of location', () {
      expect(entraForwardTarget({}, '/login'), isNull);
      expect(entraForwardTarget({}, '/home/files'), isNull);
    });

    test('forwards code+state when landing at the entry point (/login) — '
        'the shape a real Entra redirect actually arrives as', () {
      final target = entraForwardTarget({'code': 'X', 'state': 'Y'}, '/login');
      expect(target, '/auth/entra-callback?code=X&state=Y');
    });

    test('forwards an `error` the same way', () {
      final target = entraForwardTarget({'error': 'access_denied'}, '/login');
      expect(target, '/auth/entra-callback?error=access_denied');
    });

    test('round-2 review of PR #70, the redirect-loop case: does NOT '
        're-forward once already on the callback route, even though the '
        'params are still in the caller-supplied query map (the caller is '
        'expected to have stripped the real URL by then; this asserts the '
        'route itself is also a hard stop, not just the strip)', () {
      expect(entraForwardTarget({'code': 'X', 'state': 'Y'}, '/auth/entra-callback'), isNull);
    });

    test('round-2 review of PR #70, share-link hijack case: a crafted link '
        'like https://drive.zcloud.cz/?code=x#/s/abc must not divert a '
        'public share-link visit into the Entra callback', () {
      expect(entraForwardTarget({'code': 'x'}, '/s/abc123'), isNull);
    });

    test('does not forward once authenticated and already elsewhere '
        '(e.g. a stale bookmarked link with old query params)', () {
      expect(entraForwardTarget({'code': 'stale'}, '/home/files'), isNull);
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

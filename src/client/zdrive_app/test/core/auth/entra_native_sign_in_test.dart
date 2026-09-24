import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/auth/entra_config.dart';
import 'package:zdrive_app/core/auth/entra_native_sign_in.dart';
import 'package:zdrive_app/core/auth/entra_token_exchange.dart';

class MockEntraTokenExchange extends Mock implements EntraTokenExchange {}

void main() {
  setUpAll(() {
    registerFallbackValue(const FlutterWebAuth2Options());
  });

  group('EntraNativeSignIn.signIn', () {
    late MockEntraTokenExchange tokenExchange;

    setUp(() {
      tokenExchange = MockEntraTokenExchange();
    });

    /// Echoes the `state` the caller generated back in the callback URL —
    /// state is random per call, so a fixed fixture can't be used; parsing
    /// it out of the authorize [url] mirrors what a real Entra redirect
    /// does (it always reflects the `state` it was sent).
    String stateFromAuthorizeUrl(String url) =>
        Uri.parse(url).queryParameters['state']!;

    test('success: exchanges the code with the token exchange and returns '
        'its result', () async {
      when(
        () => tokenExchange.exchangeCodeForNativeTokens(
          code: any(named: 'code'),
          codeVerifier: any(named: 'codeVerifier'),
          redirectUri: any(named: 'redirectUri'),
        ),
      ).thenAnswer(
        (_) async => const EntraTokenResult(
          accessToken: 'native-access-token',
          refreshToken: 'native-refresh-token',
        ),
      );
      final signIn = EntraNativeSignIn(
        tokenExchange: tokenExchange,
        authenticate: ({
          required url,
          required callbackUrlScheme,
          required options,
        }) async {
          final state = stateFromAuthorizeUrl(url);
          return 'cz.zcloud.zdrive://auth?code=auth-code&state=$state';
        },
      );

      final result = await signIn.signIn();

      expect(result.accessToken, 'native-access-token');
      expect(result.refreshToken, 'native-refresh-token');
      verify(
        () => tokenExchange.exchangeCodeForNativeTokens(
          code: 'auth-code',
          codeVerifier: any(named: 'codeVerifier'),
          redirectUri: kEntraMobileRedirectUri,
        ),
      ).called(1);
    });

    test('state mismatch: rejected before the token exchange ever runs '
        '(CSRF check)', () async {
      final signIn = EntraNativeSignIn(
        tokenExchange: tokenExchange,
        authenticate: ({
          required url,
          required callbackUrlScheme,
          required options,
        }) async => 'cz.zcloud.zdrive://auth?code=auth-code&state=attacker',
      );

      await expectLater(
        signIn.signIn(),
        throwsA(
          isA<EntraNativeSignInException>().having(
            (e) => e.kind,
            'kind',
            // Opus review of PR #72, finding 5: a state mismatch is
            // "rejected", not "denied" — LoginPage shows a different
            // message for each.
            EntraNativeSignInFailureKind.rejected,
          ),
        ),
      );
      verifyNever(
        () => tokenExchange.exchangeCodeForNativeTokens(
          code: any(named: 'code'),
          codeVerifier: any(named: 'codeVerifier'),
          redirectUri: any(named: 'redirectUri'),
        ),
      );
    });

    test('Entra `error=`: rejected without ever reaching the token exchange', () async {
      final signIn = EntraNativeSignIn(
        tokenExchange: tokenExchange,
        authenticate: ({
          required url,
          required callbackUrlScheme,
          required options,
        }) async => 'cz.zcloud.zdrive://auth?error=access_denied',
      );

      await expectLater(
        signIn.signIn(),
        throwsA(
          isA<EntraNativeSignInException>().having(
            (e) => e.kind,
            'kind',
            EntraNativeSignInFailureKind.denied,
          ),
        ),
      );
      verifyNever(
        () => tokenExchange.exchangeCodeForNativeTokens(
          code: any(named: 'code'),
          codeVerifier: any(named: 'codeVerifier'),
          redirectUri: any(named: 'redirectUri'),
        ),
      );
    });

    test('user cancels the browser sheet: flutter_web_auth_2 throws — '
        'propagates as-is so the caller (LoginPage) can treat it as "no '
        'error dialog" per ADR 0003\'s failure modes', () async {
      final signIn = EntraNativeSignIn(
        tokenExchange: tokenExchange,
        authenticate: ({
          required url,
          required callbackUrlScheme,
          required options,
        }) async => throw Exception('CANCELED'),
      );

      await expectLater(signIn.signIn(), throwsA(isA<Exception>()));
      verifyNever(
        () => tokenExchange.exchangeCodeForNativeTokens(
          code: any(named: 'code'),
          codeVerifier: any(named: 'codeVerifier'),
          redirectUri: any(named: 'redirectUri'),
        ),
      );
    });
  });

  group('EntraNativeSignIn.nativeRedirectUri', () {
    test('Windows uses the loopback redirect URI', () {
      expect(
        EntraNativeSignIn.nativeRedirectUri(platform: TargetPlatform.windows),
        kEntraWindowsRedirectUri,
      );
    });

    test('iOS and Android use the custom-scheme redirect URI', () {
      expect(
        EntraNativeSignIn.nativeRedirectUri(platform: TargetPlatform.iOS),
        kEntraMobileRedirectUri,
      );
      expect(
        EntraNativeSignIn.nativeRedirectUri(platform: TargetPlatform.android),
        kEntraMobileRedirectUri,
      );
    });
  });

  group('EntraNativeSignIn.nativeCallbackUrlScheme', () {
    test('Windows uses the loopback host:port, no trailing slash — '
        'flutter_web_auth_2 parses this as a URI, not a string prefix', () {
      expect(
        EntraNativeSignIn.nativeCallbackUrlScheme(
          platform: TargetPlatform.windows,
        ),
        'http://localhost:43823',
      );
    });

    test('iOS and Android use the bare custom scheme', () {
      expect(
        EntraNativeSignIn.nativeCallbackUrlScheme(
          platform: TargetPlatform.iOS,
        ),
        'cz.zcloud.zdrive',
      );
    });
  });

  group('EntraNativeSignIn.nativeOptions', () {
    test('Windows disables the embedded webview — the ADR requires the '
        'system browser + loopback listener (RFC 8252 §7.3), but the '
        'package defaults to a webview on Windows', () {
      expect(
        EntraNativeSignIn.nativeOptions(
          platform: TargetPlatform.windows,
        ).useWebview,
        isFalse,
      );
    });

    test('iOS/Android use the package default (native Custom Tabs / '
        'ASWebAuthenticationSession, not the Linux/Windows-only webview '
        'toggle)', () {
      expect(
        EntraNativeSignIn.nativeOptions(platform: TargetPlatform.iOS).useWebview,
        isTrue, // FlutterWebAuth2Options' own default — has no effect on iOS
      );
    });
  });
}

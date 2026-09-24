import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/auth/entra_token_exchange.dart';

class MockHttpClientAdapter extends Mock implements HttpClientAdapter {}

void main() {
  late MockHttpClientAdapter adapter;
  late EntraTokenExchange tokenExchange;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/oauth2/v2.0/token'));
  });

  setUp(() {
    adapter = MockHttpClientAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    tokenExchange = EntraTokenExchange(dio: dio);
  });

  void stubResponse(Map<String, dynamic> body, {int statusCode = 200}) {
    when(
      () => adapter.fetch(any(), any(), any()),
    ).thenAnswer(
      (_) async => ResponseBody.fromString(
        jsonEncode(body),
        statusCode,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
  }

  group('exchangeCodeForNativeTokens', () {
    test('posts the native redirect_uri and offline_access scope, and '
        'returns both tokens from the response — ADR 0003: native stores '
        'the refresh token for silent renewal, unlike web', () async {
      stubResponse({
        'access_token': 'native-access-token',
        'refresh_token': 'native-refresh-token',
      });

      final result = await tokenExchange.exchangeCodeForNativeTokens(
        code: 'auth-code',
        codeVerifier: 'verifier',
        redirectUri: 'cz.zcloud.zdrive://auth',
      );

      expect(result.accessToken, 'native-access-token');
      expect(result.refreshToken, 'native-refresh-token');
      final captured = verify(
        () => adapter.fetch(captureAny(), any(), any()),
      ).captured;
      final request = captured.single as RequestOptions;
      final sentBody = request.data as Map<String, String>;
      expect(sentBody['redirect_uri'], 'cz.zcloud.zdrive://auth');
      expect(sentBody['scope'], 'openid offline_access');
      expect(sentBody['grant_type'], 'authorization_code');
    });

    test('throws EntraTokenExchangeException when the response has no '
        'access_token', () async {
      stubResponse({'error': 'invalid_grant'});

      expect(
        () => tokenExchange.exchangeCodeForNativeTokens(
          code: 'auth-code',
          codeVerifier: 'verifier',
          redirectUri: 'cz.zcloud.zdrive://auth',
        ),
        throwsA(isA<EntraTokenExchangeException>()),
      );
    });
  });

  group('refreshNativeTokens', () {
    test('posts a refresh_token grant with no code/redirect_uri', () async {
      stubResponse({
        'access_token': 'renewed-access-token',
        'refresh_token': 'rotated-refresh-token',
      });

      final result = await tokenExchange.refreshNativeTokens(
        refreshToken: 'stored-refresh-token',
      );

      expect(result.accessToken, 'renewed-access-token');
      expect(result.refreshToken, 'rotated-refresh-token');
      final captured = verify(
        () => adapter.fetch(captureAny(), any(), any()),
      ).captured;
      final request = captured.single as RequestOptions;
      final sentBody = request.data as Map<String, String>;
      expect(sentBody['grant_type'], 'refresh_token');
      expect(sentBody['refresh_token'], 'stored-refresh-token');
      expect(sentBody.containsKey('code'), isFalse);
      expect(sentBody.containsKey('redirect_uri'), isFalse);
    });

    test('a response with no new refresh_token still yields the new access '
        'token — Entra does not always rotate it', () async {
      stubResponse({'access_token': 'renewed-access-token'});

      final result = await tokenExchange.refreshNativeTokens(
        refreshToken: 'stored-refresh-token',
      );

      expect(result.accessToken, 'renewed-access-token');
      expect(result.refreshToken, isNull);
    });
  });

  test('exchangeCodeForAccessToken (web) keeps requesting a bare `openid` '
      'scope, unaffected by the native additions', () async {
    stubResponse({'access_token': 'web-access-token'});

    final accessToken = await tokenExchange.exchangeCodeForAccessToken(
      code: 'auth-code',
      codeVerifier: 'verifier',
    );

    expect(accessToken, 'web-access-token');
    final captured = verify(
      () => adapter.fetch(captureAny(), any(), any()),
    ).captured;
    final request = captured.single as RequestOptions;
    final sentBody = request.data as Map<String, String>;
    expect(sentBody['scope'], 'openid');
    expect(sentBody.containsKey('refresh_token'), isFalse);
  });
}

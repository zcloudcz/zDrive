import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/auth/entra_token_exchange.dart';
import 'package:zdrive_app/core/auth/token_storage.dart';
import 'package:zdrive_app/core/network/api_constants.dart';
import 'package:zdrive_app/core/network/auth_interceptor.dart';

class MockEntraTokenExchange extends Mock implements EntraTokenExchange {}

class MockHttpClientAdapter extends Mock implements HttpClientAdapter {}

/// In-memory FlutterSecureStorage backend — TokenStorage wraps the plugin
/// directly with no seam, so this is the smallest way to give it a real,
/// working store in a widget-test environment (no platform channel).
class InMemorySecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> _store = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    required Map<String, String> options,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => _store[key];

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => _store.remove(key);

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => _store.containsKey(key);

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map.of(_store);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      _store.clear();
}

ResponseBody _jsonBody(int statusCode, Map<String, dynamic> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStoragePlatform.instance = InMemorySecureStorage();

  late TokenStorage tokenStorage;
  late MockEntraTokenExchange entraTokenExchange;
  late MockHttpClientAdapter adapter;
  late AuthInterceptor interceptor;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/some/endpoint'));
  });

  setUp(() async {
    tokenStorage = TokenStorage();
    await tokenStorage.clear();
    await tokenStorage.saveTokens(
      accessToken: 'expired-access-token',
      refreshToken: 'zdrive-refresh-token',
    );
    entraTokenExchange = MockEntraTokenExchange();
    adapter = MockHttpClientAdapter();
    interceptor = AuthInterceptor(tokenStorage)
      ..entraTokenExchange = entraTokenExchange
      // Opus review of PR #72, finding 3: dioFactory is the seam that lets
      // this test control every response the interceptor's internal Dio
      // sees, instead of hitting ApiConstants.baseUrl / localhost:5100 for
      // real.
      ..dioFactory = () => Dio(BaseOptions(baseUrl: ApiConstants.baseUrl))
        ..httpClientAdapter = adapter;
  });

  /// Drives [AuthInterceptor.onError] directly rather than through a real
  /// request — dio's own retry pipeline for the ORIGINAL (401) request
  /// lives outside the interceptor under test, so this constructs the
  /// DioException onError expects and hands it a fresh (never-completing)
  /// handler.
  Future<void> triggerOnError() async {
    final err = DioException(
      requestOptions: RequestOptions(path: '/files'),
      response: Response(
        requestOptions: RequestOptions(path: '/files'),
        statusCode: 401,
      ),
      type: DioExceptionType.badResponse,
    );
    final handler = ErrorInterceptorHandler();
    await interceptor.onError(err, handler);
    // Every failure path this test drives ends in handler.next(err) — that
    // completes the handler's own Future with an error (dio's contract:
    // "no interceptor resolved this"). Nothing here plays the role of the
    // real dio pipeline that would consume it, so it's left dangling and
    // its error would otherwise surface as an unhandled async error in the
    // test zone.
    // ignore: invalid_use_of_protected_member
    handler.future.ignore();
  }

  /// Stubs the interceptor's internal Dio: `/auth/refresh` gets
  /// [refreshResponse] (a `(statusCode, body)` record, or `null` to make the
  /// call throw a plain network error instead of a bad response),
  /// `/auth/entra` gets [entraExchangeResponse], and anything else (the
  /// retried original request) gets 200.
  void stubDio({
    (int, Map<String, dynamic>)? refreshResponse,
    (int, Map<String, dynamic>)? entraExchangeResponse,
  }) {
    when(() => adapter.fetch(any(), any(), any())).thenAnswer((invocation) async {
      final options = invocation.positionalArguments[0] as RequestOptions;
      if (options.path == ApiConstants.authRefresh) {
        if (refreshResponse == null) {
          throw Exception('connection refused');
        }
        return _jsonBody(refreshResponse.$1, {'data': refreshResponse.$2});
      }
      if (options.path == ApiConstants.authEntraExchange) {
        final response = entraExchangeResponse!;
        return _jsonBody(response.$1, {'data': response.$2});
      }
      // The retried original request.
      return _jsonBody(200, {});
    });
  }

  test('no stored Entra refresh token (password-login session): zDrive '
      'refresh rejected (404) logs out exactly as before this existed — '
      'native renewal never runs', () async {
    stubDio(refreshResponse: (404, {}));

    await triggerOnError();

    expect(await tokenStorage.accessToken, isNull);
    expect(await tokenStorage.refreshToken, isNull);
    verifyNever(
      () => entraTokenExchange.refreshNativeTokens(
        refreshToken: any(named: 'refreshToken'),
      ),
    );
  });

  test('zDrive refresh fails with a NETWORK error (not an auth rejection): '
      'native renewal is never attempted even with an Entra refresh token '
      'stored — Opus review of PR #72, finding 1: only 401/404 from '
      '/auth/refresh means the zDrive refresh token is actually bad', () async {
    await tokenStorage.saveEntraRefreshToken('stored-entra-refresh-token');
    stubDio(refreshResponse: null);

    await triggerOnError();

    expect(await tokenStorage.accessToken, isNull);
    verifyNever(
      () => entraTokenExchange.refreshNativeTokens(
        refreshToken: any(named: 'refreshToken'),
      ),
    );
  });

  test('Entra refresh token revoked/expired: silent renewal attempt fails '
      '-> normal logout, Entra refresh token cleared too', () async {
    await tokenStorage.saveEntraRefreshToken('stored-entra-refresh-token');
    stubDio(refreshResponse: (404, {}));
    when(
      () => entraTokenExchange.refreshNativeTokens(
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenThrow(const EntraTokenExchangeException('invalid_grant'));

    await triggerOnError();

    expect(await tokenStorage.accessToken, isNull);
    expect(await tokenStorage.entraRefreshToken, isNull);
    verify(
      () => entraTokenExchange.refreshNativeTokens(
        refreshToken: 'stored-entra-refresh-token',
      ),
    ).called(1);
  });

  test('Entra itself accepts the renewed access token but /auth/entra '
      'rejects it (401): renewal is attempted exactly once, not retried in '
      'a loop — Opus review of PR #72, finding 3', () async {
    await tokenStorage.saveEntraRefreshToken('stored-entra-refresh-token');
    stubDio(refreshResponse: (404, {}), entraExchangeResponse: (401, {}));
    when(
      () => entraTokenExchange.refreshNativeTokens(
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer(
      (_) async => const EntraTokenResult(accessToken: 'entra-access-token'),
    );

    await triggerOnError();

    expect(await tokenStorage.accessToken, isNull);
    verify(
      () => entraTokenExchange.refreshNativeTokens(
        refreshToken: 'stored-entra-refresh-token',
      ),
    ).called(1);
  });

  test('success: Entra refresh ok -> /auth/entra ok -> new zDrive tokens '
      'saved, rotated Entra refresh token saved, original request retried '
      'with the new access token — Opus review of PR #72, finding 3', () async {
    await tokenStorage.saveEntraRefreshToken('stored-entra-refresh-token');
    stubDio(
      refreshResponse: (404, {}),
      entraExchangeResponse: (200, {
        'accessToken': 'new-zdrive-access-token',
        'refreshToken': 'new-zdrive-refresh-token',
      }),
    );
    when(
      () => entraTokenExchange.refreshNativeTokens(
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer(
      (_) async => const EntraTokenResult(
        accessToken: 'entra-access-token',
        refreshToken: 'rotated-entra-refresh-token',
      ),
    );

    final err = DioException(
      requestOptions: RequestOptions(path: '/files'),
      response: Response(
        requestOptions: RequestOptions(path: '/files'),
        statusCode: 401,
      ),
      type: DioExceptionType.badResponse,
    );
    final handler = ErrorInterceptorHandler();
    await interceptor.onError(err, handler);

    expect(await tokenStorage.accessToken, 'new-zdrive-access-token');
    expect(await tokenStorage.refreshToken, 'new-zdrive-refresh-token');
    expect(await tokenStorage.entraRefreshToken, 'rotated-entra-refresh-token');
    final retriedRequest = verify(
      () => adapter.fetch(captureAny(), any(), any()),
    ).captured.last as RequestOptions;
    expect(retriedRequest.path, '/files');
    expect(
      retriedRequest.headers['Authorization'],
      'Bearer new-zdrive-access-token',
    );
  });
}

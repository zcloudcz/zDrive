import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/auth/entra_token_exchange.dart';
import 'package:zdrive_app/core/auth/token_storage.dart';
import 'package:zdrive_app/core/network/auth_interceptor.dart';

class MockEntraTokenExchange extends Mock implements EntraTokenExchange {}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStoragePlatform.instance = InMemorySecureStorage();

  late TokenStorage tokenStorage;
  late MockEntraTokenExchange entraTokenExchange;
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
    interceptor = AuthInterceptor(tokenStorage)
      ..entraTokenExchange = entraTokenExchange;
  });

  /// Drives [AuthInterceptor.onError] directly — a full retry round-trip
  /// needs a real HTTP server (the bare `Dio` inside the interceptor isn't
  /// injectable), so this exercises the same code path onError would run
  /// after a request's 401, without depending on network I/O for the
  /// zDrive refresh call, which callers can't observe or stub anyway.
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
    // Every path this test drives ends in handler.next(err) — that
    // completes the handler's own Future with an error (dio's contract:
    // "no interceptor resolved this"), which the real dio pipeline
    // consumes by rethrowing to the original caller. Nothing here plays
    // that role, so the Future is left dangling and its error would
    // otherwise surface as an unhandled async error in the test zone.
    // ignore: invalid_use_of_protected_member
    handler.future.ignore();
  }

  test('no stored Entra refresh token (password-login session): zDrive '
      'refresh failure logs out exactly as before this existed — native '
      'renewal never runs', () async {
    await triggerOnError();

    // The interceptor's own zDrive-refresh Dio call fails for real (no
    // server) — that failure already reaches _renewViaEntra, which then
    // finds no stored Entra refresh token and rethrows, ending in a
    // cleared session either way.
    expect(await tokenStorage.accessToken, isNull);
    expect(await tokenStorage.refreshToken, isNull);
    verifyNever(
      () => entraTokenExchange.refreshNativeTokens(
        refreshToken: any(named: 'refreshToken'),
      ),
    );
  });

  test('Entra refresh token revoked/expired: silent renewal attempt fails '
      '-> normal logout, Entra refresh token cleared too', () async {
    await tokenStorage.saveEntraRefreshToken('stored-entra-refresh-token');
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

  test('one renewal attempt per failed refresh: a second, independent 401 '
      'triggers its own single attempt, not an unbounded loop', () async {
    await tokenStorage.saveEntraRefreshToken('stored-entra-refresh-token');
    when(
      () => entraTokenExchange.refreshNativeTokens(
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenThrow(const EntraTokenExchangeException('invalid_grant'));

    await triggerOnError();
    // Re-seed as if the user signed in again with a fresh Entra refresh
    // token, then hit another 401.
    await tokenStorage.saveTokens(
      accessToken: 'expired-again',
      refreshToken: 'zdrive-refresh-token-2',
    );
    await tokenStorage.saveEntraRefreshToken('stored-entra-refresh-token-2');
    await triggerOnError();

    verify(
      () => entraTokenExchange.refreshNativeTokens(
        refreshToken: any(named: 'refreshToken'),
      ),
    ).called(2);
  });
}

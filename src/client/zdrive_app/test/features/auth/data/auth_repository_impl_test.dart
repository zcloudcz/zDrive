import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/auth/token_storage.dart';
import 'package:zdrive_app/features/auth/data/auth_dtos.dart';
import 'package:zdrive_app/features/auth/data/auth_remote_data_source.dart';
import 'package:zdrive_app/features/auth/data/auth_repository_impl.dart';

class MockAuthRemoteDataSource extends Mock implements AuthRemoteDataSource {}

class MockTokenStorage extends Mock implements TokenStorage {}

void main() {
  late MockAuthRemoteDataSource remoteDataSource;
  late MockTokenStorage tokenStorage;
  late AuthRepositoryImpl repository;

  setUp(() {
    remoteDataSource = MockAuthRemoteDataSource();
    tokenStorage = MockTokenStorage();
    repository = AuthRepositoryImpl(remoteDataSource, tokenStorage);
    when(
      () => tokenStorage.saveTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer((_) async {});
    when(() => tokenStorage.clearEntraRefreshToken()).thenAnswer((_) async {});
    when(() => tokenStorage.saveEntraRefreshToken(any())).thenAnswer((_) async {});
    when(() => tokenStorage.clear()).thenAnswer((_) async {});
    when(() => remoteDataSource.getCurrentUser()).thenAnswer(
      (_) async => const UserDto(id: 'u1', email: 'a@b.com', displayName: 'A'),
    );
  });

  group('login (Opus review of PR #72, finding 1)', () {
    test('clears any stale Entra refresh token from a previous Entra '
        'sign-in on this device — otherwise silent renewal could later '
        'revive that identity under this password-login user', () async {
      when(
        () => remoteDataSource.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => AuthResponseDto(
          accessToken: 'zdrive-access',
          refreshToken: 'zdrive-refresh',
          expiresAt: DateTime.utc(2030),
        ),
      );

      await repository.login(email: 'a@b.com', password: 'password123');

      verify(() => tokenStorage.clearEntraRefreshToken()).called(1);
    });
  });

  group('register', () {
    test('also clears any stale Entra refresh token', () async {
      when(
        () => remoteDataSource.register(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer(
        (_) async => AuthResponseDto(
          accessToken: 'zdrive-access',
          refreshToken: 'zdrive-refresh',
          expiresAt: DateTime.utc(2030),
        ),
      );

      await repository.register(
        email: 'a@b.com',
        password: 'password123',
        displayName: 'A',
      );

      verify(() => tokenStorage.clearEntraRefreshToken()).called(1);
    });
  });

  group('loginWithEntra (Opus review of PR #72, finding 1)', () {
    setUp(() {
      when(
        () => remoteDataSource.entraExchange(
          accessToken: any(named: 'accessToken'),
        ),
      ).thenAnswer(
        (_) async => AuthResponseDto(
          accessToken: 'zdrive-access',
          refreshToken: 'zdrive-refresh',
          expiresAt: DateTime.utc(2030),
        ),
      );
    });

    test('success: saves zDrive tokens and the Entra refresh token', () async {
      await repository.loginWithEntra(
        'entra-access',
        entraRefreshToken: 'entra-refresh',
      );

      verify(
        () => tokenStorage.saveTokens(
          accessToken: 'zdrive-access',
          refreshToken: 'zdrive-refresh',
        ),
      ).called(1);
      verify(
        () => tokenStorage.saveEntraRefreshToken('entra-refresh'),
      ).called(1);
    });

    test('getCurrentUser fails after tokens were saved: the whole session '
        'is cleared, not left half-saved for the next user to inherit', () async {
      when(() => remoteDataSource.getCurrentUser()).thenThrow(
        Exception('network error'),
      );

      await expectLater(
        repository.loginWithEntra(
          'entra-access',
          entraRefreshToken: 'entra-refresh',
        ),
        throwsA(isA<Exception>()),
      );

      verify(() => tokenStorage.clear()).called(1);
    });
  });
}

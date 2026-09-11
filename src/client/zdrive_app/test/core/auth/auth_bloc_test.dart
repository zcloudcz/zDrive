import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/auth/auth_bloc.dart';
import 'package:zdrive_app/core/auth/token_storage.dart';
import 'package:zdrive_app/features/auth/domain/auth_repository.dart';
import 'package:zdrive_app/features/auth/domain/user.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockTokenStorage extends Mock implements TokenStorage {}

void main() {
  late MockAuthRepository mockAuthRepository;
  late MockTokenStorage mockTokenStorage;

  const testUser = User(
    id: '1',
    email: 'test@example.com',
    displayName: 'Test User',
  );

  setUp(() {
    mockAuthRepository = MockAuthRepository();
    mockTokenStorage = MockTokenStorage();
  });

  AuthBloc buildBloc() => AuthBloc(
        authRepository: mockAuthRepository,
        tokenStorage: mockTokenStorage,
      );

  group('CheckAuthStatus', () {
    blocTest<AuthBloc, AuthState>(
      'emits [Unauthenticated] when no tokens stored',
      build: () {
        when(() => mockTokenStorage.hasTokens)
            .thenAnswer((_) async => false);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const CheckAuthStatus()),
      expect: () => [const Unauthenticated()],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [Authenticated] when valid tokens exist',
      build: () {
        when(() => mockTokenStorage.hasTokens)
            .thenAnswer((_) async => true);
        when(() => mockAuthRepository.getCurrentUser())
            .thenAnswer((_) async => testUser);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const CheckAuthStatus()),
      expect: () => [const Authenticated(testUser)],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [Unauthenticated] when token is invalid',
      build: () {
        when(() => mockTokenStorage.hasTokens)
            .thenAnswer((_) async => true);
        when(() => mockAuthRepository.getCurrentUser())
            .thenThrow(Exception('unauthorized'));
        when(() => mockTokenStorage.clear())
            .thenAnswer((_) async {});
        return buildBloc();
      },
      act: (bloc) => bloc.add(const CheckAuthStatus()),
      expect: () => [const Unauthenticated()],
    );
  });

  group('LoginRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, Authenticated] on successful login',
      build: () {
        when(() => mockAuthRepository.login(
              email: any(named: 'email'),
              password: any(named: 'password'),
            )).thenAnswer((_) async => testUser);
        return buildBloc();
      },
      act: (bloc) => bloc.add(
        const LoginRequested(email: 'test@example.com', password: 'password'),
      ),
      expect: () => [const AuthLoading(), const Authenticated(testUser)],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] on failed login',
      build: () {
        when(() => mockAuthRepository.login(
              email: any(named: 'email'),
              password: any(named: 'password'),
            )).thenThrow(Exception('invalid credentials'));
        return buildBloc();
      },
      act: (bloc) => bloc.add(
        const LoginRequested(email: 'test@example.com', password: 'wrong'),
      ),
      expect: () => [
        const AuthLoading(),
        isA<AuthError>(),
      ],
    );
  });

  group('RegisterRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, Authenticated] on successful registration',
      build: () {
        when(() => mockAuthRepository.register(
              email: any(named: 'email'),
              password: any(named: 'password'),
              displayName: any(named: 'displayName'),
            )).thenAnswer((_) async => testUser);
        return buildBloc();
      },
      act: (bloc) => bloc.add(
        const RegisterRequested(
          email: 'test@example.com',
          password: 'password123',
          displayName: 'Test User',
        ),
      ),
      expect: () => [const AuthLoading(), const Authenticated(testUser)],
    );
  });

  group('LogoutRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [Unauthenticated] on logout',
      build: () {
        when(() => mockAuthRepository.logout())
            .thenAnswer((_) async {});
        return buildBloc();
      },
      act: (bloc) => bloc.add(const LogoutRequested()),
      expect: () => [const Unauthenticated()],
    );

    test('calls beforeLogout before AuthRepository.logout, when one is '
        'given — wired in main.dart to SyncCoordinator.endSession so the '
        'sync feature\'s state is cleared before the account actually logs '
        'out', () async {
      final callOrder = <String>[];
      when(() => mockAuthRepository.logout()).thenAnswer((_) async {
        callOrder.add('logout');
      });
      final bloc = AuthBloc(
        authRepository: mockAuthRepository,
        tokenStorage: mockTokenStorage,
        beforeLogout: () async {
          callOrder.add('beforeLogout');
        },
      );
      addTearDown(bloc.close);

      bloc.add(const LogoutRequested());
      await bloc.stream.firstWhere((s) => s is Unauthenticated);

      expect(callOrder, ['beforeLogout', 'logout']);
    });

    blocTest<AuthBloc, AuthState>(
      'still logs out normally when no beforeLogout is given — it is '
      'optional',
      build: () {
        when(() => mockAuthRepository.logout())
            .thenAnswer((_) async {});
        return buildBloc(); // no beforeLogout passed
      },
      act: (bloc) => bloc.add(const LogoutRequested()),
      expect: () => [const Unauthenticated()],
    );
  });
}

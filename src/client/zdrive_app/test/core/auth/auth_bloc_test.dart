import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/auth/auth_bloc.dart';
import 'package:zdrive_app/core/auth/token_storage.dart';
import 'package:zdrive_app/core/diagnostics/diagnostics_io.dart';
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
        when(() => mockTokenStorage.hasTokens).thenAnswer((_) async => false);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const CheckAuthStatus()),
      expect: () => [const Unauthenticated()],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [Authenticated] when valid tokens exist',
      build: () {
        when(() => mockTokenStorage.hasTokens).thenAnswer((_) async => true);
        when(
          () => mockAuthRepository.getCurrentUser(),
        ).thenAnswer((_) async => testUser);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const CheckAuthStatus()),
      expect: () => [const Authenticated(testUser)],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [Unauthenticated] when token is invalid',
      build: () {
        when(() => mockTokenStorage.hasTokens).thenAnswer((_) async => true);
        when(
          () => mockAuthRepository.getCurrentUser(),
        ).thenThrow(Exception('unauthorized'));
        when(() => mockTokenStorage.clear()).thenAnswer((_) async {});
        return buildBloc();
      },
      act: (bloc) => bloc.add(const CheckAuthStatus()),
      expect: () => [const Unauthenticated()],
    );

    test(
      'a failed session check (tokens exist but getCurrentUser throws) '
      'also runs beforeLogout — not just the logout button — so sync '
      'stops promptly on that path too (PR #16 review round 1, F3)',
      () async {
        when(() => mockTokenStorage.hasTokens).thenAnswer((_) async => true);
        when(
          () => mockAuthRepository.getCurrentUser(),
        ).thenThrow(Exception('unauthorized'));
        when(() => mockTokenStorage.clear()).thenAnswer((_) async {});
        var beforeLogoutCalled = false;
        final bloc = AuthBloc(
          authRepository: mockAuthRepository,
          tokenStorage: mockTokenStorage,
          beforeLogout: () async {
            beforeLogoutCalled = true;
          },
        );
        addTearDown(bloc.close);

        bloc.add(const CheckAuthStatus());
        await bloc.stream.firstWhere((s) => s is Unauthenticated);

        expect(beforeLogoutCalled, isTrue);
      },
    );
  });

  group('LoginRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, Authenticated] on successful login',
      build: () {
        when(
          () => mockAuthRepository.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => testUser);
        return buildBloc();
      },
      act: (bloc) => bloc.add(
        const LoginRequested(email: 'test@example.com', password: 'password'),
      ),
      expect: () => [const AuthLoading(), const Authenticated(testUser)],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] on failed login, carrying the caught '
      'error object rather than a pre-rendered string — the page renders '
      'it via describeAuthError, not the bloc',
      build: () {
        when(
          () => mockAuthRepository.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenThrow(Exception('invalid credentials'));
        return buildBloc();
      },
      act: (bloc) => bloc.add(
        const LoginRequested(email: 'test@example.com', password: 'wrong'),
      ),
      expect: () => [
        const AuthLoading(),
        isA<AuthError>().having(
          (s) => s.error,
          'error',
          isA<Exception>(),
        ),
      ],
    );
  });

  group('EntraLoginRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, Authenticated] on successful Entra exchange',
      build: () {
        when(
          () => mockAuthRepository.loginWithEntra(any()),
        ).thenAnswer((_) async => testUser);
        return buildBloc();
      },
      act: (bloc) => bloc.add(
        const EntraLoginRequested(accessToken: 'entra-access-token'),
      ),
      expect: () => [const AuthLoading(), const Authenticated(testUser)],
      verify: (_) {
        verify(
          () => mockAuthRepository.loginWithEntra('entra-access-token'),
        ).called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] when the backend rejects the Entra '
      'token (e.g. entra-exchange disabled server-side, 404)',
      build: () {
        when(
          () => mockAuthRepository.loginWithEntra(any()),
        ).thenThrow(Exception('404'));
        return buildBloc();
      },
      act: (bloc) => bloc.add(
        const EntraLoginRequested(accessToken: 'entra-access-token'),
      ),
      expect: () => [const AuthLoading(), isA<AuthError>()],
    );
  });

  group('RegisterRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, Authenticated] on successful registration',
      build: () {
        when(
          () => mockAuthRepository.register(
            email: any(named: 'email'),
            password: any(named: 'password'),
            displayName: any(named: 'displayName'),
          ),
        ).thenAnswer((_) async => testUser);
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
        when(() => mockAuthRepository.logout()).thenAnswer((_) async {});
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
        when(() => mockAuthRepository.logout()).thenAnswer((_) async {});
        return buildBloc(); // no beforeLogout passed
      },
      act: (bloc) => bloc.add(const LogoutRequested()),
      expect: () => [const Unauthenticated()],
    );

    test('still logs out when beforeLogout throws — a storage/sqlite '
        'failure there must not block the user from actually logging out '
        '(PR #16 review round 1, non-blocking note)', () async {
      when(() => mockAuthRepository.logout()).thenAnswer((_) async {});
      final bloc = AuthBloc(
        authRepository: mockAuthRepository,
        tokenStorage: mockTokenStorage,
        beforeLogout: () async => throw Exception('sqlite locked'),
      );
      addTearDown(bloc.close);

      bloc.add(const LogoutRequested());
      await bloc.stream.firstWhere((s) => s is Unauthenticated);

      verify(() => mockAuthRepository.logout()).called(1);
    });
  });

  group('Diagnostics logging on auth failure', () {
    // Diagnostics.initialize/shutdown are process-wide singletons (see
    // diagnostics_test.dart), so this group owns its own temp directory
    // and drives the real writer isolate rather than faking it — there is
    // no lighter-weight interception point in Diagnostics' public API.
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('auth-diagnostics-');
      await Diagnostics.initialize(directory: directory.path);
    });

    tearDown(() async {
      await Diagnostics.shutdown();
      for (var i = 0; i < 20; i++) {
        try {
          await directory.delete(recursive: true);
          break;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
    });

    Future<String> loggedEvents() async {
      await Diagnostics.flush();
      final file = File('${directory.path}/diagnostic-0.jsonl');
      return file.existsSync() ? file.readAsString() : '';
    }

    test('a failed login is recorded as auth.login_failed', () async {
      when(
        () => mockAuthRepository.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(Exception('invalid credentials'));
      final bloc = buildBloc();
      addTearDown(bloc.close);

      bloc.add(
        const LoginRequested(email: 'test@example.com', password: 'wrong'),
      );
      await bloc.stream.firstWhere((s) => s is AuthError);

      expect(await loggedEvents(), contains('auth.login_failed'));
    });

    test('a failed registration is recorded as auth.register_failed', () async {
      when(
        () => mockAuthRepository.register(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        ),
      ).thenThrow(Exception('email already registered'));
      final bloc = buildBloc();
      addTearDown(bloc.close);

      bloc.add(
        const RegisterRequested(
          email: 'test@example.com',
          password: 'password123',
          displayName: 'Test User',
        ),
      );
      await bloc.stream.firstWhere((s) => s is AuthError);

      expect(await loggedEvents(), contains('auth.register_failed'));
    });

    test('a failed Entra exchange is recorded as auth.entra_login_failed', () async {
      when(
        () => mockAuthRepository.loginWithEntra(any()),
      ).thenThrow(Exception('404'));
      final bloc = buildBloc();
      addTearDown(bloc.close);

      bloc.add(const EntraLoginRequested(accessToken: 'entra-access-token'));
      await bloc.stream.firstWhere((s) => s is AuthError);

      expect(await loggedEvents(), contains('auth.entra_login_failed'));
    });
  });
}

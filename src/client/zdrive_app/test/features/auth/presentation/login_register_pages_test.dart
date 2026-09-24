import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/auth/auth_bloc.dart';
import 'package:zdrive_app/core/auth/entra_native_sign_in.dart';
import 'package:zdrive_app/core/auth/entra_token_exchange.dart';
import 'package:zdrive_app/features/auth/presentation/login_page.dart';
import 'package:zdrive_app/features/auth/presentation/register_page.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';
import 'package:zdrive_app/shared/theme/app_theme.dart';
import 'package:zdrive_app/shared/widgets/brand_lockup.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

/// Stands in for a real Entra token exchange in the success-path test below
/// — a real EntraTokenExchange would hit Entra's actual token endpoint.
class _FakeEntraTokenExchange extends EntraTokenExchange {
  @override
  Future<EntraTokenResult> exchangeCodeForNativeTokens({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async => const EntraTokenResult(
    accessToken: 'native-access-token',
    refreshToken: 'native-refresh-token',
  );
}

void main() {
  late MockAuthBloc authBloc;

  setUpAll(() {
    registerFallbackValue(const CheckAuthStatus());
  });

  setUp(() {
    authBloc = MockAuthBloc();
    // Default: idle, unauthenticated-adjacent state so pages render their
    // normal (non-loading, non-error) form.
    whenListen(
      authBloc,
      const Stream<AuthState>.empty(),
      initialState: const AuthInitial(),
    );
  });

  // A router is needed because both pages call context.go() for navigation
  // links (login<->register); GoRouter is the app's real router so this
  // matches production wiring instead of stubbing go_router out.
  Widget build(Widget page) {
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(path: '/login', builder: (context, state) => page),
        GoRoute(path: '/register', builder: (context, state) => page),
      ],
    );
    return BlocProvider<AuthBloc>.value(
      value: authBloc,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
      ),
    );
  }

  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('LoginPage', () {
    testWidgets('narrow screen stacks the lockup above a single form column', (
      tester,
    ) async {
      await setSize(tester, const Size(400, 800));

      await tester.pumpWidget(build(const LoginPage()));
      await tester.pumpAndSettle();

      expect(find.byType(BrandLockup), findsOneWidget);
      // No brand-panel Container (petrol fill) at this width.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container && widget.color == AppTheme.brandPetrol,
        ),
        findsNothing,
      );
    });

    testWidgets(
      'wide screen shows the petrol brand panel and the form side by side',
      (tester) async {
        await setSize(tester, const Size(1200, 800));

        await tester.pumpWidget(build(const LoginPage()));
        await tester.pumpAndSettle();

        // Exactly one BrandLockup: the brand panel's (mono). The form column
        // no longer repeats it (bug: brand appeared twice in the wide layout).
        expect(find.byType(BrandLockup), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.color == AppTheme.brandPetrol,
          ),
          findsOneWidget,
        );
        expect(find.byType(TextFormField), findsNWidgets(2));

        // The panel lockup must be the monochrome (white wordmark) variant —
        // the default variant uses onSurface, which is close to black and
        // would be unreadable on the petrol fill.
        final panelLockup = tester.widget<BrandLockup>(
          find.byType(BrandLockup),
        );
        expect(panelLockup.monochrome, isTrue);
        final wordmark = tester.widget<Text>(
          find.descendant(
            of: find.byType(BrandLockup),
            matching: find.text('zDrive'),
          ),
        );
        expect(wordmark.style?.color, Colors.white);
      },
    );

    testWidgets('loading state disables the button and shows progress', (
      tester,
    ) async {
      whenListen(
        authBloc,
        const Stream<AuthState>.empty(),
        initialState: const AuthLoading(),
      );

      await tester.pumpWidget(build(const LoginPage()));
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('error state renders the message', (tester) async {
      whenListen(
        authBloc,
        const Stream<AuthState>.empty(),
        initialState: const AuthError('Invalid credentials'),
      );

      await tester.pumpWidget(build(const LoginPage()));
      await tester.pump();

      expect(find.text('Invalid credentials'), findsOneWidget);
    });

    testWidgets('Enter in the password field submits exactly once when idle', (
      tester,
    ) async {
      await tester.pumpWidget(build(const LoginPage()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'user@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'longenoughpassword',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      verify(
        () => authBloc.add(
          const LoginRequested(
            email: 'user@example.com',
            password: 'longenoughpassword',
          ),
        ),
      ).called(1);
    });

    testWidgets(
      'Enter in the password field dispatches nothing while loading',
      (tester) async {
        whenListen(
          authBloc,
          const Stream<AuthState>.empty(),
          initialState: const AuthLoading(),
        );

        await tester.pumpWidget(build(const LoginPage()));
        // Not pumpAndSettle: AuthLoading renders an indeterminate
        // CircularProgressIndicator, which animates forever.
        await tester.pump();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'),
          'user@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'),
          'longenoughpassword',
        );
        // The button is already disabled by AuthLoading; Enter is the second
        // entry point that must be guarded the same way (SHOULD-FIX review
        // finding: a second Enter mid-request used to dispatch a duplicate
        // LoginRequested).
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        verifyNever(() => authBloc.add(any()));
      },
    );

    testWidgets('has a heading distinguishing it from the register page', (
      tester,
    ) async {
      await tester.pumpWidget(build(const LoginPage()));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(tester.element(find.byType(LoginPage)))!;
      expect(find.text(l10n.login), findsOneWidget);
    });

    testWidgets('320px + 200% text scaling does not overflow', (tester) async {
      await setSize(tester, const Size(320, 700));
      // MaterialApp.router rebuilds MediaQuery from the test view rather
      // than an ancestor MediaQuery, so text scale is set on the view/
      // platform dispatcher, not by wrapping the tree.
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(build(const LoginPage()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    // Real gate is kEntraSignInVisible (computeEntraSignInVisible — needs
    // both a client id/scope AND an eligible platform, see
    // entra_config.dart) — always false in a `flutter test` run since no
    // client id is passed. `entraSignInVisible` threads that same pure
    // boolean through as a param instead, so both branches are exercisable
    // here without any browser/platform-channel test infra.
    testWidgets('Entra sign-in button is hidden by default (no client id '
        'configured — the default build)', (tester) async {
      await tester.pumpWidget(build(const LoginPage()));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(tester.element(find.byType(LoginPage)))!;
      expect(find.text(l10n.entraSignInButton), findsNothing);
    });

    testWidgets('Entra sign-in button shows once entraSignInVisible is true', (
      tester,
    ) async {
      await tester.pumpWidget(build(const LoginPage(entraSignInVisible: true)));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(tester.element(find.byType(LoginPage)))!;
      expect(find.text(l10n.entraSignInButton), findsOneWidget);
    });

    // A real EntraNativeSignIn calls the actual flutter_web_auth_2 platform
    // channel, which never replies in a plain `flutter_test` run (no native
    // implementation registered) — the underlying Future would simply hang
    // forever rather than throw, so these all fake the browser step via
    // LoginPage.entraNativeSignInFactory (Opus review of PR #72, finding 2
    // caught the previous version of this test asserting nothing, since it
    // never actually exercised the catch branches below).
    Future<void> tapEntraSignIn(
      WidgetTester tester,
      EntraNativeSignIn Function() factory,
    ) async {
      await tester.pumpWidget(
        build(
          LoginPage(entraSignInVisible: true, entraNativeSignInFactory: factory),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(tester.element(find.byType(LoginPage)))!;
      await tester.tap(find.text(l10n.entraSignInButton));
      await tester.pumpAndSettle();
    }

    testWidgets('success: dispatches EntraLoginRequested with both tokens', (
      tester,
    ) async {
      await tapEntraSignIn(
        tester,
        () => EntraNativeSignIn(
          tokenExchange: _FakeEntraTokenExchange(),
          authenticate: ({required url, required callbackUrlScheme, required options}) async {
            final state = Uri.parse(url).queryParameters['state'];
            return 'cz.zcloud.zdrive://auth?code=auth-code&state=$state';
          },
        ),
      );

      expect(tester.takeException(), isNull);
      verify(
        () => authBloc.add(
          const EntraLoginRequested(
            accessToken: 'native-access-token',
            entraRefreshToken: 'native-refresh-token',
          ),
        ),
      ).called(1);
    });

    testWidgets('Entra `error=` (denied consent) shows the denial message, '
        'not the state-mismatch one — Opus review of PR #72, finding 5', (
      tester,
    ) async {
      await tapEntraSignIn(
        tester,
        () => EntraNativeSignIn(
          authenticate: ({required url, required callbackUrlScheme, required options}) async =>
              'cz.zcloud.zdrive://auth?error=access_denied',
        ),
      );

      final l10n = AppLocalizations.of(tester.element(find.byType(LoginPage)))!;
      expect(tester.takeException(), isNull);
      expect(find.text(l10n.entraSignInDenied), findsOneWidget);
      verifyNever(() => authBloc.add(any(that: isA<EntraLoginRequested>())));
    });

    testWidgets('CSRF state mismatch shows the state-mismatch message', (
      tester,
    ) async {
      await tapEntraSignIn(
        tester,
        () => EntraNativeSignIn(
          authenticate: ({required url, required callbackUrlScheme, required options}) async =>
              'cz.zcloud.zdrive://auth?code=auth-code&state=attacker',
        ),
      );

      final l10n = AppLocalizations.of(tester.element(find.byType(LoginPage)))!;
      expect(tester.takeException(), isNull);
      expect(find.text(l10n.entraStateMismatch), findsOneWidget);
      verifyNever(() => authBloc.add(any(that: isA<EntraLoginRequested>())));
    });

    testWidgets('user cancels the browser sheet (PlatformException code '
        'CANCELED): no error shown, per ADR 0003\'s failure modes', (
      tester,
    ) async {
      await tapEntraSignIn(
        tester,
        () => EntraNativeSignIn(
          authenticate: ({required url, required callbackUrlScheme, required options}) async =>
              throw PlatformException(code: 'CANCELED'),
        ),
      );

      final l10n = AppLocalizations.of(tester.element(find.byType(LoginPage)))!;
      expect(tester.takeException(), isNull);
      expect(find.text(l10n.entraSignInDenied), findsNothing);
      expect(find.text(l10n.entraStateMismatch), findsNothing);
      expect(find.text(l10n.errorRequestFailed), findsNothing);
      verifyNever(() => authBloc.add(any(that: isA<EntraLoginRequested>())));
    });

    testWidgets('any OTHER failure (e.g. Windows loopback port already in '
        'use, a missing platform channel) shows a readable error instead of '
        'swallowing it — Opus review of PR #72, finding 2', (tester) async {
      await tapEntraSignIn(
        tester,
        () => EntraNativeSignIn(
          authenticate: ({required url, required callbackUrlScheme, required options}) async =>
              throw PlatformException(code: 'channel-error', message: 'port in use'),
        ),
      );

      final l10n = AppLocalizations.of(tester.element(find.byType(LoginPage)))!;
      expect(tester.takeException(), isNull);
      expect(find.text(l10n.errorRequestFailed), findsOneWidget);
      verifyNever(() => authBloc.add(any(that: isA<EntraLoginRequested>())));
    });
  });

  group('RegisterPage', () {
    testWidgets('email required / short password validation still fires', (
      tester,
    ) async {
      await setSize(tester, const Size(400, 900));
      await tester.pumpWidget(build(const RegisterPage()));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(RegisterPage)),
      )!;
      expect(find.text(l10n.emailRequired), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.password),
        'short',
      );
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(find.text(l10n.passwordTooShort), findsOneWidget);
    });

    testWidgets('has a heading distinguishing it from the login page', (
      tester,
    ) async {
      await tester.pumpWidget(build(const RegisterPage()));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(RegisterPage)),
      )!;
      expect(find.text(l10n.register), findsOneWidget);
    });

    testWidgets('320px + 200% text scaling does not overflow', (tester) async {
      await setSize(tester, const Size(320, 700));
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(build(const RegisterPage()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}

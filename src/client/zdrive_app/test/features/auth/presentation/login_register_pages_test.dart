import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/auth/auth_bloc.dart';
import 'package:zdrive_app/features/auth/presentation/login_page.dart';
import 'package:zdrive_app/features/auth/presentation/register_page.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';
import 'package:zdrive_app/shared/widgets/brand_lockup.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

void main() {
  late MockAuthBloc authBloc;

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
    testWidgets('narrow screen stacks the lockup above a single form column',
        (tester) async {
      await setSize(tester, const Size(400, 800));

      await tester.pumpWidget(build(const LoginPage()));
      await tester.pumpAndSettle();

      expect(find.byType(BrandLockup), findsOneWidget);
      // No brand-panel Container (petrol fill) at this width.
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Container && widget.color == const Color(0xFF003840),
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

      // Two BrandLockups: one in the brand panel (mono), one above the form.
      expect(find.byType(BrandLockup), findsNWidgets(2));
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Container && widget.color == const Color(0xFF003840),
        ),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNWidgets(2));
    });

    testWidgets('loading state disables the button and shows progress',
        (tester) async {
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

    testWidgets('Enter in the password field submits once', (tester) async {
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
  });

  group('RegisterPage', () {
    testWidgets('email required / short password validation still fires',
        (tester) async {
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
  });
}

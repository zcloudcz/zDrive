import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/auth/auth_bloc.dart';
import 'package:zdrive_app/core/auth/entra_sign_in.dart';
import 'package:zdrive_app/core/auth/entra_token_exchange.dart';
import 'package:zdrive_app/features/auth/presentation/entra_callback_page.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class MockEntraTokenExchange extends Mock implements EntraTokenExchange {}

/// consumeVerifierIfStateMatches is the only method the page calls — a
/// fixed return value stands in for a real sessionStorage round-trip
/// (already covered by entra_sign_in_test.dart).
class FakeEntraSignIn extends EntraSignIn {
  FakeEntraSignIn(this._verifier);
  final String? _verifier;

  @override
  String? consumeVerifierIfStateMatches(String? returnedState) => _verifier;
}

void main() {
  late MockAuthBloc authBloc;
  late MockEntraTokenExchange tokenExchange;

  setUpAll(() {
    registerFallbackValue(const CheckAuthStatus());
  });

  setUp(() {
    authBloc = MockAuthBloc();
    tokenExchange = MockEntraTokenExchange();
    whenListen(
      authBloc,
      const Stream<AuthState>.empty(),
      initialState: const AuthInitial(),
    );
  });

  Widget build(Widget page) {
    final router = GoRouter(
      initialLocation: '/auth/entra-callback',
      routes: [
        GoRoute(
          path: '/auth/entra-callback',
          builder: (context, state) => page,
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const SizedBox.shrink(),
        ),
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

  testWidgets('success: valid code + matching state exchanges the code and '
      'dispatches EntraLoginRequested with the resulting access token', (
    tester,
  ) async {
    when(
      () => tokenExchange.exchangeCodeForAccessToken(
        code: any(named: 'code'),
        codeVerifier: any(named: 'codeVerifier'),
      ),
    ).thenAnswer((_) async => 'backend-access-token');

    await tester.pumpWidget(
      build(
        EntraCallbackPage(
          code: 'auth-code',
          error: null,
          returnedState: 'returned-state',
          signIn: FakeEntraSignIn('the-verifier'),
          tokenExchange: tokenExchange,
        ),
      ),
    );
    // Not pumpAndSettle: this success case never leaves the page (AuthBloc
    // is mocked, so no Authenticated state ever arrives to navigate away),
    // and the loading spinner it shows meanwhile is an indeterminate
    // CircularProgressIndicator, which animates forever.
    await tester.pump();
    await tester.pump();

    verify(
      () => tokenExchange.exchangeCodeForAccessToken(
        code: 'auth-code',
        codeVerifier: 'the-verifier',
      ),
    ).called(1);
    verify(
      () => authBloc.add(
        const EntraLoginRequested(accessToken: 'backend-access-token'),
      ),
    ).called(1);
  });

  testWidgets('state mismatch: rejected before the token exchange ever runs '
      '(CSRF check)', (tester) async {
    await tester.pumpWidget(
      build(
        EntraCallbackPage(
          code: 'auth-code',
          error: null,
          returnedState: 'attacker-state',
          signIn: FakeEntraSignIn(
            null,
          ), // simulates consumeVerifierIfStateMatches rejecting
          tokenExchange: tokenExchange,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(EntraCallbackPage)),
    )!;
    expect(find.text(l10n.entraStateMismatch), findsOneWidget);
    verifyNever(
      () => tokenExchange.exchangeCodeForAccessToken(
        code: any(named: 'code'),
        codeVerifier: any(named: 'codeVerifier'),
      ),
    );
    verifyNever(() => authBloc.add(any(that: isA<EntraLoginRequested>())));
  });

  testWidgets('Entra denial: an `error` query param shows a readable message '
      'and never reaches the token exchange', (tester) async {
    await tester.pumpWidget(
      build(
        EntraCallbackPage(
          code: null,
          error: 'access_denied',
          returnedState: null,
          signIn: FakeEntraSignIn('unused'),
          tokenExchange: tokenExchange,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(EntraCallbackPage)),
    )!;
    expect(find.text(l10n.entraSignInDenied), findsOneWidget);
    verifyNever(
      () => tokenExchange.exchangeCodeForAccessToken(
        code: any(named: 'code'),
        codeVerifier: any(named: 'codeVerifier'),
      ),
    );
    verifyNever(() => authBloc.add(any(that: isA<EntraLoginRequested>())));
  });

  testWidgets('token endpoint failure surfaces a readable error instead of '
      'silently failing', (tester) async {
    when(
      () => tokenExchange.exchangeCodeForAccessToken(
        code: any(named: 'code'),
        codeVerifier: any(named: 'codeVerifier'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/oauth2/v2.0/token'),
        type: DioExceptionType.connectionError,
      ),
    );

    await tester.pumpWidget(
      build(
        EntraCallbackPage(
          code: 'auth-code',
          error: null,
          returnedState: 'returned-state',
          signIn: FakeEntraSignIn('the-verifier'),
          tokenExchange: tokenExchange,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(EntraCallbackPage)),
    )!;
    expect(find.text(l10n.errorNoConnection), findsOneWidget);
    verifyNever(() => authBloc.add(any(that: isA<EntraLoginRequested>())));
  });
}

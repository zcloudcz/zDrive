import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../../core/auth/auth_bloc.dart';
import '../../../core/auth/entra_sign_in.dart';
import '../../../core/auth/entra_token_exchange.dart';
import '../../../core/network/error_message.dart';
import 'widgets/auth_scaffold.dart';

/// What went wrong before AuthBloc ever got involved — everything here
/// happens client-side (Entra denial, CSRF check, the code<->token
/// exchange), so it needs its own local error state distinct from
/// [AuthError]. Kept as raw signals rather than pre-localized strings: an
/// [AppLocalizations] lookup during [State.initState] hits an inherited
/// widget before its dependency is fully wired up, so localizing happens in
/// [State.build] instead (see `_localError` below).
enum _CallbackFailure {
  entraDenied,
  stateMismatch,
  missingCode,
  exchangeFailed,
}

/// Lands here after Entra's hosted sign-in page redirects back. `redirect_uri`
/// is this app's plain origin (see `entra_config.dart`'s `entraRedirectUri`);
/// `app_router.dart`'s `redirect` callback forwards the real URL's query
/// string into this in-app hash route.
///
/// Runs the parts of the PKCE flow that only make sense once, back on this
/// page: verify Entra didn't report an error, check the returned `state`
/// against what EntraSignIn.beginSignIn stashed (CSRF), exchange the code
/// for an access token, then hand that token to AuthBloc — which reuses the
/// normal login states from there (AuthLoading/Authenticated/AuthError).
class EntraCallbackPage extends StatefulWidget {
  const EntraCallbackPage({
    super.key,
    required this.code,
    required this.error,
    required this.returnedState,
    this.signIn = const EntraSignIn(),
    EntraTokenExchange? tokenExchange,
  }) : _tokenExchange = tokenExchange;

  /// `code` query parameter — present on a successful Entra redirect.
  final String? code;

  /// `error` query parameter — present when the user denied consent or
  /// Entra otherwise refused to issue a code.
  final String? error;

  /// `state` query parameter, to check against what was stashed before the
  /// redirect to Entra.
  final String? returnedState;

  final EntraSignIn signIn;
  final EntraTokenExchange? _tokenExchange;

  @override
  State<EntraCallbackPage> createState() => _EntraCallbackPageState();
}

class _EntraCallbackPageState extends State<EntraCallbackPage> {
  _CallbackFailure? _failure;
  DioException? _exchangeError;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (widget.error != null) {
      setState(() => _failure = _CallbackFailure.entraDenied);
      return;
    }
    final code = widget.code;
    if (code == null) {
      setState(() => _failure = _CallbackFailure.missingCode);
      return;
    }
    final verifier = widget.signIn.consumeVerifierIfStateMatches(
      widget.returnedState,
    );
    if (verifier == null) {
      setState(() => _failure = _CallbackFailure.stateMismatch);
      return;
    }
    try {
      final tokenExchange = widget._tokenExchange ?? EntraTokenExchange();
      final accessToken = await tokenExchange.exchangeCodeForAccessToken(
        code: code,
        codeVerifier: verifier,
      );
      if (!mounted) return;
      context.read<AuthBloc>().add(
        EntraLoginRequested(accessToken: accessToken),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = _CallbackFailure.exchangeFailed;
        _exchangeError = e;
      });
    } on EntraTokenExchangeException {
      if (!mounted) return;
      setState(() => _failure = _CallbackFailure.exchangeFailed);
    }
  }

  String? _localErrorMessage(AppLocalizations l10n) {
    switch (_failure) {
      case null:
        return null;
      case _CallbackFailure.entraDenied:
        return l10n.entraSignInDenied;
      case _CallbackFailure.stateMismatch:
        return l10n.entraStateMismatch;
      case _CallbackFailure.missingCode:
        return l10n.errorRequestFailed;
      case _CallbackFailure.exchangeFailed:
        return _exchangeError != null
            ? describeError(_exchangeError!, l10n)
            : l10n.errorRequestFailed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final message = _localErrorMessage(l10n);
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        // Combine local failures (denial, CSRF, code exchange) with a
        // failure AuthBloc reports once it got as far as calling the
        // backend (e.g. Entra:Enabled=false -> 404). Either way, once
        // there's an error there must be a way out: round-1 review of
        // PR #70 found a bloc-originated error left the page stuck with no
        // back button, since only the local `message` gated it before.
        final text = message ?? (state is AuthError ? state.message : null);
        return AuthScaffold(
          appBar: text == null
              ? null
              : AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.go('/login'),
                  ),
                ),
          child: text != null
              ? Text(
                  text,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                )
              : const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

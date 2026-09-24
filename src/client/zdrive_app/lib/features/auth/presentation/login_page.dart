import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_bloc.dart';
import '../../../core/auth/entra_config.dart';
import '../../../core/auth/entra_native_sign_in.dart';
import '../../../core/auth/entra_sign_in.dart';
import '../../../core/auth/entra_token_exchange.dart';
import '../../../core/network/error_message.dart';
import '../../../shared/widgets/windows_download_button.dart';
import 'widgets/auth_scaffold.dart';

/// What went wrong in the native (ADR 0003) sign-in step, before AuthBloc
/// ever got involved — mirrors `_CallbackFailure` in EntraCallbackPage
/// (web's equivalent). `authFailed` covers both Entra's `error=` (denied
/// consent) and the CSRF state-mismatch check: either way sign-in did not
/// complete, and one message is enough for both (per ADR 0003: "same
/// handling as web").
enum _EntraNativeFailure { authFailed, exchangeFailed }

class LoginPage extends StatefulWidget {
  // Left null by default so the real gate (kEntraSignInVisible, resolved at
  // runtime — see entra_config.dart) applies; threaded in as a param so a
  // widget test can force either branch without depending on the current
  // platform. `bool?` rather than a `bool` default: kEntraSignInVisible is
  // no longer `const` (ADR 0003 needs a runtime platform check), and a
  // default parameter value must be a compile-time constant.
  const LoginPage({super.key, this.entraSignInVisible});

  final bool? entraSignInVisible;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Native (ADR 0003) sign-in errors happen entirely client-side, before
  // AuthBloc is ever involved (Entra denial, CSRF state mismatch, the
  // code<->token exchange) — same reasoning as EntraCallbackPage's
  // _CallbackFailure, kept local rather than routed through AuthBloc.
  _EntraNativeFailure? _entraFailure;
  DioException? _entraExchangeError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _onEntraSignIn() async {
    if (kIsWeb) {
      const EntraSignIn().beginSignIn();
      return;
    }
    setState(() {
      _entraFailure = null;
      _entraExchangeError = null;
    });
    try {
      final result = await EntraNativeSignIn().signIn();
      if (!mounted) return;
      context.read<AuthBloc>().add(
        EntraLoginRequested(
          accessToken: result.accessToken,
          entraRefreshToken: result.refreshToken,
        ),
      );
    } on EntraNativeSignInException {
      if (!mounted) return;
      setState(() => _entraFailure = _EntraNativeFailure.authFailed);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _entraFailure = _EntraNativeFailure.exchangeFailed;
        _entraExchangeError = e;
      });
    } on EntraTokenExchangeException {
      if (!mounted) return;
      setState(() => _entraFailure = _EntraNativeFailure.exchangeFailed);
    } catch (_) {
      // flutter_web_auth_2 throws a plain PlatformException(code: CANCELED)
      // when the user dismisses the browser sheet — back to the login page
      // with no error, per ADR 0003's failure modes, same as web treats a
      // user simply not completing the redirect.
    }
  }

  void _onSubmit() {
    // Guard here, not just at the button's onPressed: onFieldSubmitted
    // (Enter/Done in the password field) is a second entry point that
    // doesn't get disabled while a request is in flight, so without this
    // check pressing Enter again during AuthLoading fired a second
    // LoginRequested.
    if (context.read<AuthBloc>().state is AuthLoading) {
      return;
    }
    if (_formKey.currentState!.validate()) {
      context.read<AuthBloc>().add(
        LoginRequested(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        ),
      );
    }
  }

  String? _entraErrorMessage(AppLocalizations l10n) {
    switch (_entraFailure) {
      case null:
        return null;
      case _EntraNativeFailure.authFailed:
        return l10n.entraStateMismatch;
      case _EntraNativeFailure.exchangeFailed:
        return _entraExchangeError != null
            ? describeError(_entraExchangeError!, l10n)
            : l10n.errorRequestFailed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final entraSignInVisible = widget.entraSignInVisible ?? kEntraSignInVisible;

    return AuthScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.login,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: InputDecoration(
                labelText: l10n.email,
                prefixIcon: const Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l10n.emailRequired;
                }
                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(value.trim())) {
                  return l10n.invalidEmail;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: l10n.password,
                prefixIcon: const Icon(Icons.lock_outlined),
              ),
              obscureText: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              // Enter/Done on desktop and soft keyboards submits the form,
              // matching the button below (spec 4.5 keyboard requirements).
              // _onSubmit itself guards against a duplicate submit while
              // AuthLoading, since this is a second entry point besides the
              // button.
              onFieldSubmitted: (_) => _onSubmit(),
              validator: (value) {
                if (value == null || value.length < 8) {
                  return l10n.passwordTooShort;
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            // Reserves space for the error line so it appears without
            // shifting the fields/button below it (spec 4.5 "error message
            // area that does not shift layout"). This is the only error
            // surface now — a SnackBar here would just repeat it.
            BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                // Merge AuthBloc's error (email/password, or the backend
                // leg of native Entra sign-in) with a native-flow error
                // that never reaches AuthBloc (cancelled/denied/CSRF) — see
                // entra_callback_page.dart's web equivalent of this merge.
                final message =
                    _entraErrorMessage(l10n) ??
                    (state is AuthError ? state.message : null);
                return ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 20),
                  child: message == null
                      ? null
                      : Text(
                          message,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                );
              },
            ),
            const SizedBox(height: 8),
            BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                final isLoading = state is AuthLoading;
                return SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: isLoading ? null : _onSubmit,
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.loginButton),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.go('/register'),
              child: Text(l10n.createAccount),
            ),
            if (entraSignInVisible) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _onEntraSignIn,
                  child: Text(l10n.entraSignInButton),
                ),
              ),
            ],
            const Divider(height: 32),
            const WindowsDownloadButton(),
          ],
        ),
      ),
    );
  }
}

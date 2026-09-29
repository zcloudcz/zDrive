import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../../../core/auth/auth_bloc.dart';
import '../../../../core/network/error_message.dart';

/// Second step of a 2FA login, shown inline by LoginPage while AuthBloc is in
/// [AuthTwoFactorRequired]: a 6-digit authenticator code, or — via the link
/// below the field — a one-time recovery code.
class TwoFactorStep extends StatefulWidget {
  const TwoFactorStep({super.key, required this.state});

  final AuthTwoFactorRequired state;

  @override
  State<TwoFactorStep> createState() => _TwoFactorStepState();
}

class _TwoFactorStepState extends State<TwoFactorStep> {
  final _controller = TextEditingController();
  bool _useRecoveryCode = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty || widget.state.submitting) return;
    context.read<AuthBloc>().add(
      _useRecoveryCode
          ? TwoFactorCodeSubmitted(recoveryCode: value)
          : TwoFactorCodeSubmitted(code: value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final error = widget.state.error;
    final submitting = widget.state.submitting;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.twoFactorTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _useRecoveryCode ? l10n.twoFactorRecoveryPrompt : l10n.twoFactorPrompt,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        TextField(
          // A new key per mode so switching clears the field and its keyboard.
          key: ValueKey(_useRecoveryCode),
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: _useRecoveryCode
                ? l10n.twoFactorRecoveryCodeLabel
                : l10n.twoFactorCodeLabel,
            prefixIcon: const Icon(Icons.shield_outlined),
          ),
          keyboardType: _useRecoveryCode
              ? TextInputType.text
              : TextInputType.number,
          inputFormatters: _useRecoveryCode
              ? null
              : [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
          autofillHints: const [AutofillHints.oneTimeCode],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 20),
          child: error == null
              ? null
              : Text(
                  describeAuthError(error, l10n),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: submitting ? null : _submit,
            child: submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.twoFactorVerifyButton),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: submitting
              ? null
              : () => setState(() {
                  _useRecoveryCode = !_useRecoveryCode;
                  _controller.clear();
                }),
          child: Text(
            _useRecoveryCode
                ? l10n.twoFactorUseAuthenticator
                : l10n.twoFactorUseRecoveryCode,
          ),
        ),
        TextButton(
          onPressed: submitting
              ? null
              : () => context.read<AuthBloc>().add(const TwoFactorCancelled()),
          child: Text(l10n.twoFactorBackToSignIn),
        ),
      ],
    );
  }
}

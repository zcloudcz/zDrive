import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../../core/network/error_message.dart';
import 'two_factor_cubit.dart';

/// Turn TOTP two-factor authentication on or off (account menu). Enrollment:
/// QR code + manual key, confirm with a code, then the one-time recovery
/// codes. Needs a [TwoFactorCubit] above it.
class TwoFactorSettingsPage extends StatelessWidget {
  const TwoFactorSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.twoFactorTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: BlocBuilder<TwoFactorCubit, TwoFactorState>(
                builder: (context, state) => switch (state) {
                  TwoFactorLoading() => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  TwoFactorLoadFailed(:final error) => _LoadFailed(error: error),
                  TwoFactorUnavailable() => Text(l10n.twoFactorUnavailable),
                  TwoFactorOff() => _Off(state: state),
                  TwoFactorEnrolling() => _Enrolling(state: state),
                  TwoFactorRecoveryCodes() => _RecoveryCodes(state: state),
                  TwoFactorOn() => _On(state: state),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.error);

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 20),
      child: error == null
          ? null
          : Text(
              describeAuthError(error!, l10n),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 20,
    width: 20,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

Future<void> _copy(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.of(context);
  final copied = AppLocalizations.of(context)!.twoFactorCopied;
  await Clipboard.setData(ClipboardData(text: text));
  messenger.showSnackBar(SnackBar(content: Text(copied)));
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(describeError(error, l10n)),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => context.read<TwoFactorCubit>().load(),
          child: Text(l10n.retry),
        ),
      ],
    );
  }
}

class _Off extends StatefulWidget {
  const _Off({required this.state});

  final TwoFactorOff state;

  @override
  State<_Off> createState() => _OffState();
}

class _OffState extends State<_Off> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.isEmpty || widget.state.busy) return;
    context.read<TwoFactorCubit>().beginSetup(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.twoFactorStatusOff),
        const SizedBox(height: 16),
        Text(l10n.twoFactorEnablePasswordInfo),
        const SizedBox(height: 16),
        TextField(
          controller: _password,
          decoration: InputDecoration(
            labelText: l10n.password,
            prefixIcon: const Icon(Icons.lock_outlined),
          ),
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        _ErrorLine(widget.state.error),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: widget.state.busy ? null : _submit,
          child: widget.state.busy ? const _Busy() : Text(l10n.twoFactorEnable),
        ),
      ],
    );
  }
}

class _Enrolling extends StatefulWidget {
  const _Enrolling({required this.state});

  final TwoFactorEnrolling state;

  @override
  State<_Enrolling> createState() => _EnrollingState();
}

class _EnrollingState extends State<_Enrolling> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _code.text.trim();
    if (code.length != 6 || widget.state.busy) return;
    context.read<TwoFactorCubit>().confirm(code);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final setup = widget.state.setup;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.twoFactorSetupInstructions),
        const SizedBox(height: 16),
        Center(
          // Light background whatever the theme: dark-on-dark QR codes do not
          // scan.
          child: QrImageView(
            data: setup.otpAuthUri,
            size: 200,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.twoFactorSetupKey,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        Row(
          children: [
            Expanded(child: SelectableText(setup.secret)),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: l10n.twoFactorCopy,
              onPressed: () => _copy(context, setup.secret),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _code,
          decoration: InputDecoration(
            labelText: l10n.twoFactorCodeLabel,
            prefixIcon: const Icon(Icons.shield_outlined),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        _ErrorLine(widget.state.error),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: widget.state.busy ? null : _submit,
          child: widget.state.busy
              ? const _Busy()
              : Text(l10n.twoFactorConfirmButton),
        ),
      ],
    );
  }
}

class _RecoveryCodes extends StatelessWidget {
  const _RecoveryCodes({required this.state});

  final TwoFactorRecoveryCodes state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.twoFactorRecoveryCodesTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.twoFactorRecoveryCodesInfo),
        const SizedBox(height: 16),
        Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            for (final code in state.codes)
              SelectableText(
                code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy),
          label: Text(l10n.twoFactorCopyCodes),
          onPressed: () => _copy(context, state.codes.join('\n')),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => context.read<TwoFactorCubit>().finishEnrollment(),
          child: Text(l10n.twoFactorDone),
        ),
      ],
    );
  }
}

class _On extends StatefulWidget {
  const _On({required this.state});

  final TwoFactorOn state;

  @override
  State<_On> createState() => _OnState();
}

class _OnState extends State<_On> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _showForm = false;

  @override
  void initState() {
    super.initState();
    // A failed disable comes back as a fresh TwoFactorOn(error): keep the
    // form open so the user can correct it.
    _showForm = widget.state.error != null;
  }

  @override
  void dispose() {
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.isEmpty || _code.text.trim().isEmpty) return;
    context.read<TwoFactorCubit>().disable(
      password: _password.text,
      code: _code.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final busy = widget.state.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.verified_user_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text(l10n.twoFactorStatusOn)),
          ],
        ),
        const SizedBox(height: 16),
        if (!_showForm)
          OutlinedButton(
            onPressed: () => setState(() => _showForm = true),
            child: Text(l10n.twoFactorDisable),
          )
        else ...[
          Text(l10n.twoFactorDisableInfo),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            decoration: InputDecoration(
              labelText: l10n.password,
              prefixIcon: const Icon(Icons.lock_outlined),
            ),
            obscureText: true,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            decoration: InputDecoration(
              labelText: l10n.twoFactorCodeLabel,
              prefixIcon: const Icon(Icons.shield_outlined),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          _ErrorLine(widget.state.error),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: busy ? null : _submit,
            child: busy ? const _Busy() : Text(l10n.twoFactorDisableConfirm),
          ),
        ],
      ],
    );
  }
}

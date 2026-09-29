import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/app_localizations.dart';
import 'diagnostic_export.dart';
import '../../core/diagnostics/diagnostics.dart';

class AppSettingsMenu extends StatefulWidget {
  const AppSettingsMenu({
    super.key,
    this.exportDiagnostics = exportDiagnosticFile,
    this.onTwoFactorSettings,
  });
  final Future<bool> Function() exportDiagnostics;

  /// Opens the 2FA settings page. Null hides the item (accounts without a
  /// local password have no 2FA setup).
  final VoidCallback? onTwoFactorSettings;

  @override
  State<AppSettingsMenu> createState() => _AppSettingsMenuState();
}

class _AppSettingsMenuState extends State<AppSettingsMenu> {
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.settings_outlined),
      tooltip: l10n.settings,
      onSelected: (action) async {
        if (action == 'two_factor') {
          widget.onTwoFactorSettings?.call();
        } else if (action == 'about') {
          showDialog<void>(
            context: context,
            builder: (_) => const _AppAboutDialog(),
          );
        } else if (action == 'logs') {
          if (_exporting) return;
          setState(() => _exporting = true);
          final messenger = ScaffoldMessenger.of(context);
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.diagnosticsPreparing)),
          );
          try {
            final saved = await widget.exportDiagnostics();
            if (!mounted) return;
            messenger.hideCurrentSnackBar();
            if (saved) {
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.diagnosticsSaved)),
              );
            }
          } catch (error, stack) {
            Diagnostics.error('diagnostics.export.failed', error, stack);
            if (!mounted) return;
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.diagnosticsFailed)),
            );
          } finally {
            if (mounted) setState(() => _exporting = false);
          }
        } else {
          Diagnostics.event('app.exit.requested');
          try {
            await Diagnostics.flush();
            await const MethodChannel(
              'zdrive/windows_lifecycle',
            ).invokeMethod<void>('quit');
          } on PlatformException {
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l10n.exitFailed)));
            }
          }
        }
      },
      itemBuilder: (_) => [
        if (widget.onTwoFactorSettings != null)
          PopupMenuItem(value: 'two_factor', child: Text(l10n.twoFactorTitle)),
        PopupMenuItem(value: 'about', child: Text(l10n.aboutApp)),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)
          PopupMenuItem(
            value: 'logs',
            enabled: !_exporting,
            child: Text(l10n.exportDiagnostics),
          ),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)
          PopupMenuItem(value: 'exit', child: Text(l10n.exitApp)),
      ],
    );
  }
}

class _AppAboutDialog extends StatefulWidget {
  const _AppAboutDialog();

  @override
  State<_AppAboutDialog> createState() => _AppAboutDialogState();
}

class _AppAboutDialogState extends State<_AppAboutDialog> {
  late Future<PackageInfo> _info;

  @override
  void initState() {
    super.initState();
    _info = PackageInfo.fromPlatform();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.aboutApp),
      content: FutureBuilder<PackageInfo>(
        future: _info,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.appVersionFailed),
                TextButton(
                  onPressed: () => setState(() {
                    _info = PackageInfo.fromPlatform();
                  }),
                  child: Text(l10n.updateRetry),
                ),
              ],
            );
          }
          final info = snapshot.data;
          if (info == null) {
            return const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final version = info.buildNumber.isEmpty
              ? info.version
              : '${info.version}+${info.buildNumber}';
          return Text('${l10n.appTitle}\n${l10n.appVersion(version)}');
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    );
  }
}

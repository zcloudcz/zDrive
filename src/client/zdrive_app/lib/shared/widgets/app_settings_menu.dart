import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/app_localizations.dart';

class AppSettingsMenu extends StatelessWidget {
  const AppSettingsMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.settings_outlined),
      tooltip: l10n.settings,
      onSelected: (action) async {
        if (action == 'about') {
          showDialog<void>(
            context: context,
            builder: (_) => const _AppAboutDialog(),
          );
        } else {
          try {
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
        PopupMenuItem(value: 'about', child: Text(l10n.aboutApp)),
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

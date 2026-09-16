import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../l10n/app_localizations.dart';

class WindowsDownloadButton extends StatelessWidget {
  const WindowsDownloadButton({super.key, this.compact = false});

  final bool compact;

  void _openDownloads() {
    web.window.open('/downloads/', '_blank', 'noopener,noreferrer');
  }

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context)!.downloadForWindows;
    if (compact) {
      return IconButton(
        onPressed: _openDownloads,
        icon: const Icon(Icons.desktop_windows_outlined),
        tooltip: label,
      );
    }
    return TextButton.icon(
      onPressed: _openDownloads,
      icon: const Icon(Icons.desktop_windows_outlined),
      label: Text(label),
    );
  }
}

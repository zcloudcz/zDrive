import 'package:flutter/material.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../../sync/domain/sync_mirror_entry.dart';

/// What the item menu offers for each [OfflineStatus]. Kept next to the icon
/// so list and grid items cannot disagree.
extension OfflineStatusActions on OfflineStatus {
  /// Also offered for [OfflineStatus.downloading]: a pin whose download failed
  /// (network drop) is retried by choosing it again.
  bool get canKeep => this != OfflineStatus.alwaysKeep && this != OfflineStatus.alwaysKeepViaFolder;

  /// Not for items kept via a pinned folder: unpinning them has to happen on
  /// that folder, "free up" on the item alone would silently do nothing.
  bool get canFreeUp => this == OfflineStatus.available || this == OfflineStatus.alwaysKeep;
}

/// Small per-item "cloud only / downloading / on this device" marker shown in
/// the desktop file browser.
class OfflineStatusIcon extends StatelessWidget {
  final OfflineStatus status;
  final double size;

  const OfflineStatusIcon({super.key, required this.status, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (status) {
      OfflineStatus.cloudOnly => (Icons.cloud_outlined, l10n.offlineCloudOnly, colors.onSurfaceVariant),
      OfflineStatus.downloading => (Icons.downloading, l10n.offlineDownloading, colors.primary),
      OfflineStatus.available => (Icons.check_circle_outline, l10n.offlineAvailable, colors.primary),
      OfflineStatus.alwaysKeep ||
      OfflineStatus.alwaysKeepViaFolder => (Icons.offline_pin, l10n.offlineAlwaysKeep, colors.primary),
    };
    return Tooltip(
      message: label,
      child: Icon(icon, size: size, color: color, semanticLabel: label),
    );
  }
}

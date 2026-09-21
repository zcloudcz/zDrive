import 'package:flutter/material.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../../sync/domain/sync_mirror_entry.dart';
import '../../domain/file_item.dart';
import 'file_icon.dart';
import 'offline_status_icon.dart';

class FileGridItem extends StatelessWidget {
  final FileItem file;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onVersions;

  /// Desktop selective-sync extras. Null on platforms without the sync engine
  /// (web, mobile): then no marker and no menu entries are shown.
  final OfflineStatus? offlineStatus;
  final VoidCallback? onKeepOnDevice;
  final VoidCallback? onFreeUp;

  const FileGridItem({
    super.key,
    required this.file,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onShare,
    required this.onVersions,
    this.offlineStatus,
    this.onKeepOnDevice,
    this.onFreeUp,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              // Solid fill, not a translucent wash over whatever sits behind
              // it — the alpha wash read as muddy at low contrast (spec 4.5).
              child: Container(
                color: colorScheme.surfaceContainerHighest,
                child: Center(
                  child: FileIcon(file: file, size: 40),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (offlineStatus != null)
                    OfflineStatusIcon(status: offlineStatus!, size: 16),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    // The glyph stays small, but the tap target must still
                    // meet the 48dp minimum (spec 4.6 accessibility).
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'rename':
                          onRename();
                        case 'delete':
                          onDelete();
                        case 'share':
                          onShare();
                        case 'versions':
                          onVersions();
                        case 'keep':
                          onKeepOnDevice?.call();
                        case 'freeUp':
                          onFreeUp?.call();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'rename', child: Text(l10n.rename)),
                      PopupMenuItem(
                          value: 'share', child: Text(l10n.share)),
                      // Folders have no content, so no version history.
                      if (!file.isFolder)
                        PopupMenuItem(
                            value: 'versions',
                            child: Text(l10n.versionHistory)),
                      if (onKeepOnDevice != null &&
                          offlineStatus?.canKeep == true)
                        PopupMenuItem(
                            value: 'keep', child: Text(l10n.keepOnDevice)),
                      if (onFreeUp != null && offlineStatus?.canFreeUp == true)
                        PopupMenuItem(
                            value: 'freeUp', child: Text(l10n.freeUpSpace)),
                      PopupMenuItem(
                          value: 'delete', child: Text(l10n.delete)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:zdrive_app/shared/l10n/relative_time.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../../sync/domain/sync_mirror_entry.dart';
import '../../domain/file_item.dart';
import 'file_icon.dart';
import 'file_size_format.dart';
import 'offline_status_icon.dart';

class FileListItem extends StatelessWidget {
  final FileItem file;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onVersions;

  /// Null hides the "Download" menu entry.
  final VoidCallback? onDownload;

  /// Desktop selective-sync extras. Null on platforms without the sync engine
  /// (web, mobile): then no marker and no menu entries are shown.
  final OfflineStatus? offlineStatus;
  final VoidCallback? onKeepOnDevice;
  final VoidCallback? onFreeUp;

  const FileListItem({
    super.key,
    required this.file,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onShare,
    required this.onVersions,
    this.onDownload,
    this.offlineStatus,
    this.onKeepOnDevice,
    this.onFreeUp,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return ListTile(
      leading: FileIcon(file: file),
      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        file.isFolder
            ? formatRelativeTime(file.updatedAt, l10n.localeName)
            : '${formatFileSize(file.sizeBytes)} · ${formatRelativeTime(file.updatedAt, l10n.localeName)}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (offlineStatus != null) OfflineStatusIcon(status: offlineStatus!),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'rename':
                  onRename();
                case 'delete':
                  onDelete();
                case 'share':
                  onShare();
                case 'download':
                  onDownload?.call();
                case 'versions':
                  onVersions();
                case 'keep':
                  onKeepOnDevice?.call();
                case 'freeUp':
                  onFreeUp?.call();
              }
            },
            itemBuilder: (_) => [
              if (!file.isFolder && onDownload != null)
                PopupMenuItem(value: 'download', child: Text(l10n.download)),
              PopupMenuItem(value: 'rename', child: Text(l10n.rename)),
              PopupMenuItem(value: 'share', child: Text(l10n.share)),
              // Folders have no content, so no version history.
              if (!file.isFolder)
                PopupMenuItem(value: 'versions', child: Text(l10n.versionHistory)),
              if (onKeepOnDevice != null && offlineStatus?.canKeep == true)
                PopupMenuItem(value: 'keep', child: Text(l10n.keepOnDevice)),
              if (onFreeUp != null && offlineStatus?.canFreeUp == true)
                PopupMenuItem(value: 'freeUp', child: Text(l10n.freeUpSpace)),
              PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
            ],
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

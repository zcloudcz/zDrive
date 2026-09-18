import 'package:flutter/material.dart';
import 'package:zdrive_app/shared/l10n/relative_time.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../domain/file_item.dart';
import 'file_icon.dart';
import 'file_size_format.dart';

class FileListItem extends StatelessWidget {
  final FileItem file;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onVersions;

  const FileListItem({
    super.key,
    required this.file,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onShare,
    required this.onVersions,
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
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: PopupMenuButton<String>(
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
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'rename', child: Text(l10n.rename)),
          PopupMenuItem(value: 'share', child: Text(l10n.share)),
          // Folders have no content, so no version history.
          if (!file.isFolder)
            PopupMenuItem(value: 'versions', child: Text(l10n.versionHistory)),
          PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
        ],
      ),
      onTap: onTap,
    );
  }
}

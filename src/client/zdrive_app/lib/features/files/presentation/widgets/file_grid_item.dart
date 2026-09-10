import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../domain/file_item.dart';
import 'file_icon.dart';

class FileGridItem extends StatelessWidget {
  final FileItem file;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onVersions;
  final VoidCallback onDownloadFolder;

  const FileGridItem({
    super.key,
    required this.file,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onShare,
    required this.onVersions,
    required this.onDownloadFolder,
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
              child: Container(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                child: Center(
                  child: FileIcon(file: file, size: 48),
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
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      iconSize: 16,
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
                          case 'downloadFolder':
                            onDownloadFolder();
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                            value: 'rename', child: Text(l10n.rename)),
                        PopupMenuItem(
                            value: 'share', child: Text(l10n.share)),
                        // Folders have no content, so no version history —
                        // but they do get a download action, since tapping a
                        // folder navigates into it rather than downloading.
                        if (!file.isFolder)
                          PopupMenuItem(
                              value: 'versions',
                              child: Text(l10n.versionHistory)),
                        if (file.isFolder && !kIsWeb)
                          PopupMenuItem(
                              value: 'downloadFolder',
                              child: Text(l10n.downloadFolder)),
                        PopupMenuItem(
                            value: 'delete', child: Text(l10n.delete)),
                      ],
                    ),
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

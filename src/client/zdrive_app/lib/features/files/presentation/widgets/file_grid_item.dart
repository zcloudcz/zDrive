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

  const FileGridItem({
    super.key,
    required this.file,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onShare,
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
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                            value: 'rename', child: Text(l10n.rename)),
                        PopupMenuItem(
                            value: 'share', child: Text(l10n.share)),
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

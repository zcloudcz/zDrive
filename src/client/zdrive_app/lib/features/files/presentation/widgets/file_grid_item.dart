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

  const FileGridItem({
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

import 'package:flutter/material.dart';

import '../../domain/file_item.dart';
import 'file_icon_data.dart';

class FileIcon extends StatelessWidget {
  final FileItem file;
  final double size;

  const FileIcon({super.key, required this.file, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (file.isFolder) {
      return Icon(Icons.folder, size: size, color: colorScheme.primary);
    }

    final icon = iconForFile(isFolder: false, mimeType: file.mimeType);
    return Icon(icon, size: size, color: colorScheme.onSurfaceVariant);
  }
}

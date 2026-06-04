import 'package:flutter/material.dart';

import '../../domain/file_item.dart';

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

    final icon = _iconForMimeType(file.mimeType);
    return Icon(icon, size: size, color: colorScheme.onSurfaceVariant);
  }

  IconData _iconForMimeType(String? mimeType) {
    if (mimeType == null) return Icons.insert_drive_file;

    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.video_file;
    if (mimeType.startsWith('audio/')) return Icons.audio_file;
    if (mimeType.startsWith('text/')) return Icons.description;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('zip') || mimeType.contains('archive')) {
      return Icons.archive;
    }
    if (mimeType.contains('spreadsheet') || mimeType.contains('excel')) {
      return Icons.table_chart;
    }
    if (mimeType.contains('presentation') || mimeType.contains('powerpoint')) {
      return Icons.slideshow;
    }
    if (mimeType.contains('document') || mimeType.contains('word')) {
      return Icons.article;
    }

    return Icons.insert_drive_file;
  }
}

import 'package:flutter/material.dart';

/// The icon [FileIcon] shows for a file/folder, factored out so the public
/// share page can reuse the same mapping without depending on the domain
/// [FileItem] type that widget is built around.
IconData iconForFile({required bool isFolder, String? mimeType}) {
  if (isFolder) return Icons.folder;
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

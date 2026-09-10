import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../domain/file_item.dart';
import '../domain/file_repository.dart';

/// Lets the user pick a destination directory, then saves [folder]'s whole
/// tree under it (in a subdirectory named after [folder]). See
/// [mirrorRemoteFolder] for the walk itself.
Future<void> downloadFolder(FileRepository repository, FileItem folder) async {
  final destPath = await FilePicker.platform.getDirectoryPath();
  if (destPath == null) return; // User cancelled the picker.
  await mirrorRemoteFolder(repository, folder.id, Directory('$destPath/${folder.name}'));
}

/// Recursively walks the remote folder [remoteFolderId], creating
/// [localDir] and every subfolder under it, and saving each file's
/// reassembled content (via [FileRepository.downloadFile], which already
/// fetches and verifies every chunk) into place.
///
/// No backend change: this is the same manifest/chunk API a single-file
/// download already uses, just called once per file in the tree. A
/// server-side zip/archive endpoint would save round-trips for very large
/// trees, but isn't needed for this to work.
Future<void> mirrorRemoteFolder(
  FileRepository repository,
  String remoteFolderId,
  Directory localDir,
) async {
  await localDir.create(recursive: true);

  var page = 1;
  const pageSize = 200;
  while (true) {
    final result = await repository.listChildren(
      remoteFolderId,
      page: page,
      pageSize: pageSize,
    );

    for (final item in result.items) {
      if (item.isFolder) {
        await mirrorRemoteFolder(
          repository,
          item.id,
          Directory('${localDir.path}/${item.name}'),
        );
      } else {
        final bytes = await repository.downloadFile(item.id);
        await File('${localDir.path}/${item.name}').writeAsBytes(bytes);
      }
    }

    if (page * pageSize >= result.totalCount || result.items.isEmpty) break;
    page++;
  }
}

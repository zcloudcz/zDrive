import '../domain/file_item.dart';
import '../domain/file_repository.dart';

/// Web cannot write an arbitrary local directory tree (no `dart:io`, and
/// browsers only ever hand the user one file at a time), so folder download
/// does not exist here. file_browser_page.dart hides the "download folder"
/// action on web; this only exists so the conditional export in
/// folder_downloader.dart has a web-safe counterpart.
Future<void> downloadFolder(FileRepository repository, FileItem folder) async {
  throw UnsupportedError('Folder download is not supported on web.');
}

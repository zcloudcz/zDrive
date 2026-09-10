// Walks a remote folder client-side and saves each file locally, mirroring
// the folder structure. Conditionally exported like file_saver.dart: saving
// nested directories needs dart:io, which does not exist on web — and a
// browser cannot write an arbitrary local directory tree, so this is a
// native-only feature (see file_browser_page.dart's kIsWeb gate).
export 'folder_downloader_web.dart' if (dart.library.io) 'folder_downloader_io.dart';

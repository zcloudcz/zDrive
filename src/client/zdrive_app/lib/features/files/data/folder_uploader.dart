// Mirrors a locally-picked directory tree into zDrive. Conditionally
// exported like file_saver.dart: picking a directory and walking it needs
// dart:io, which does not exist on web — there is also no way for a web
// page to read a local directory tree in the first place, so folder upload
// is a native-only feature (see file_browser_page.dart's kIsWeb gate).
export 'folder_uploader_web.dart' if (dart.library.io) 'folder_uploader_io.dart';

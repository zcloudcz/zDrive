// Saves downloaded file bytes as a named file, through whatever mechanism
// the current platform actually supports. Conditionally exported: native
// platforms (Android, iOS, Windows, macOS, Linux) go through file_picker +
// dart:io; web has no file_picker saveFile() implementation, so it uses a
// browser Blob download instead.
export 'file_saver_web.dart' if (dart.library.io) 'file_saver_io.dart';

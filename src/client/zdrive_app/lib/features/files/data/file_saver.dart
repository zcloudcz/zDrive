// Saves a downloaded stream through the current platform's mechanism.
// Desktop chooses a path before consuming content and stages it on disk.
// Android/iOS plugins and browser Blob downloads still require buffering
// the complete file in memory.
export 'file_saver_web.dart' if (dart.library.io) 'file_saver_io.dart';

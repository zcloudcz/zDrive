import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Saves [bytes] as [fileName] via the OS save dialog.
///
/// file_picker's `saveFile()` behaves differently per platform (see its own
/// doc comment on `FilePicker.saveFile`): on Android/iOS it writes [bytes]
/// itself and returns the resulting path; on desktop (Windows/macOS/Linux)
/// the dialog only returns the chosen path — [bytes] is not accepted there
/// (macOS throws if it is), so this function writes the file itself.
Future<void> saveFile(String fileName, Uint8List bytes) async {
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  if (isMobile) {
    await FilePicker.platform.saveFile(fileName: fileName, bytes: bytes);
    return;
  }

  final path = await FilePicker.platform.saveFile(fileName: fileName);
  if (path == null) return; // User cancelled the save dialog.
  await File(path).writeAsBytes(bytes);
}

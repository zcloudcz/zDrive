import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Desktop asks for a destination before subscribing to [content], then
/// installs it only after successful stream completion. Mobile plugins
/// require the complete byte array, so that fallback still buffers in memory.
Future<void> saveFileStream(String fileName, Stream<Uint8List> content) async {
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (isMobile) {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in content) {
      builder.add(chunk);
    }
    await saveFile(fileName, builder.takeBytes());
    return;
  }

  final path = await FilePicker.platform.saveFile(fileName: fileName);
  if (path == null) return;

  final staging = await File(path).parent.createTemp(r'~$zdrive-download-');
  final temporary = File(p.join(staging.path, 'content'));
  try {
    final output = await temporary.open(mode: FileMode.write);
    try {
      await for (final chunk in content) {
        await output.writeFrom(chunk);
      }
      await output.flush();
    } finally {
      await output.close();
    }
    // Same-filesystem replacement; OS sharing restrictions may reject it.
    // Never delete an existing destination to work around a failed rename.
    await temporary.rename(path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
    await staging.delete();
  }
}

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

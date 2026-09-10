import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Saves [bytes] as [fileName] by triggering a browser download.
///
/// file_picker has no web implementation of `saveFile()` — `FilePickerWeb`
/// never overrides the base class's `saveFile`, which throws
/// `UnimplementedError` (see file_picker's `_internal/file_picker_web.dart`).
/// The browser-native way to hand the user a file instead: build an
/// in-memory Blob, point a synthetic `<a download>` at it, and click it.
/// Unlike `window.open()` (the previous, now-removed url_launcher path),
/// this is not a popup and does not depend on user-activation still being
/// live after the network round-trip that fetched [bytes].
Future<void> saveFile(String fileName, Uint8List bytes) async {
  final blob = web.Blob([bytes.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..click();
  web.URL.revokeObjectURL(url);
}

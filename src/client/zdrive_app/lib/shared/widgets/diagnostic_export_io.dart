import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../core/diagnostics/diagnostics.dart';

Future<bool> exportDiagnosticFile() async {
  final source = await Diagnostics.exportLogs();
  if (source == null) throw StateError('Diagnostic log unavailable');
  var keepSource = false;
  try {
    final destination = await FilePicker.platform.saveFile(
      fileName: 'zDrive-diagnostics.log',
      type: FileType.custom,
      allowedExtensions: ['log'],
    );
    if (destination == null) return false;
    keepSource =
        File(source).absolute.path.toLowerCase() ==
        File(destination).absolute.path.toLowerCase();
    if (!keepSource) await File(source).copy(destination);
    return true;
  } finally {
    if (!keepSource) {
      try {
        await File(source).delete();
      } on FileSystemException {
        // Export cleanup must not hide the original save result.
      }
    }
  }
}

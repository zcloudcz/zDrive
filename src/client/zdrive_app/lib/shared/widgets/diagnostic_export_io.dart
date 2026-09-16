import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../core/diagnostics/diagnostics.dart';

Future<bool> exportDiagnosticFile() async {
  final source = await Diagnostics.exportLogs();
  if (source == null) throw StateError('Diagnostic log unavailable');
  final destination = await FilePicker.platform.saveFile(
    fileName: 'zDrive-diagnostics.log',
    type: FileType.custom,
    allowedExtensions: ['log'],
  );
  if (destination == null) return false;
  if (File(source).absolute.path != File(destination).absolute.path) {
    await File(source).copy(destination);
  }
  return true;
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads a PNG's width from its IHDR chunk (bytes 16-19, big-endian) without
/// decoding the image — enough to guard against a future regeneration
/// shrinking the asset back down.
int _pngWidth(ByteData data) {
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  return ByteData.sublistView(bytes, 16, 20).getUint32(0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Guards the pubspec.yaml `assets:` declaration: a wrong or missing path
  // only fails at runtime (rootBundle.load), never at compile time.
  for (final path in [
    'assets/branding/zdrive-mark.png',
    'assets/branding/zdrive-mark@2x.png',
    'assets/branding/zdrive-mark@3x.png',
  ]) {
    test('rootBundle resolves declared branding asset $path', () async {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(0));
    });
  }

  test('zdrive-mark@3x.png is at least 384px wide (guards HiDPI sharpness)', () async {
    final data = await rootBundle.load('assets/branding/zdrive-mark@3x.png');
    expect(_pngWidth(data), greaterThanOrEqualTo(384));
  });
}

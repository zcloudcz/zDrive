import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Guards the pubspec.yaml `assets:` declaration: a wrong or missing path
  // only fails at runtime (rootBundle.load), never at compile time.
  for (final path in [
    'assets/branding/zdrive-lockup.png',
    'assets/branding/zdrive-lockup@2x.png',
    'assets/branding/zdrive-lockup@3x.png',
  ]) {
    test('rootBundle resolves declared branding asset $path', () async {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(0));
    });
  }
}

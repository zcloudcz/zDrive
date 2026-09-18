import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Guards the petrol brand colour in the web shell files. Neither file is
/// read by the Flutter runtime under test, so a plain Dart file test (not
/// flutter_test) reading them directly is the simplest check that a future
/// asset regeneration cannot silently revert the colour.
void main() {
  // Tests run from the package root regardless of invocation directory.
  final webDir = p.join(Directory.current.path, 'web');

  test('web/manifest.json uses brand petrol for theme_color and background_color', () {
    final manifest = File(p.join(webDir, 'manifest.json')).readAsStringSync();
    expect(manifest, contains('"background_color": "#003840"'));
    expect(manifest, contains('"theme_color": "#003840"'));
  });

  test('web/index.html declares the brand petrol theme-color meta tag', () {
    final indexHtml = File(p.join(webDir, 'index.html')).readAsStringSync();
    expect(indexHtml, contains('<meta name="theme-color" content="#003840">'));
  });
}

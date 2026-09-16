import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/features/sync/data/file_hash.dart';

void main() {
  test(
    'streaming background hash returns digest and actual large file size',
    () async {
      final dir = await Directory.systemTemp.createTemp('sync_hash_');
      addTearDown(() => dir.delete(recursive: true));
      final bytes = Uint8List.fromList(
        List.generate(9 * 1024 * 1024 + 73, (i) => i % 251),
      );
      final file = File('${dir.path}/large.bin');
      await file.writeAsBytes(bytes);
      final result = await hashFileInBackground(file.path);
      expect(result.size, bytes.length);
      expect(result.hash, sha256.convert(bytes).toString());
    },
  );

  test('missing file reports an error', () async {
    final dir = await Directory.systemTemp.createTemp('sync_hash_');
    addTearDown(() => dir.delete(recursive: true));
    await expectLater(
      hashFileInBackground('${dir.path}/missing'),
      throwsA(isA<FileSystemException>()),
    );
  });
}

import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// Reads and hashes bounded chunks away from the UI isolate.
Future<({String hash, int size})> hashFileInBackground(String path) =>
    Isolate.run(() async {
      var size = 0;
      final digest = await sha256
          .bind(
            File(path).openRead().map((chunk) {
              size += chunk.length;
              return chunk;
            }),
          )
          .single;
      return (hash: digest.toString(), size: size);
    });

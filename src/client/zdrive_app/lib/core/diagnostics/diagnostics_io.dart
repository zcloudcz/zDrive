import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'diagnostic_record.dart';

class Diagnostics {
  static SendPort? _writer;
  static Isolate? _isolate;
  static ReceivePort? _acks;
  static Timer? _heartbeat;
  static int _pending = 0;
  static int _dropped = 0;

  static Future<void> initialize({
    String? version,
    String? directory,
    int maxBytes = 2 * 1024 * 1024,
    Duration stallThreshold = const Duration(seconds: 10),
    // Test-only: simulates a slow isolate startup, to prove `readyTimeout`
    // tolerates it instead of silently abandoning a merely-slow writer.
    Duration startupDelay = Duration.zero,
    Duration readyTimeout = const Duration(seconds: 20),
  }) async {
    if (_writer != null) return;
    final ready = ReceivePort();
    try {
      final base =
          directory ??
          (Platform.isWindows && Platform.environment['LOCALAPPDATA'] != null
              ? p.join(Platform.environment['LOCALAPPDATA']!, 'zDrive', 'logs')
              : p.join(
                  (await getApplicationSupportDirectory().timeout(
                    const Duration(seconds: 3),
                  )).path,
                  'logs',
                ));
      _acks = ReceivePort()
        ..listen((_) {
          if (_pending > 0) _pending--;
        });
      _isolate = await Isolate.spawn(_writeLogs, [
        ready.sendPort,
        _acks!.sendPort,
        base,
        maxBytes,
        stallThreshold.inMilliseconds,
        version ?? 'unknown',
        startupDelay.inMilliseconds,
      ]);
      // A generous safety net, not a race: isolate group startup and JIT
      // warm-up for the writer entrypoint can legitimately take several
      // seconds under load (busy CI runners, cold caches). A tight timeout
      // here does not "fail fast" on a broken writer -- it abandons a merely
      // slow one, permanently and silently (every event/flush becomes a
      // no-op for the rest of the session, since `_writer` stays null).
      final result = await ready.first.timeout(readyTimeout);
      if (result is! SendPort) {
        throw StateError('Diagnostic writer unavailable');
      }
      _writer = result;
      _heartbeat = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _writer?.send('heartbeat'),
      );
    } catch (_) {
      await shutdown();
    } finally {
      ready.close();
    }
  }

  static void event(String name, [Map<String, Object?> fields = const {}]) {
    _send(diagnosticRecord(name, fields));
  }

  static void error(String name, Object error, [StackTrace? stack]) {
    final record = diagnosticRecord(name, {});
    final type = error.runtimeType.toString().replaceAll(
      RegExp(r'[^a-zA-Z0-9_]'),
      '',
    );
    record['errorType'] = type.substring(0, type.length.clamp(0, 80));
    record['stack'] = diagnosticStack(stack);
    _send(record);
  }

  static void _send(Map<String, Object?> record) {
    if (_writer == null) return;
    if (_pending >= 256) {
      _dropped++;
      return;
    }
    if (_dropped > 0) {
      record['droppedEvents'] = _dropped;
      _dropped = 0;
    }
    _pending++;
    _writer!.send(record);
  }

  static Future<String?> exportLogs() async {
    if (_writer == null) return null;
    final reply = ReceivePort();
    try {
      _writer!.send(reply.sendPort);
      return await reply.first.timeout(const Duration(seconds: 10)) as String?;
    } catch (_) {
      return null;
    } finally {
      reply.close();
    }
  }

  /// Wait for earlier events to reach the disk writer before an explicit exit.
  /// A broken or busy filesystem must never indefinitely hold up the app.
  static Future<void> flush() async {
    if (_writer == null) return;
    final reply = ReceivePort();
    try {
      _writer!.send(['flush', reply.sendPort]);
      await reply.first.timeout(const Duration(seconds: 2));
    } catch (_) {
      // Logging is best effort if the writer cannot make progress.
    } finally {
      reply.close();
    }
  }

  /// Also releases resources for isolated filesystem tests.
  static Future<void> shutdown() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    if (_writer != null) {
      final closed = ReceivePort();
      _writer!.send(['shutdown', closed.sendPort]);
      try {
        await closed.first.timeout(const Duration(seconds: 1));
      } catch (_) {
        /* A failed writer must not prevent app shutdown. */
      } finally {
        closed.close();
      }
    }
    _writer = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _acks?.close();
    _acks = null;
    _pending = 0;
    _dropped = 0;
  }
}

void _writeLogs(List<Object> args) {
  final ready = args[0] as SendPort;
  final ack = args[1] as SendPort;
  final directory = args[2] as String;
  final maxBytes = args[3] as int;
  final threshold = args[4] as int;
  final session = '${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid';
  final inbox = ReceivePort();
  File log(int index) => File(p.join(directory, 'diagnostic-$index.jsonl'));

  T locked<T>(T Function() operation) {
    Directory(directory).createSync(recursive: true);
    RandomAccessFile? lease;
    try {
      // Retry briefly on this worker only, never block the UI isolate. Releasing
      // the lease after each operation allows every running app to write/export.
      for (var attempt = 0; ; attempt++) {
        try {
          lease = File(
            p.join(directory, 'diagnostic.lock'),
          ).openSync(mode: FileMode.append);
          lease.lockSync(FileLock.exclusive);
          break;
        } on FileSystemException {
          lease?.closeSync();
          lease = null;
          if (attempt == 4) rethrow;
          sleep(const Duration(milliseconds: 10));
        }
      }
      try {
        return operation();
      } finally {
        lease.unlockSync();
      }
    } finally {
      lease?.closeSync();
    }
  }

  var failedEvents = 0;
  var exportSequence = 0;
  void append(Map<String, Object?> record) {
    try {
      locked(() {
        final bytes = utf8.encode(
          '${jsonEncode({...record, 'session': session, if (failedEvents > 0) 'writerDroppedEvents': failedEvents})}\n',
        );
        // Another process may have appended or rotated since our last event.
        final length = log(0).existsSync() ? log(0).lengthSync() : 0;
        if (length + bytes.length > maxBytes) {
          if (log(2).existsSync()) log(2).deleteSync();
          for (var i = 1; i >= 0; i--) {
            if (log(i).existsSync()) log(i).renameSync(log(i + 1).path);
          }
        }
        final output = log(0).openSync(mode: FileMode.append);
        try {
          output.writeFromSync(bytes);
          output.flushSync();
        } finally {
          output.closeSync();
        }
      });
      failedEvents = 0;
    } catch (_) {
      failedEvents++;
    }
  }

  final version = args[5] as String;
  final startupDelayMs = args[6] as int;
  append({
    ...diagnosticRecord('app.started', {'pid': pid}),
    'version': RegExp(r'^[a-zA-Z0-9.+_-]{1,60}$').hasMatch(version)
        ? version
        : 'unknown',
    'os': Platform.operatingSystem,
  });
  // Test-only: simulates isolate startup that is slower than a would-be
  // too-tight `readyTimeout`, without waiting on real scheduler jitter.
  if (startupDelayMs > 0) sleep(Duration(milliseconds: startupDelayMs));
  final clock = Stopwatch()..start();
  var lastHeartbeat = 0;
  var stalled = false;
  final watchdog = Timer.periodic(
    Duration(milliseconds: threshold.clamp(50, 2000)),
    (_) {
      if (!stalled && clock.elapsedMilliseconds - lastHeartbeat > threshold) {
        stalled = true;
        append(
          diagnosticRecord('ui.heartbeat_stalled', {
            'gapMs': clock.elapsedMilliseconds - lastHeartbeat,
          }),
        );
      }
    },
  );
  inbox.listen((message) {
    if (message is List && message.first == 'shutdown') {
      watchdog.cancel();
      inbox.close();
      (message[1] as SendPort).send(null);
    } else if (message is List && message.first == 'flush') {
      if (failedEvents > 0) append(diagnosticRecord('writer.drop_summary', {}));
      // ReceivePort preserves sender order, and each earlier append flushed.
      (message[1] as SendPort).send(null);
    } else if (message == 'heartbeat') {
      if (stalled) {
        append(
          diagnosticRecord('ui.heartbeat_recovered', {
            'gapMs': clock.elapsedMilliseconds - lastHeartbeat,
          }),
        );
      }
      stalled = false;
      lastHeartbeat = clock.elapsedMilliseconds;
    } else if (message is Map) {
      // Generic map type arguments are not preserved consistently when a
      // message crosses an isolate boundary on Windows. The record originates
      // from diagnosticRecord, so normalizing its string keys is sufficient.
      append(Map<String, Object?>.from(message));
      ack.send(null);
    } else if (message is SendPort) {
      if (failedEvents > 0) append(diagnosticRecord('writer.drop_summary', {}));
      try {
        final exported = locked(() {
          final file = File(
            p.join(
              directory,
              'diagnostic-export-$session-${++exportSequence}.log',
            ),
          );
          final snapshot = file.openSync(mode: FileMode.write);
          try {
            for (var i = 2; i >= 0; i--) {
              if (log(i).existsSync()) {
                snapshot.writeFromSync(log(i).readAsBytesSync());
              }
            }
            snapshot.flushSync();
          } finally {
            snapshot.closeSync();
          }
          return file.path;
        });
        message.send(exported);
      } catch (_) {
        message.send(null);
      }
    }
  });
  ready.send(inbox.sendPort);
}

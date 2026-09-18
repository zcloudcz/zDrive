import 'dart:async';
import 'dart:collection';
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

  // A writer isolate that is merely slow to start (busy CI runner, cold
  // JIT) is not broken, so `initialize()` never disables the facility on a
  // timeout. Events raised before the writer is ready are queued here --
  // bounded, so a writer that never starts cannot grow this without limit
  // -- and flushed in order once the ready signal arrives, however late.
  // Only a writer that genuinely fails (spawn error, uncaught isolate
  // error, exit before ready) disables logging, via [_writerFailed].
  static final Queue<Map<String, Object?>> _preReadyQueue = Queue();
  static int _preReadyDropped = 0;
  static const _preReadyQueueCap = 2000;
  static bool _writerFailed = false;
  static Completer<void>? _readyOrFailed;
  static bool _slowStartFlagged = false;
  static Duration _readyTimeout = const Duration(seconds: 20);
  // Bumped on every initialize()/shutdown() cycle. A killed-but-still-
  // starting isolate can deliver its (late) ready/exit message after a
  // *later* initialize() call has already set up fresh state; the callback
  // below checks this to discard such a stale result instead of clobbering
  // the newer session.
  static int _generation = 0;

  static Future<void> initialize({
    String? version,
    String? directory,
    int maxBytes = 2 * 1024 * 1024,
    Duration stallThreshold = const Duration(seconds: 10),
    // Test-only: simulates a slow isolate startup.
    Duration startupDelay = Duration.zero,
    // How long `flush()` waits before flagging the writer as slow to start
    // (a `diagnostics.slow_writer_start` event, itself queued for once the
    // writer is up). Purely observability -- flush() keeps waiting for the
    // writer past this point regardless; it is never treated as a failure.
    Duration readyTimeout = const Duration(seconds: 20),
  }) async {
    if (_writer != null || _isolate != null) return;
    _writerFailed = false;
    _slowStartFlagged = false;
    _readyTimeout = readyTimeout;
    final readyOrFailed = Completer<void>();
    _readyOrFailed = readyOrFailed;
    final generation = ++_generation;
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
      // The same port doubles as onError/onExit: a genuine isolate failure
      // delivers a message that is not a SendPort, handled below exactly
      // like an explicit "unavailable" result.
      _isolate = await Isolate.spawn(
        _writeLogs,
        [
          ready.sendPort,
          _acks!.sendPort,
          base,
          maxBytes,
          stallThreshold.inMilliseconds,
          version ?? 'unknown',
          startupDelay.inMilliseconds,
        ],
        onError: ready.sendPort,
        onExit: ready.sendPort,
      );
      unawaited(
        ready.first.then((result) {
          ready.close();
          if (generation != _generation) return; // superseded, see above
          if (result is SendPort) {
            _writer = result;
            _heartbeat = Timer.periodic(
              const Duration(seconds: 2),
              (_) => _writer?.send('heartbeat'),
            );
            _drainPreReadyQueue();
          } else {
            _writerFailed = true;
            _isolate = null;
          }
          if (!readyOrFailed.isCompleted) readyOrFailed.complete();
        }),
      );
    } catch (_) {
      _writerFailed = true;
      if (!readyOrFailed.isCompleted) readyOrFailed.complete();
      ready.close();
      await shutdown();
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
    if (_writerFailed) return;
    if (_writer != null) {
      _sendToWriter(record);
      return;
    }
    // Writer not ready yet: buffer instead of dropping. Bounded so a writer
    // that never starts (still waiting, or about to fail) cannot leak
    // memory; oldest entries make way, and the drop count is reported as
    // one summary event once the writer is finally reachable.
    if (_preReadyQueue.length >= _preReadyQueueCap) {
      _preReadyQueue.removeFirst();
      _preReadyDropped++;
    }
    _preReadyQueue.add(record);
  }

  static void _sendToWriter(Map<String, Object?> record) {
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

  static void _drainPreReadyQueue() {
    if (_preReadyDropped > 0) {
      _sendToWriter(
        diagnosticRecord('diagnostics.dropped', {'count': _preReadyDropped}),
      );
      _preReadyDropped = 0;
    }
    while (_preReadyQueue.isNotEmpty) {
      _sendToWriter(_preReadyQueue.removeFirst());
    }
  }

  // Shared by exportLogs()/flush(): both need the writer to actually be up
  // before they mean anything, and both are callable while it is still
  // starting (cold JIT, busy CI runner) -- which is not a failure. `_readyTimeout`
  // only flags a slow start once, as an event queued for whenever the
  // writer does come up; callers still wait for the real outcome (ready,
  // or genuinely failed via spawn error / isolate error / exit) afterwards.
  // A fixed bound that gave up here would silently lose events queued so
  // far, which is exactly the bug this replaces.
  static Future<void> _awaitWriter() async {
    if (_writer != null || _writerFailed) return;
    if (!_slowStartFlagged) {
      try {
        await _readyOrFailed?.future.timeout(_readyTimeout);
      } on TimeoutException {
        _slowStartFlagged = true;
        _send(diagnosticRecord('diagnostics.slow_writer_start', {}));
      }
    }
    await _readyOrFailed?.future;
  }

  static Future<String?> exportLogs() async {
    await _awaitWriter();
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
    await _awaitWriter();
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
    _generation++; // discard any still-in-flight ready/exit callback
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
    _preReadyQueue.clear();
    _preReadyDropped = 0;
    _writerFailed = false;
    _slowStartFlagged = false;
    if (_readyOrFailed != null && !_readyOrFailed!.isCompleted) {
      _readyOrFailed!.complete();
    }
    _readyOrFailed = null;
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
      // Pre-ready events now arrive in one synchronous burst once the writer
      // comes up (drained from the buffer -- see Diagnostics._drainPreReadyQueue),
      // instead of trickling in one at a time; two writers sharing a
      // directory can collide on this lock more densely than before, so the
      // retry budget is wider than a single append's own contention needed.
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
          if (attempt == 19) rethrow;
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

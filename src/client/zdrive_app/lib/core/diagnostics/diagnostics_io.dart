import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'diagnostic_record.dart';

class Diagnostics {
  static SendPort? _writer;
  static Isolate? _isolate;
  static ReceivePort? _acks;
  // Stays open for the writer isolate's whole life (unlike the one-shot
  // `ready` port in initialize()), so a crash/exit *after* readiness is
  // still observed -- otherwise events would pile up behind `_pending`'s
  // cap and silently vanish into `_dropped` while everything looked fine.
  static ReceivePort? _lifecycle;
  static Timer? _heartbeat;
  static int _pending = 0;
  static int _dropped = 0;

  // A writer isolate that is merely slow to start (busy CI runner, cold
  // JIT) is not broken, so `initialize()` never disables the facility on a
  // timeout. Events raised before the writer is ready are queued here --
  // bounded, so a writer that never starts cannot grow this without limit
  // -- and flushed in order once the ready signal arrives, however late.
  // Only a writer that genuinely fails (spawn error, uncaught isolate
  // error, exit before or after ready) disables logging, via [_writerFailed].
  static final Queue<Map<String, Object?>> _preReadyQueue = Queue();
  static int _preReadyDropped = 0;
  static const _preReadyQueueCap = 2000;
  static bool _writerFailed = false;
  static Completer<void>? _readyOrFailed;
  static bool _slowStartFlagged = false;
  static bool _draining = false;
  static Duration _readyTimeout = const Duration(seconds: 5);
  // Bumped on every initialize()/shutdown() cycle. A killed-but-still-
  // starting isolate can deliver its (late) ready/exit message after a
  // *later* initialize() call has already set up fresh state; callbacks
  // below check this to discard such a stale result instead of clobbering
  // the newer session.
  static int _generation = 0;

  static Future<void> initialize({
    String? version,
    String? directory,
    int maxBytes = 2 * 1024 * 1024,
    Duration stallThreshold = const Duration(seconds: 10),
    // Test-only: simulates a slow isolate startup.
    @visibleForTesting Duration startupDelay = Duration.zero,
    // Bounds how long flush()/exportLogs() wait for the writer to report
    // ready (see _awaitWriter). Exposed for tests; production code should
    // not need to override the default.
    @visibleForTesting Duration readyTimeout = const Duration(seconds: 5),
  }) async {
    if (_writer != null || _isolate != null) return;
    _writerFailed = false;
    _slowStartFlagged = false;
    _readyTimeout = readyTimeout;
    final readyOrFailed = Completer<void>();
    _readyOrFailed = readyOrFailed;
    final generation = ++_generation;
    final ready = ReceivePort();
    final lifecycle = ReceivePort();
    _lifecycle = lifecycle;
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
      // onError/onExit go to `lifecycle`, not `ready`: a genuine isolate
      // failure (crash, or exit before ever reporting ready) must be
      // distinguishable from -- and raceable against -- the writer's own
      // explicit readiness signal on `ready`.
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
        onError: lifecycle.sendPort,
        onExit: lifecycle.sendPort,
      );
      unawaited(
        () async {
          // A single, persistent listener on `lifecycle`: its first message
          // races against `ready` below (via `firstFailure`) to decide the
          // initial outcome, and the SAME listener keeps running afterward
          // to catch a *later* crash/exit -- a ReceivePort only allows one
          // subscription, so `.first` (which itself listens) cannot be used
          // here as well without "Stream has already been listened to".
          final firstFailure = Completer<Object?>();
          final lifecycleSub = lifecycle.listen((message) {
            if (!firstFailure.isCompleted) {
              firstFailure.complete(message);
              return;
            }
            if (generation != _generation) return;
            _writerFailed = true;
            _writer = null;
            _heartbeat?.cancel();
            _heartbeat = null;
          });
          Object? result;
          try {
            result = await Future.any([ready.first, firstFailure.future]);
          } catch (_) {
            result = null;
          }
          ready.close();
          if (generation != _generation) {
            await lifecycleSub.cancel();
            lifecycle.close();
            return;
          }
          if (result is SendPort) {
            _writer = result;
            _heartbeat = Timer.periodic(
              const Duration(seconds: 2),
              (_) => _writer?.send('heartbeat'),
            );
            await _drainPreReadyQueue();
            if (!readyOrFailed.isCompleted) readyOrFailed.complete();
            // lifecycleSub keeps running: a later message hits the `else`
            // branch above and marks the facility failed.
          } else {
            // Genuine failure (spawn's onError/onExit) before the writer
            // ever reported ready.
            _writerFailed = true;
            _isolate = null;
            await lifecycleSub.cancel();
            lifecycle.close();
            if (!readyOrFailed.isCompleted) readyOrFailed.complete();
          }
        }(),
      );
    } catch (_) {
      _writerFailed = true;
      if (!readyOrFailed.isCompleted) readyOrFailed.complete();
      ready.close();
      lifecycle.close();
      await shutdown();
    }
  }

  /// Test-only: simulates the writer isolate dying unexpectedly (crash,
  /// OOM, killed by the OS) *after* it already reported ready, to exercise
  /// the `_lifecycle` failure path without a real crash.
  @visibleForTesting
  static void killWriterForTest() {
    // A real `Isolate.kill()`'s onExit notification is not guaranteed to be
    // prompt -- it can wait for the isolate's own next scheduled event
    // (e.g. its 2s heartbeat-stall timer), which would make this seam flaky
    // for no reason relevant to what it is testing. Deliver the same
    // synthetic signal `onExit` would, directly and immediately; still kill
    // the isolate too, for realism and cleanup.
    _lifecycle?.sendPort.send(null);
    _isolate?.kill(priority: Isolate.immediate);
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
    // While a drain is running, new events still queue behind whatever it
    // has not yet sent -- sending directly here would let them overtake
    // earlier, still-buffered events and break ordering.
    if (_writer != null && !_draining) {
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

  // Drains the buffer built up before the writer was ready. Exempt from
  // `_sendToWriter`'s normal 256 in-flight cap: that cap exists to bound
  // memory from a sender that could otherwise queue unboundedly forever;
  // draining does not have that shape; it is a single pass over a buffer
  // that was already bounded at `_preReadyQueueCap` when it was filled, so
  // it cannot itself grow further while draining (`_send` refuses to bypass
  // it during a drain, see `_draining`). Gating on the 256 cap as well
  // would mean polling for round-tripped acks mid-drain to make progress,
  // which is slow and protects nothing not already covered by that bound.
  // Order is preserved: this is the only place that removes from
  // `_preReadyQueue`, in FIFO order, synchronously.
  static Future<void> _drainPreReadyQueue() async {
    _draining = true;
    try {
      if (_preReadyDropped > 0) {
        _sendDuringDrain(
          diagnosticRecord('diagnostics.dropped', {'count': _preReadyDropped}),
        );
        _preReadyDropped = 0;
      }
      while (_preReadyQueue.isNotEmpty) {
        if (_writerFailed) return; // writer died mid-drain; stop, don't hang
        _sendDuringDrain(_preReadyQueue.removeFirst());
      }
    } finally {
      _draining = false;
    }
  }

  static void _sendDuringDrain(Map<String, Object?> record) {
    if (_dropped > 0) {
      record['droppedEvents'] = _dropped;
      _dropped = 0;
    }
    _pending++;
    _writer!.send(record);
  }

  // Shared by exportLogs()/flush(): both need the writer to actually be up
  // before they mean anything, and both are callable while it is still
  // starting (cold JIT, busy CI runner) -- which is not a failure.
  // Bounded so exit-path callers (flush()/exportLogs(), and quit() which
  // awaits flush() before restarting) never hang: the writer now reports
  // ready before it ever touches the shared `diagnostic.lock` (see
  // _writeLogs), but a lock held by another instance sharing this
  // directory (tray + updater-spawned instance under
  // %LOCALAPPDATA%\zDrive\logs, or a synced/SMB dir) can still delay
  // isolate startup itself past this bound in principle. On timeout this
  // never disables the facility -- it just flags the slow start once (an
  // event queued like any other) and returns; events keep buffering, and a
  // later ready signal still drains them.
  static Future<void> _awaitWriter() async {
    // `_writer` is set the moment the writer reports ready, but the drain
    // of whatever was buffered before that runs after, asynchronously (see
    // _drainPreReadyQueue). Racing ahead of it here -- straight to the
    // writer, bypassing the still-draining queue -- would let flush()'s
    // own message overtake buffered events still waiting their turn.
    if ((_writer != null && !_draining) || _writerFailed) return;
    try {
      await _readyOrFailed?.future.timeout(_readyTimeout);
    } on TimeoutException {
      if (!_slowStartFlagged) {
        _slowStartFlagged = true;
        _send(diagnosticRecord('diagnostics.slow_writer_start', {}));
      }
    }
  }

  static Future<String?> exportLogs() async {
    await _awaitWriter();
    if (_writer == null || _draining) return null;
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
    if (_writer == null || _draining) return;
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
    _draining = false;
    _lifecycle?.close();
    _lifecycle = null;
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
      // Pre-ready events now arrive in one fully synchronous, uncapped burst
      // once the writer comes up (drained from the buffer -- see
      // Diagnostics._drainPreReadyQueue), instead of trickling in one at a
      // time; two writers sharing a directory can collide on this lock much
      // more densely than before, so the retry budget is far wider than a
      // single append's own contention needed.
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
          if (attempt == 199) rethrow;
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
  // Test-only: simulates isolate startup that is slower than a would-be
  // too-tight `readyTimeout`, without waiting on real scheduler jitter.
  // Deliberately before `ready.send` below -- it stands in for real
  // isolate/JIT startup cost, which does delay readiness.
  if (startupDelayMs > 0) sleep(Duration(milliseconds: startupDelayMs));
  final clock = Stopwatch()..start();
  var lastHeartbeat = 0;
  var stalled = false;
  late final Timer watchdog;
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
  // Report ready before ever touching `diagnostic.lock`: readiness must not
  // depend on winning it. A caller stuck behind another instance holding
  // that lock (tray + updater-spawned instance sharing
  // %LOCALAPPDATA%\zDrive\logs, or a synced/SMB directory) would otherwise
  // never see `ready`, leaving flush()/exportLogs() nothing to bound their
  // wait against (see Diagnostics._awaitWriter). The lock wait now only
  // delays this isolate's writes, which that bound already tolerates.
  ready.send(inbox.sendPort);
  append({
    ...diagnosticRecord('app.started', {'pid': pid}),
    'version': RegExp(r'^[a-zA-Z0-9.+_-]{1,60}$').hasMatch(version)
        ? version
        : 'unknown',
    'os': Platform.operatingSystem,
  });
  watchdog = Timer.periodic(
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
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'update_manifest.dart';

abstract interface class UpdateBackend {
  String get currentVersion;
  Future<UpdateManifest?> readPending();
  Future<bool> consumePreviousError();
  Future<UpdateManifest> fetchManifest();
  Future<void> prepare(UpdateManifest manifest, void Function(int) onBytes);
  Future<void> launch(UpdateManifest manifest);
  Future<void> quit();
  void close();
}

enum UpdatePhase { idle, checking, downloading, ready, restarting, error }

class UpdateController extends ChangeNotifier {
  UpdateController(this.backend, {required this.drain, required this.resume});
  final UpdateBackend backend;
  final Future<void> Function() drain;
  final Future<void> Function() resume;
  UpdatePhase phase = UpdatePhase.idle;
  UpdateManifest? pending;
  int downloadedBytes = 0;
  int? totalBytes;
  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  void _publish(UpdatePhase value) {
    if (_disposed) return;
    phase = value;
    notifyListeners();
  }

  /// Only local validation runs before authentication and sync startup.
  Future<bool> initialize({bool skipApply = false}) async {
    try {
      final previousError = await backend.consumePreviousError();
      pending = await backend.readPending();
      if (_disposed) return false;
      if (pending != null && !skipApply && !previousError) {
        return await apply(drainFirst: false);
      }
      _publish(
        previousError
            ? UpdatePhase.error
            : pending != null
            ? UpdatePhase.ready
            : UpdatePhase.idle,
      );
    } catch (_) {
      _publish(UpdatePhase.error);
    }
    return false;
  }

  void start() {
    if (_disposed || _timer != null) return;
    _timer = Timer.periodic(
      const Duration(hours: 6),
      (_) => unawaited(check()),
    );
    if (phase != UpdatePhase.error) unawaited(check());
  }

  Future<void> check() async {
    if (_disposed || _busy || pending != null) return;
    _busy = true;
    _publish(UpdatePhase.checking);
    try {
      final manifest = await backend.fetchManifest();
      if (_disposed) return;
      if (!manifest.isNewerThan(backend.currentVersion)) {
        _publish(UpdatePhase.idle);
        return;
      }
      downloadedBytes = 0;
      totalBytes = manifest.sizeBytes;
      _publish(UpdatePhase.downloading);
      await backend.prepare(manifest, (bytes) {
        if (_disposed) return;
        downloadedBytes = bytes;
        _publish(UpdatePhase.downloading);
      });
      if (_disposed) return;
      pending = manifest;
      _publish(UpdatePhase.ready);
    } catch (_) {
      _publish(UpdatePhase.error);
    } finally {
      _busy = false;
    }
  }

  Future<bool> apply({bool drainFirst = true}) async {
    final manifest = pending;
    if (_disposed || _busy || manifest == null) return false;
    _busy = true;
    _publish(UpdatePhase.restarting);
    try {
      if (drainFirst) await drain();
      if (_disposed) return false;
      await backend.launch(manifest);
      if (_disposed) return false;
      await backend.quit();
      return true;
    } catch (_) {
      if (drainFirst && !_disposed) {
        try {
          await resume();
        } catch (_) {
          /* The normal sync UI reports errors. */
        }
      }
      _publish(UpdatePhase.error);
      return false;
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    backend.close();
    super.dispose();
  }
}

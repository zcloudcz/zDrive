import 'package:equatable/equatable.dart';

enum SyncPhase {
  connecting,
  downloading,
  scanning,
  hashing,
  uploading,
  deleting,
}

class SyncFileProgress extends Equatable {
  final String key;
  final String path;
  final int transferredBytes;
  final int? totalBytes;

  const SyncFileProgress({
    required this.key,
    required this.path,
    this.transferredBytes = 0,
    this.totalBytes,
  });

  @override
  List<Object?> get props => [key, path, transferredBytes, totalBytes];
}

class SyncProgress extends Equatable {
  final SyncPhase phase;
  final int totalFiles;
  final int completedFiles;
  final int failedFiles;
  final bool discovering;
  final List<SyncFileProgress> activeFiles;

  SyncProgress({
    required this.phase,
    this.totalFiles = 0,
    this.completedFiles = 0,
    this.failedFiles = 0,
    this.discovering = false,
    List<SyncFileProgress> activeFiles = const [],
  }) : activeFiles = List.unmodifiable(activeFiles);

  int get remainingFiles =>
      (totalFiles - completedFiles - failedFiles).clamp(0, totalFiles);

  @override
  List<Object?> get props => [
    phase,
    totalFiles,
    completedFiles,
    failedFiles,
    discovering,
    activeFiles,
  ];
}

/// Phase-local counters. Byte callbacks are coalesced without background timers.
class SyncProgressTracker {
  final void Function(SyncProgress) onProgress;
  final Stopwatch _clock = Stopwatch()..start();
  int _lastEmission = -100;
  SyncPhase _phase = SyncPhase.connecting;
  int _total = 0;
  int _completed = 0;
  int _failed = 0;
  bool _discovering = false;
  final Map<String, SyncFileProgress> _active = {};

  SyncProgressTracker(this.onProgress);

  SyncProgress get snapshot => SyncProgress(
    phase: _phase,
    totalFiles: _total,
    completedFiles: _completed,
    failedFiles: _failed,
    discovering: _discovering,
    activeFiles: _active.values.toList(),
  );

  void beginPhase(
    SyncPhase phase, {
    int totalFiles = 0,
    bool discovering = false,
  }) {
    _phase = phase;
    _total = totalFiles;
    _completed = 0;
    _failed = 0;
    _discovering = discovering;
    _active.clear();
    _emit();
  }

  void setTotalFiles(int totalFiles) {
    _total = totalFiles;
    _emit();
  }

  void startFile(String key, String path, {int? totalBytes}) {
    _active[key] = SyncFileProgress(
      key: key,
      path: path,
      totalBytes: totalBytes,
    );
    _emit();
  }

  void updateFile(String key, int bytes, {int? totalBytes}) {
    final file = _active[key];
    if (file == null) return;
    _active[key] = SyncFileProgress(
      key: key,
      path: file.path,
      transferredBytes: bytes,
      totalBytes: totalBytes ?? file.totalBytes,
    );
    if (_clock.elapsedMilliseconds - _lastEmission >= 100) _emit();
  }

  void finishFile(String key, {bool failed = false}) {
    if (_active.remove(key) == null) return;
    if (failed) {
      _failed++;
    } else {
      _completed++;
    }
    _emit();
  }

  void _emit() {
    _lastEmission = _clock.elapsedMilliseconds;
    onProgress(snapshot);
  }
}

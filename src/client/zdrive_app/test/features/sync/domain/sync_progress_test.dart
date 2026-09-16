import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/features/sync/domain/sync_progress.dart';
void main() {
  test('snapshots are immutable, phase counters reset and duplicate finishes are ignored', () {
    final tracker = SyncProgressTracker((_) {});
    tracker.beginPhase(SyncPhase.uploading, totalFiles: 2);
    tracker.startFile('a', 'a.jpg', totalBytes: 100);
    final old = tracker.snapshot;
    tracker.startFile('b', 'b.jpg');
    tracker.updateFile('a', 50);
    expect(old.activeFiles.single.transferredBytes, 0);
    expect(() => old.activeFiles.clear(), throwsUnsupportedError);
    tracker.finishFile('b', failed: true);
    expect(tracker.snapshot.remainingFiles, 1);
    expect(tracker.snapshot.failedFiles, 1);
    tracker.finishFile('a'); tracker.finishFile('a');
    expect(tracker.snapshot.completedFiles, 1);
    expect(tracker.snapshot.remainingFiles, 0);
    tracker.beginPhase(SyncPhase.scanning, discovering: true);
    tracker.setTotalFiles(4);
    expect(tracker.snapshot.discovering, isTrue);
    expect(tracker.snapshot.failedFiles, 0);
  });
  test('byte updates coalesce and finish emits immediately', () {
    final emissions = <SyncProgress>[];
    final tracker = SyncProgressTracker(emissions.add);
    tracker.beginPhase(SyncPhase.uploading, totalFiles: 1);
    tracker.startFile('a', 'a');
    final before = emissions.length;
    for (var i = 0; i < 100; i++) { tracker.updateFile('a', i); }
    expect(emissions.length, before);
    expect(tracker.snapshot.activeFiles.single.transferredBytes, 99);
    tracker.finishFile('a');
    expect(emissions.last.completedFiles, 1);
  });
}

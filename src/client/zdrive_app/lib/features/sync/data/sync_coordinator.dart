import 'package:injectable/injectable.dart';

import 'local_change_scanner.dart';
import 'pull_sync_service.dart';

/// Runs one full sync cycle: pull, then scan-and-push, never overlapping —
/// pull and push share this single lock instead of each guarding itself
/// independently.
///
/// WHY strictly sequential under one guard, not just "not concurrent with
/// itself": a scan running *between* pull writing a file to disk and pull
/// updating the mirror for it would see a file that looks locally "changed"
/// (on disk, but not yet in the mirror) and push pull's own write straight
/// back to the server as if it were a local edit. Running pull fully to
/// completion before a scan ever starts — both behind the same in-flight
/// future [PullSyncService.pullOnce] already uses — makes that ordering
/// impossible instead of merely unlikely.
@lazySingleton
class SyncCoordinator {
  final PullSyncService _pull;
  final LocalChangeScanner _scanner;

  SyncCoordinator(this._pull, this._scanner);

  Future<SyncRunResult>? _inFlight;

  Future<SyncRunResult> syncOnce(String syncFolderPath) {
    return _inFlight ??= _syncOnce(syncFolderPath).whenComplete(() => _inFlight = null);
  }

  Future<SyncRunResult> _syncOnce(String syncFolderPath) async {
    final pulled = await _pull.pullOnce(syncFolderPath);
    final pushed = await _scanner.scanOnce(syncFolderPath);
    return SyncRunResult(pulled: pulled, pushed: pushed);
  }
}

/// How many events [SyncCoordinator.syncOnce] applied from the server and
/// how many local changes it reported upstream.
class SyncRunResult {
  final int pulled;
  final int pushed;

  const SyncRunResult({required this.pulled, required this.pushed});
}

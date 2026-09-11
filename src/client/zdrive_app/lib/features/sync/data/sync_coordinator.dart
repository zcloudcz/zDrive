import 'dart:developer';
import 'dart:io';

import 'package:injectable/injectable.dart';

import 'local_change_scanner.dart';
import 'pull_sync_service.dart';
import 'push_sync_service.dart';

/// Thrown when the designated sync folder no longer exists on disk (the
/// user renamed or deleted it since it was chosen — the watcher and poll
/// have no way to notice that asynchronously, so this is caught on the
/// very next [SyncCoordinator.syncOnce] instead). Must be checked *before*
/// pull runs: [Directory.create] deep inside pull would silently recreate
/// the folder as soon as it needs to write anything into it, and the scan
/// that follows would then find every tracked item "missing" from that
/// freshly-empty folder and delete the whole account's content (PR #12
/// review round 1, F3). Surfaces through SyncBloc's existing pull-error
/// path (`e.toString()` shown as-is), so no new UI string is needed.
class SyncFolderMissingException implements Exception {
  final String path;
  const SyncFolderMissingException(this.path);

  @override
  String toString() => 'sync folder is missing: $path';
}

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
  final PushSyncService _push;

  SyncCoordinator(this._pull, this._scanner, this._push);

  Future<SyncRunResult>? _inFlight;

  Future<SyncRunResult> syncOnce(String syncFolderPath) {
    return _inFlight ??= _syncOnce(syncFolderPath).whenComplete(() => _inFlight = null);
  }

  Future<SyncRunResult> _syncOnce(String syncFolderPath) async {
    // Checked before pull runs — see SyncFolderMissingException's doc
    // comment for why pull and scan must never run against a folder that
    // is not actually there.
    if (!await Directory(syncFolderPath).exists()) {
      throw SyncFolderMissingException(syncFolderPath);
    }
    final pulled = await _pull.pullOnce(syncFolderPath);
    final pushed = await _scanner.scanOnce(syncFolderPath);
    // The scan itself never depends on SyncService being reachable (PR #14
    // review round 3) — every local change is already durable in the
    // outbox by this point, so a drain failure here must not throw out of
    // syncOnce: the queue just retries on the next cycle instead.
    try {
      await _push.drainOutbox();
    } catch (e, st) {
      log('drainOutbox failed, queue retries next cycle', error: e, stackTrace: st, name: 'SyncCoordinator');
    }
    final queued = await _push.outboxCount();
    return SyncRunResult(pulled: pulled, pushed: pushed, queued: queued);
  }
}

/// How many events [SyncCoordinator.syncOnce] applied from the server, how
/// many local changes it committed, and how many reports are still owed
/// after the drain (0 when SyncService kept up).
class SyncRunResult {
  final int pulled;
  final int pushed;
  final int queued;

  const SyncRunResult({required this.pulled, required this.pushed, required this.queued});
}

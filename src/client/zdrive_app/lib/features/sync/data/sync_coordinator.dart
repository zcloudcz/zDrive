import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:injectable/injectable.dart';

import '../../../core/storage/app_preferences.dart';
import '../../../core/diagnostics/diagnostics.dart';
import '../domain/sync_mirror_repository.dart';
import '../domain/sync_progress.dart';
import 'device_id_storage.dart';
import 'device_registration_service.dart';
import 'local_change_scanner.dart';
import 'pull_sync_service.dart';
import 'sync_remote_data_source.dart';

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
/// independently. The same lock also serializes [startSession], [endSession]
/// and [resetForNewFolder] against [syncOnce] — see [_withLock]'s doc
/// comment.
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
  final SyncMirrorRepository _mirror;
  final DeviceIdStorage _deviceIdStorage;
  final AppPreferences _preferences;
  final DeviceRegistrationService _deviceRegistration;
  final SyncRemoteDataSource _remote;

  SyncCoordinator(
    this._pull,
    this._scanner,
    this._mirror,
    this._deviceIdStorage,
    this._preferences,
    this._deviceRegistration,
    this._remote,
  );

  // Dedupe is scoped to the path it was started for — not "whatever run is
  // currently in flight" — because the mutex below can queue a stale
  // syncOnce(A) behind a resetForNewFolder(B): if a concurrent syncOnce(B)
  // just joined A's future instead of starting its own, B would never
  // actually run pull/scan for its own folder at all (PR #16 review round
  // 3, finding 2). A call for a different path always gets its own future;
  // the mutex still serializes the actual work, so it simply waits its turn
  // behind whatever is already queued.
  ({String path, Future<SyncRunResult> future})? _inFlight;

  // A small async mutex: every critical section below (syncOnce's own body,
  // startSession, endSession, resetForNewFolder) chains onto this future in
  // call order, one at a time. Not a package dependency — the need is this
  // narrow: no reentrancy, no timeout, just "wait your turn". WHY this is
  // needed on top of syncOnce's own single-flight [_inFlight] dedupe below:
  // that dedupe only protects syncOnce against a second concurrent syncOnce
  // call: it does nothing to stop [startSession] from clearing the mirror
  // while a syncOnce is mid-pull, which would pull the ground out from under
  // a write still in progress — see [startSession]'s doc comment.
  Future<void> _mutex = Future.value();

  Future<T> _withLock<T>(Future<T> Function() body) {
    final previous = _mutex;
    final completer = Completer<void>();
    // Reassigned synchronously, before this function returns — so a second
    // call made right after this one (even in the same microtask) still
    // queues behind this one's completer, regardless of how long `body`
    // itself takes to actually start running.
    _mutex = completer.future;
    return previous
        .then((_) => body())
        .whenComplete(() => completer.complete());
  }

  // Set by [endSession], cleared by [startSession] — see endSession's doc
  // comment for why a poll tick between the mirror clear and the app shell
  // actually being disposed must not be allowed to bootstrap a fresh
  // session back into the just-cleared state.
  bool _sessionEnded = false;

  Future<SyncRunResult> syncOnce(
    String syncFolderPath, {
    void Function(SyncProgress)? onProgress,
  }) {
    final current = _inFlight;
    if (current != null && current.path == syncFolderPath) {
      return current.future;
    }
    final progress = onProgress == null
        ? null
        : SyncProgressTracker(onProgress);
    Diagnostics.event('sync.queued');
    final future = _withLock(() async {
      final watch = Stopwatch()..start();
      Diagnostics.event('sync.start');
      try {
        final result = await _syncOnce(syncFolderPath, progress);
        Diagnostics.event('sync.complete', {
          'pulled': result.pulled,
          'pushed': result.pushed,
          'durationMs': watch.elapsedMilliseconds,
        });
        return result;
      } catch (error, stack) {
        Diagnostics.error('sync.failed', error, stack);
        rethrow;
      }
    });
    final entry = (path: syncFolderPath, future: future);
    _inFlight = entry;
    // Only clear the slot if it still holds THIS entry — a call for a
    // different path may already have replaced it by the time this one
    // finishes, and that entry must not be wiped out from under it.
    return future.whenComplete(() {
      if (_inFlight == entry) {
        _inFlight = null;
      }
    });
  }

  Future<SyncRunResult> _syncOnce(
    String syncFolderPath,
    SyncProgressTracker? progress,
  ) async {
    if (_sessionEnded) {
      // A poll tick or watcher event firing after endSession has already
      // cleared the mirror, but before the app shell that owns the bloc
      // driving this call is actually disposed — see endSession's doc
      // comment. A no-op, not an error: there is nothing to sync for a
      // session that no longer exists, and checked before the folder-exists
      // check below so it holds regardless of what is still on disk.
      return const SyncRunResult(pulled: 0, pushed: 0);
    }
    if (_preferences.syncFolderPath != syncFolderPath) {
      // A poll tick or watch event that captured the sync folder path
      // before [resetForNewFolder] switched it to a different one — that
      // switch (see its doc comment) sets the new path inside the same
      // mutex as the mirror clear, so by the time this call gets its turn
      // on the lock, the stored path already reflects whichever folder is
      // actually current. A stale argument must not run pull/scan against
      // either the old path (nothing there is tracked in the just-cleared
      // mirror any more) or the new one under a caller who does not
      // actually mean it (PR #16 review round 2, finding 3).
      return const SyncRunResult(pulled: 0, pushed: 0);
    }
    // Checked before pull runs — see SyncFolderMissingException's doc
    // comment for why pull and scan must never run against a folder that
    // is not actually there.
    if (!await Directory(syncFolderPath).exists()) {
      throw SyncFolderMissingException(syncFolderPath);
    }
    progress?.beginPhase(SyncPhase.connecting, discovering: true);
    Diagnostics.event('sync.pull.start');
    final pulled = progress == null
        ? await _pull.pullOnce(syncFolderPath)
        : await _pull.pullOnce(syncFolderPath, progress: progress);
    // Rule: the timestamp means "this device last contacted the server
    // successfully" — so a pull that completed without throwing counts,
    // even if it applied zero events. Only a pull that throws skips the
    // heartbeat. It deliberately does not wait for the scan below, so it
    // does not claim the local half of the reconciliation happened; the
    // account-wide device list is the only thing that reads it, and this
    // installation's own push state has its own tile on the sync page.
    //
    // Fire and forget, and NOT awaited anywhere in this run: the whole
    // method body holds _mutex, and the shared Dio client retries a
    // 429/5xx heartbeat up to three times, honouring `Retry-After` capped
    // at 120s. Awaiting it — even after the scan — keeps the lock for
    // minutes, which would hang `endSession()` on logout (auth_bloc waits
    // on the same mutex, so the tokens never get cleared) and drop the 30s
    // poll ticks that arrive meanwhile. Nothing in the run needs the
    // result, and _sendHeartbeat catches everything internally, so the
    // dangling future can never surface as an unhandled async error.
    Diagnostics.event('sync.pull.complete', {'count': pulled});
    unawaited(_sendHeartbeat());
    Diagnostics.event('sync.scan.start');
    final pushed = progress == null
        ? await _scanner.scanOnce(syncFolderPath)
        : await _scanner.scanOnce(syncFolderPath, progress: progress);
    Diagnostics.event('sync.scan.complete', {'count': pushed});
    return SyncRunResult(pulled: pulled, pushed: pushed);
  }

  /// Best-effort: pull's results are already applied and persisted by the
  /// time this runs, so a heartbeat failure (network blip, server error)
  /// must not undo that or abort the scan that runs alongside it — it is
  /// logged and swallowed instead. [DeviceRegistrationService.localDeviceId]
  /// is inside the try too — it reads platform secure storage, which can
  /// throw just as easily as the network call (Codex review).
  Future<void> _sendHeartbeat() async {
    try {
      final deviceId = await _deviceRegistration.localDeviceId();
      if (deviceId == null) {
        return; // First-run edge case — nothing registered yet.
      }
      await _remote.heartbeat(deviceId);
    } catch (e, st) {
      log(
        'heartbeat failed',
        error: e,
        stackTrace: st,
        name: 'SyncCoordinator',
      );
    }
  }

  /// Re-enables syncing after [endSession] — called by [SyncBloc] on
  /// `LoadSyncStatus` with the id of whichever user is now authenticated.
  ///
  /// Also the one place that decides whether this machine's mirror, device
  /// id, and chosen folder still belong to [userId]: if the stored owner is
  /// someone else, everything is cleared before this session is allowed to
  /// sync. Checking here — not at logout — is what makes this hold
  /// regardless of *how* the previous session ended (the logout button, an
  /// expired refresh token, a killed app process): every one of those paths
  /// leaves this machine's stored owner pointing at the account that just
  /// left, and this check runs unconditionally when the next login arrives,
  /// so it does not depend on every possible ending path having its own
  /// cleanup call. The same user signing back in clears nothing — its
  /// mirror, device id and folder are exactly what let that re-login skip
  /// re-uploading every local file as a new version.
  Future<void> startSession(String userId) {
    return _withLock(() async {
      final storedOwner = _preferences.syncOwnerUserId;
      if (storedOwner != null && storedOwner != userId) {
        await _mirror.clearAll();
        await _deviceIdStorage.clear();
        await _preferences.clearSyncFolderPath();
        // The previous owner's backoff entries are keyed by local path, not
        // by user — if the new owner picks the same folder, a path that
        // failed for the old account must not sit in cooldown for the new
        // one too, delaying files it has never even tried yet (PR #16
        // review round 2, finding 8).
        _scanner.resetBackoff();
      }
      await _preferences.setSyncOwnerUserId(userId);
      _sessionEnded = false;
    });
  }

  /// Stops syncing for the session that is ending — the logout button, or
  /// any other path that calls it. Does *not* clear the mirror, device id,
  /// or chosen sync folder any more: that responsibility moved to
  /// [startSession]'s owner check (see its doc comment for why), so the
  /// same account logging back in on this machine is not made to
  /// re-upload every local file as a new version just because it logged
  /// out first.
  ///
  /// WHY the flag, not just trusting nothing calls syncOnce again:
  /// [SyncBloc]'s poll timer and folder watcher keep firing until the app
  /// shell that owns them is actually disposed, which happens asynchronously
  /// after `AuthBloc` emits `Unauthenticated` — a tick in that window would
  /// otherwise keep syncing this account's folder for a few more cycles
  /// after the user asked to log out.
  ///
  /// Runs inside [_withLock] so it can never run while a [syncOnce] is
  /// mid-flight.
  Future<void> endSession() {
    return _withLock(() async {
      _sessionEnded = true;
    });
  }

  /// Starts sync over from a clean slate for a newly chosen folder — called
  /// by [SyncBloc] when a folder is picked that differs from the one
  /// already configured. Runs inside [_withLock] for the same reason as
  /// [endSession]: never while a [syncOnce] is mid-flight.
  ///
  /// [newPath] is persisted here, inside the same lock as the mirror clear
  /// — not left for the caller to save afterwards. Saving it outside the
  /// lock left a window where a poll tick queued behind this same mutex
  /// would get its turn between the clear and the save and run
  /// [syncOnce] against whichever path it had captured before either of
  /// those happened: the old path (nothing under it is tracked in the
  /// just-cleared mirror any more) or the new one, by accident, before the
  /// caller actually meant to start syncing it (PR #16 review round 2,
  /// finding 3). [_syncOnce]'s own check against [AppPreferences
  /// .syncFolderPath] is what makes a tick that queued behind THIS call, and
  /// so sees the new path already saved, a safe no-op instead.
  Future<void> resetForNewFolder(String newPath) {
    return _withLock(() async {
      await _mirror.clearAll();
      await _preferences.setSyncFolderPath(newPath);
    });
  }
}

/// How many events [SyncCoordinator.syncOnce] applied from the server, and
/// how many local changes it committed.
class SyncRunResult {
  final int pulled;
  final int pushed;

  const SyncRunResult({required this.pulled, required this.pushed});
}

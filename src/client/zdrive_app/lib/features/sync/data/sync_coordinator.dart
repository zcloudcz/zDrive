import 'dart:async';
import 'dart:io';

import 'package:injectable/injectable.dart';

import '../../../core/storage/app_preferences.dart';
import '../domain/sync_mirror_repository.dart';
import 'device_id_storage.dart';
import 'local_change_scanner.dart';
import 'pull_sync_service.dart';

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
/// independently. The same lock also serializes [endSession] and
/// [resetForNewFolder] against [syncOnce] — see [_withLock]'s doc comment.
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

  SyncCoordinator(this._pull, this._scanner, this._mirror, this._deviceIdStorage, this._preferences);

  Future<SyncRunResult>? _inFlight;

  // A small async mutex: every critical section below (syncOnce's own body,
  // endSession, resetForNewFolder) chains onto this future in call order,
  // one at a time. Not a package dependency — the need is this narrow: no
  // reentrancy, no timeout, just "wait your turn". WHY this is needed on top
  // of syncOnce's own single-flight [_inFlight] dedupe below: that dedupe
  // only protects syncOnce against a second concurrent syncOnce call: it
  // does nothing to stop [endSession] from running while a syncOnce is
  // mid-pull, which would clear the mirror out from under a write still in
  // progress — see [endSession]'s doc comment.
  Future<void> _mutex = Future.value();

  Future<T> _withLock<T>(Future<T> Function() body) {
    final previous = _mutex;
    final completer = Completer<void>();
    // Reassigned synchronously, before this function returns — so a second
    // call made right after this one (even in the same microtask) still
    // queues behind this one's completer, regardless of how long `body`
    // itself takes to actually start running.
    _mutex = completer.future;
    return previous.then((_) => body()).whenComplete(() => completer.complete());
  }

  // Set by [endSession], cleared by [startSession] — see endSession's doc
  // comment for why a poll tick between the mirror clear and the app shell
  // actually being disposed must not be allowed to bootstrap a fresh
  // session back into the just-cleared state.
  bool _sessionEnded = false;

  Future<SyncRunResult> syncOnce(String syncFolderPath) {
    return _inFlight ??= _withLock(() => _syncOnce(syncFolderPath)).whenComplete(() => _inFlight = null);
  }

  Future<SyncRunResult> _syncOnce(String syncFolderPath) async {
    if (_sessionEnded) {
      // A poll tick or watcher event firing after endSession has already
      // cleared the mirror, but before the app shell that owns the bloc
      // driving this call is actually disposed — see endSession's doc
      // comment. A no-op, not an error: there is nothing to sync for a
      // session that no longer exists, and checked before the folder-exists
      // check below so it holds regardless of what is still on disk.
      return const SyncRunResult(pulled: 0, pushed: 0);
    }
    // Checked before pull runs — see SyncFolderMissingException's doc
    // comment for why pull and scan must never run against a folder that
    // is not actually there.
    if (!await Directory(syncFolderPath).exists()) {
      throw SyncFolderMissingException(syncFolderPath);
    }
    final pulled = await _pull.pullOnce(syncFolderPath);
    final pushed = await _scanner.scanOnce(syncFolderPath);
    return SyncRunResult(pulled: pulled, pushed: pushed);
  }

  /// Re-enables syncing after [endSession] — called by [SyncBloc] on
  /// `LoadSyncStatus`, i.e. once the app has a fresh, authenticated shell to
  /// sync for.
  void startSession() {
    _sessionEnded = false;
  }

  /// Clears everything this machine remembers about the account that is
  /// logging out — the mirror, the device id, and the chosen sync folder —
  /// then blocks [syncOnce] until [startSession] re-enables it.
  ///
  /// WHY the flag, not just clearing state and trusting nothing calls
  /// syncOnce again: [SyncBloc]'s poll timer and folder watcher keep firing
  /// until the app shell that owns them is actually disposed, which happens
  /// asynchronously after `AuthBloc` emits `Unauthenticated` — a tick in
  /// that window would otherwise register a fresh device and re-bootstrap
  /// the just-cleared folder from FileService before the shell is gone, and
  /// the next account that logs in on this machine would inherit that
  /// mirror and folder: its first scan would then upload the previous
  /// user's files into the new account.
  ///
  /// Runs inside [_withLock] so it can never run while a [syncOnce] is
  /// mid-flight — clearing the mirror out from under a pull or scan that is
  /// still writing to it would leave that write's own mirror row pointing
  /// at data that no longer exists.
  Future<void> endSession() {
    return _withLock(() async {
      _sessionEnded = true;
      await _mirror.clearAll();
      await _deviceIdStorage.clear();
      await _preferences.clearSyncFolderPath();
    });
  }

  /// Starts sync over from a clean slate for a newly chosen folder — called
  /// by [SyncBloc] when a folder is picked that differs from the one
  /// already configured. Runs inside [_withLock] for the same reason as
  /// [endSession]: never while a [syncOnce] is mid-flight.
  Future<void> resetForNewFolder() {
    return _withLock(() => _mirror.clearAll());
  }
}

/// How many events [SyncCoordinator.syncOnce] applied from the server, and
/// how many local changes it committed.
class SyncRunResult {
  final int pulled;
  final int pushed;

  const SyncRunResult({required this.pulled, required this.pushed});
}

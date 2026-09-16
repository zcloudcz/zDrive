import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/events/remote_file_change_notifier.dart';
import '../../../core/storage/app_preferences.dart';
import '../data/pull_sync_service.dart';
import '../data/sync_coordinator.dart';
import '../data/sync_remote_data_source.dart';
import '../domain/sync_mirror_entry.dart';
import '../domain/sync_models.dart';
import '../domain/sync_progress.dart';

// --- Events ---

sealed class SyncEvent extends Equatable {
  const SyncEvent();

  @override
  List<Object?> get props => [];
}

final class LoadSyncStatus extends SyncEvent {
  const LoadSyncStatus();
}

/// The user picked a local folder to sync (via the platform folder picker —
/// the pick itself happens in the page, this just carries the result in).
final class SyncFolderChosen extends SyncEvent {
  final String path;

  const SyncFolderChosen(this.path);

  @override
  List<Object?> get props => [path];
}

/// Pulls once: registers the device if needed and applies pending events.
/// Fired after loading (if a folder is already configured), after a folder
/// is first chosen, on the periodic timer, and from a manual "sync now".
final class PullRequested extends SyncEvent {
  const PullRequested();
}

// --- States ---

sealed class SyncState extends Equatable {
  const SyncState();

  @override
  List<Object?> get props => [];
}

final class SyncInitial extends SyncState {
  const SyncInitial();
}

final class SyncLoading extends SyncState {
  const SyncLoading();
}

final class SyncLoaded extends SyncState {
  final List<SyncDevice> devices;
  final String? syncFolderPath;
  final bool isPulling;
  final String? pullError;
  final List<SyncFailedEvent> failedEvents;
  final SyncProgress? progress;
  final int failedFiles;

  const SyncLoaded({
    required this.devices,
    this.syncFolderPath,
    this.isPulling = false,
    this.pullError,
    this.failedEvents = const [],
    this.progress,
    this.failedFiles = 0,
  });

  SyncLoaded copyWith({
    List<SyncDevice>? devices,
    String? syncFolderPath,
    bool? isPulling,
    String? Function()? pullError,
    List<SyncFailedEvent>? failedEvents,
    SyncProgress? Function()? progress,
    int? failedFiles,
  }) {
    return SyncLoaded(
      devices: devices ?? this.devices,
      syncFolderPath: syncFolderPath ?? this.syncFolderPath,
      isPulling: isPulling ?? this.isPulling,
      pullError: pullError != null ? pullError() : this.pullError,
      failedEvents: failedEvents ?? this.failedEvents,
      progress: progress != null ? progress() : this.progress,
      failedFiles: failedFiles ?? this.failedFiles,
    );
  }

  @override
  List<Object?> get props => [
    devices,
    syncFolderPath,
    isPulling,
    pullError,
    failedEvents,
    progress,
    failedFiles,
  ];
}

final class SyncError extends SyncState {
  final String message;

  const SyncError(this.message);

  @override
  List<Object?> get props => [message];
}

// --- Bloc ---

/// Status page for the (Phase 2) sync engine: registered devices, the
/// designated sync folder, and the sync loop that keeps it up to date —
/// pull, then push local changes, via [SyncCoordinator] so the two never
/// interleave (see its class doc comment). Provided once for the whole
/// authenticated app shell (`app_router.dart`), not per-visit to the sync
/// page — see [LoadSyncStatus] and [_onLoadSyncStatus].
class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final SyncRemoteDataSource _dataSource;
  final SyncCoordinator _syncCoordinator;
  final PullSyncService _pullService;
  final AppPreferences _preferences;
  final RemoteFileChangeNotifier _remoteChangeNotifier;
  final String _userId;
  final Stream<FileSystemEvent> Function(String path) _watchFolder;

  // Polling, not SignalR: the hub has no backplane configured at
  // max_replicas=3, so a client subscribed to one replica would miss events
  // raised on another. 30s balances "changes show up promptly" against
  // hammering the gateway from every idle desktop client; short enough that
  // a user waiting on a sync does not perceive it as stalled, long enough
  // that it is not a meaningful load source at MVP scale. The folder watch
  // below makes most syncs faster than this, but the poll stays as the
  // fallback for whatever the watch misses (e.g. Linux has no recursive
  // watch support at all).
  static const _pollInterval = Duration(seconds: 30);

  /// How long to wait after the *last* watch event before syncing — a save
  /// touches a folder several times in quick succession (temp file, rename,
  /// metadata), and a multi-file drag-and-drop fires one event per file;
  /// without debouncing, each of those would trigger its own sync.
  static const _watchDebounce = Duration(seconds: 2);

  Timer? _pollTimer;
  StreamSubscription<FileSystemEvent>? _watchSubscription;
  Timer? _watchDebounceTimer;

  // Ties a sync run's tail back to the run that started it. Bumped on every
  // SyncFolderChosen and on close() — see _runSync: a run captures this at
  // the top and only its OWN tail (the one still holding the current
  // generation) is allowed to write isPulling/pullError/devices/failedEvents
  // into state. Without this, the OLD folder's pull finishing after the
  // switch would clobber the NEW folder's state with stale results, and the
  // guard in _runSync would then see a wrong isPulling and let a poll tick
  // start a second, concurrent syncOnce for the new folder (PR #16 review
  // round 3, finding 1).
  int _syncGeneration = 0;

  // Set when a sync is requested while one is already running (a watch event
  // mid-run, a poll tick, the initial load racing a folder pick) and cleared
  // by the trailing run that services it. Cleared on every _syncGeneration
  // bump too: a request made for a folder nobody is looking at any more must
  // not start a run for the folder that replaced it.
  bool _syncRequestedWhileRunning = false;

  SyncBloc({
    required SyncRemoteDataSource dataSource,
    required SyncCoordinator syncCoordinator,
    required PullSyncService pullService,
    required AppPreferences preferences,
    required RemoteFileChangeNotifier remoteChangeNotifier,
    required String userId,
    Stream<FileSystemEvent> Function(String path)? watch,
  }) : _dataSource = dataSource,
       _syncCoordinator = syncCoordinator,
       _pullService = pullService,
       _preferences = preferences,
       _remoteChangeNotifier = remoteChangeNotifier,
       _userId = userId,
       // Defaults to a real recursive folder watch; tests inject a fake so
       // they can drive events without touching the filesystem.
       _watchFolder =
           watch ?? ((path) => Directory(path).watch(recursive: true)),
       super(const SyncInitial()) {
    on<LoadSyncStatus>(_onLoadSyncStatus);
    on<SyncFolderChosen>(_onSyncFolderChosen);
    on<PullRequested>(_onPullRequested);
  }

  Future<void> _onLoadSyncStatus(
    LoadSyncStatus event,
    Emitter<SyncState> emit,
  ) async {
    emit(const SyncLoading());
    try {
      // Re-enables syncOnce after a previous session's endSession, and — if
      // this machine's stored sync state belongs to a different account
      // than _userId — clears it first, so that account never inherits the
      // previous user's mirror, device id or folder. See
      // SyncCoordinator.startSession's doc comment. Inside this try (PR #16
      // review round 2, finding 7): a failure here used to leave the state
      // at SyncInitial forever — indistinguishable from SyncLoading in
      // SyncPage — instead of the error/retry state every other failure in
      // this handler already gets.
      await _syncCoordinator.startSession(_userId);
      final loaded = await _fetchLoadedState();
      // Same close()-during-await guard as _onSyncFolderChosen (see its
      // comment) — the bloc can close while either await above is pending,
      // and without this, a handler resuming during that window would
      // re-arm _startPolling/_startWatching on a bloc that already closed
      // (PR #16 review round 6, F2).
      if (emit.isDone || isClosed) return;
      emit(loaded);
      if (loaded.syncFolderPath != null) {
        _startPolling();
        _startWatching(loaded.syncFolderPath!);
        add(const PullRequested());
      }
    } catch (e) {
      emit(SyncError(e.toString()));
    }
  }

  Future<void> _onSyncFolderChosen(
    SyncFolderChosen event,
    Emitter<SyncState> emit,
  ) async {
    // Bumped before anything else here so any run already in flight for the
    // old folder is stale the moment its tail next checks — see
    // _syncGeneration's doc comment.
    _syncGeneration++;
    _syncRequestedWhileRunning = false;
    try {
      final current = state;
      final previousPath = current is SyncLoaded
          ? current.syncFolderPath
          : _preferences.syncFolderPath;
      if (previousPath != null && previousPath != event.path) {
        // A different folder than the one already configured starts sync
        // over from a clean slate — see resetForNewFolder's doc comment. This
        // awaits the coordinator's mutex, i.e. waits for any pull already in
        // flight to finish, and now also persists the new path itself, inside
        // that same lock (PR #16 review round 2, finding 3 — see
        // resetForNewFolder's doc comment for why).
        await _syncCoordinator.resetForNewFolder(event.path);
      } else {
        await _preferences.setSyncFolderPath(event.path);
      }
      // The bloc can close while the await above is pending (e.g. logout
      // during a folder switch). emit.isDone alone does not cover that:
      // Bloc.close() (bloc 9.x) awaits _eventController.close() FIRST and
      // only cancels this handler's emitter afterwards, so a handler
      // resuming inside that first await still sees emit.isDone == false and
      // would re-arm _startPolling/_startWatching below on a bloc that is
      // already shutting down — a Timer.periodic or stream subscription
      // created after close() outlives the bloc, and the timer's add() then
      // throws an uncaught StateError once it next fires, with the folder
      // watch left running forever (PR #16 review round 6, F1). isClosed
      // flips synchronously the instant close() is called, so checking it
      // too closes that window. Bailing out here skips both the stale emit
      // and the re-arm.
      if (emit.isDone || isClosed) return;

      // Reads `state` again here instead of reusing `current`: the in-flight
      // pull's own handler can land its "pull finished" emit (isPulling:
      // false, or a pullError) while the await above was pending, and building
      // this emit from the state captured before it would resurrect a stale
      // isPulling: true over that update, wedging every later PullRequested
      // (PR #16 review round 1, F2).
      final latest = state;
      if (latest is SyncLoaded) {
        // isPulling is forced to false here rather than carried over from
        // `latest` — it describes the OLD folder's pull (if one was still in
        // flight above), which says nothing about whether this NEW folder
        // needs to wait. Forcing it in the same statement as this emit, with
        // no await before _runSync's own guard check runs next, makes that
        // guard immune to how far the old pull's own finishing sequence
        // (getDevices/getFailedEvents/its own emit, running concurrently on a
        // separate event) has gotten by this point — otherwise it could still
        // see isPulling: true and skip the new folder's first sync entirely
        // (PR #16 review round 2, finding 4).
        emit(
          latest.copyWith(
            syncFolderPath: event.path,
            isPulling: false,
            progress: () => null,
            failedFiles: 0,
          ),
        );
      } else {
        final loaded = await _fetchLoadedState();
        // Same close()-during-await guard as above (see its comment), for
        // this branch's own await — isClosed is required here too, not just
        // emit.isDone, for the same reason.
        if (emit.isDone || isClosed) return;
        emit(loaded);
      }
      _startPolling();
      _startWatching(event.path);
      // Runs the pull routine directly instead of add(const PullRequested()):
      // that event is handled concurrently with whatever else the bloc is
      // doing (bloc's default EventTransformer), so a re-dispatched event's
      // guard can still observe the old pull as in flight and return without
      // ever syncing the new folder. Calling the guard-and-run logic
      // synchronously from here, right after the isPulling override above,
      // sidesteps that race instead of relying on it resolving in time.
      //
      // The flag is cleared again here, not only at the _syncGeneration bump
      // at the top of this handler: the awaits in between (resetForNewFolder
      // waits on the coordinator's mutex, i.e. on the very run being
      // replaced) leave a window where a poll tick or watch event sets it
      // again — for the OLD folder. The old run's tail then hits the
      // generation mismatch and returns WITHOUT clearing it, so it would
      // survive into the new folder's run and earn it a pointless second scan
      // and pull.
      _syncRequestedWhileRunning = false;
      await _runSync(emit);
    } catch (e) {
      // Mirrors _onLoadSyncStatus's try/catch (PR #16 review round 4, R1): an
      // uncaught throw here — e.g. resetForNewFolder's sqflite clearAll, or a
      // SharedPreferences write failure in setSyncFolderPath — used to escape
      // this handler entirely, which kills the bloc's event processing for
      // good (a later PullRequested is never handled again, no restart short
      // of relaunching the app). Emitting the same error state every other
      // failure in this bloc gets keeps the bloc alive and gives the user the
      // page's existing Retry button (re-dispatches LoadSyncStatus).
      emit(SyncError(e.toString()));
    }
  }

  Future<void> _onPullRequested(PullRequested event, Emitter<SyncState> emit) =>
      _runSync(emit);

  /// The guarded pull-once routine shared by [_onPullRequested] and
  /// [_onSyncFolderChosen] (PR #16 review round 2, finding 4) — extracted so
  /// a folder pick can run it directly instead of going through
  /// [PullRequested]'s event queue.
  Future<void> _runSync(Emitter<SyncState> emit) async {
    final current = state;
    if (current is! SyncLoaded || current.syncFolderPath == null) {
      return;
    }
    // The isPulling check makes this re-entrancy-safe against the periodic
    // timer, the initial load, and a folder pick all firing around the same
    // time: it is read and then set synchronously (no `await` in between),
    // so a second call arriving while the first is still in flight always
    // sees it already true and never runs a second syncOnce concurrently.
    //
    // It must not DROP that request, though, which is what it used to do. A
    // run scans the disk once, at its start; SyncCoordinator's single flight
    // also hands a caller for the same path the already-running future. So a
    // file dropped into the sync folder while a run was in flight was neither
    // uploaded by that run (it scanned before the file existed) nor by a new
    // one (this returned early) — it sat there until the next 30s poll tick,
    // and the Files tab showed nothing because no run reported having pushed
    // anything. Remember the request instead and service it with exactly one
    // trailing run, however many arrive while this one is busy.
    if (current.isPulling) {
      _syncRequestedWhileRunning = true;
      return;
    }

    // Captured now, before any await: if a folder switch bumps
    // _syncGeneration while this run is in flight, comparing against the
    // live field below tells this run's tail it no longer owns the sync UI
    // state (PR #16 review round 3, finding 1).
    final generation = _syncGeneration;
    final path = current.syncFolderPath!;

    emit(
      current.copyWith(
        isPulling: true,
        pullError: () => null,
        progress: () => null,
        failedFiles: 0,
      ),
    );
    final phaseFailures = <SyncPhase, int>{};
    try {
      final result = await _syncCoordinator.syncOnce(
        path,
        onProgress: (progress) {
          if (generation != _syncGeneration || emit.isDone || isClosed) return;
          final latest = state;
          if (latest is! SyncLoaded || latest.syncFolderPath != path) return;
          phaseFailures[progress.phase] = progress.failedFiles;
          emit(
            latest.copyWith(
              progress: () => progress,
              failedFiles: phaseFailures.values.fold<int>(
                0,
                (sum, count) => sum + count,
              ),
            ),
          );
        },
      );
      // The Files tab (FileBrowserBloc) mirrors server state and otherwise
      // never refreshes after its initial load (see RemoteFileChangeNotifier's
      // doc comment) — a run that actually pulled or pushed something means
      // the server-side file list this run's own UI state might go on to
      // discard as stale (see the generation checks below) is still worth a
      // ping, since the change landed on the server either way.
      if (result.pulled > 0 || result.pushed > 0) {
        _remoteChangeNotifier.notifyChanged();
      }
      if (generation != _syncGeneration || emit.isDone || isClosed) {
        // The folder changed via SyncFolderChosen, or this bloc closed,
        // while this run was pulling — a newer run already owns the sync UI
        // state, so this tail must not overwrite it with results for a
        // folder nobody is looking at any more. Checked before the two
        // calls below (PR #16 review round 4, N1): a stale run has no use
        // for a fresh device list or failed-events count it is about to
        // throw away, so there is no reason to spend those requests.
        log(
          'stale sync run for $path finished after folder change; dropping result',
          name: 'SyncBloc',
        );
        return;
      }
      // A first pull registers the device, so the device list can now
      // include this installation — refresh it rather than assuming.
      final devices = await _dataSource.getDevices();
      final failedEvents = await _pullService.getFailedEvents();
      if (generation != _syncGeneration || emit.isDone || isClosed) {
        // A second, independent check — the one above only proves this run
        // wasn't already stale before spending the two requests just made;
        // it says nothing about whether a folder switch landed *during*
        // either await. Without this, a switch that lands here would still
        // let this tail emit the OLD folder's device list and failed-events
        // snapshot (and isPulling: false) into whatever the NEW folder's own
        // run has since put in state (PR #16 review round 5, Codex C2).
        log(
          'stale sync run for $path finished after folder change; dropping result',
          name: 'SyncBloc',
        );
        return;
      }
      final latest = state;
      if (latest is SyncLoaded) {
        emit(
          latest.copyWith(
            devices: devices.map(SyncDevice.fromJson).toList(),
            isPulling: false,
            failedEvents: failedEvents,
            progress: () => null,
          ),
        );
      }
    } catch (e) {
      if (generation != _syncGeneration || emit.isDone || isClosed) {
        log(
          'stale sync run for $path failed after folder change; dropping error',
          name: 'SyncBloc',
        );
        return;
      }
      final latest = state;
      if (latest is SyncLoaded) {
        emit(
          latest.copyWith(
            isPulling: false,
            pullError: () => e.toString(),
            progress: () => null,
          ),
        );
      }
    } finally {
      // In `finally` so it also covers the stale-generation returns above and
      // the error path: whatever ended this run, a request that arrived while
      // it was busy still has to be serviced.
      _dispatchTrailingSyncIfRequested(generation);
    }
  }

  /// Runs once more if anything asked to sync while the last run was in
  /// flight — a single trailing run no matter how many requests arrived, so a
  /// burst of watch events cannot queue a run per event.
  ///
  /// Dispatched as an event rather than calling [_runSync] directly: that
  /// keeps it behind the bloc's own event queue (no recursion, and the
  /// isPulling flag is already back to false by the time it is handled).
  void _dispatchTrailingSyncIfRequested(int generation) {
    if (!_syncRequestedWhileRunning) return;
    // A folder switch or a close bumps the generation and clears the flag
    // itself, so a mismatch here means this run is stale and the flag now
    // belongs to whoever bumped it — leave it alone.
    if (generation != _syncGeneration || isClosed) return;
    _syncRequestedWhileRunning = false;
    add(const PullRequested());
  }

  Future<SyncLoaded> _fetchLoadedState() async {
    final devices = await _dataSource.getDevices();
    return SyncLoaded(
      devices: devices.map(SyncDevice.fromJson).toList(),
      syncFolderPath: _preferences.syncFolderPath,
    );
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      _pollInterval,
      (_) => add(const PullRequested()),
    );
  }

  /// Subscribes to filesystem change events for [path], debounced so a burst
  /// of events (a save, a multi-file copy) triggers one sync, not several.
  /// Cancels any previous subscription first — used both on first load and
  /// whenever the folder changes, so switching folders never leaves the old
  /// one's watch running.
  void _startWatching(String path) {
    _stopWatching();
    try {
      _watchSubscription = _watchFolder(path).listen(
        (_) {
          _watchDebounceTimer?.cancel();
          _watchDebounceTimer = Timer(
            _watchDebounce,
            () => add(const PullRequested()),
          );
        },
        // Recursive watching is not supported on every platform (e.g.
        // Linux throws asynchronously via the stream rather than on this
        // call) — not fatal either way, since the poll timer above is the
        // fallback regardless of why the watch failed.
        onError: (Object e) =>
            log('sync folder watch failed: $path', error: e, name: 'SyncBloc'),
      );
    } catch (e) {
      log('failed to watch sync folder: $path', error: e, name: 'SyncBloc');
    }
  }

  void _stopWatching() {
    _watchDebounceTimer?.cancel();
    _watchDebounceTimer = null;
    _watchSubscription?.cancel();
    _watchSubscription = null;
  }

  @override
  Future<void> close() {
    // This bloc itself is closing — see _syncGeneration's doc comment: a
    // run still in flight at this point must not try to emit into a bloc
    // that is closing.
    _syncGeneration++;
    _syncRequestedWhileRunning = false;
    _pollTimer?.cancel();
    _stopWatching();
    return super.close();
  }
}

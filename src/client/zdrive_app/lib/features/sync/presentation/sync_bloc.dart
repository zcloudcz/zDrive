import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/storage/app_preferences.dart';
import '../data/pull_sync_service.dart';
import '../data/sync_coordinator.dart';
import '../data/sync_remote_data_source.dart';
import '../domain/sync_mirror_entry.dart';
import '../domain/sync_models.dart';

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

  const SyncLoaded({
    required this.devices,
    this.syncFolderPath,
    this.isPulling = false,
    this.pullError,
    this.failedEvents = const [],
  });

  SyncLoaded copyWith({
    List<SyncDevice>? devices,
    String? syncFolderPath,
    bool? isPulling,
    String? Function()? pullError,
    List<SyncFailedEvent>? failedEvents,
  }) {
    return SyncLoaded(
      devices: devices ?? this.devices,
      syncFolderPath: syncFolderPath ?? this.syncFolderPath,
      isPulling: isPulling ?? this.isPulling,
      pullError: pullError != null ? pullError() : this.pullError,
      failedEvents: failedEvents ?? this.failedEvents,
    );
  }

  @override
  List<Object?> get props => [devices, syncFolderPath, isPulling, pullError, failedEvents];
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

  SyncBloc({
    required SyncRemoteDataSource dataSource,
    required SyncCoordinator syncCoordinator,
    required PullSyncService pullService,
    required AppPreferences preferences,
    required String userId,
    Stream<FileSystemEvent> Function(String path)? watch,
  })  : _dataSource = dataSource,
        _syncCoordinator = syncCoordinator,
        _pullService = pullService,
        _preferences = preferences,
        _userId = userId,
        // Defaults to a real recursive folder watch; tests inject a fake so
        // they can drive events without touching the filesystem.
        _watchFolder = watch ?? ((path) => Directory(path).watch(recursive: true)),
        super(const SyncInitial()) {
    on<LoadSyncStatus>(_onLoadSyncStatus);
    on<SyncFolderChosen>(_onSyncFolderChosen);
    on<PullRequested>(_onPullRequested);
  }

  Future<void> _onLoadSyncStatus(
    LoadSyncStatus event,
    Emitter<SyncState> emit,
  ) async {
    // Re-enables syncOnce after a previous session's endSession, and — if
    // this machine's stored sync state belongs to a different account than
    // _userId — clears it first, so that account never inherits the
    // previous user's mirror, device id or folder. See
    // SyncCoordinator.startSession's doc comment.
    await _syncCoordinator.startSession(_userId);
    emit(const SyncLoading());
    try {
      final loaded = await _fetchLoadedState();
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
    final current = state;
    final previousPath = current is SyncLoaded ? current.syncFolderPath : _preferences.syncFolderPath;
    if (previousPath != null && previousPath != event.path) {
      // A different folder than the one already configured starts sync
      // over from a clean slate — see resetForNewFolder's doc comment. This
      // awaits the coordinator's mutex, i.e. waits for any pull already in
      // flight to finish — which is why the emit below reads `state` again
      // instead of reusing `current`: the in-flight pull's own handler can
      // land its "pull finished" emit (isPulling: false, or a pullError)
      // while this await is pending, and building the next emit from the
      // state captured before it would resurrect a stale isPulling: true
      // over that update, wedging every later PullRequested (PR #16 review
      // round 1, F2).
      await _syncCoordinator.resetForNewFolder();
    }
    await _preferences.setSyncFolderPath(event.path);

    final latest = state;
    if (latest is SyncLoaded) {
      emit(latest.copyWith(syncFolderPath: event.path));
    } else {
      emit(await _fetchLoadedState());
    }
    _startPolling();
    _startWatching(event.path);
    add(const PullRequested());
  }

  Future<void> _onPullRequested(
    PullRequested event,
    Emitter<SyncState> emit,
  ) async {
    final current = state;
    // The isPulling check makes this re-entrancy-safe against the periodic
    // timer, the initial load, and a folder pick all firing PullRequested
    // around the same time: it is read and then set synchronously (no
    // `await` in between), so a second call arriving while the first is
    // still in flight always sees it already true and returns immediately
    // instead of running a second pullOnce concurrently.
    if (current is! SyncLoaded || current.syncFolderPath == null || current.isPulling) {
      return;
    }

    emit(current.copyWith(isPulling: true, pullError: () => null));
    try {
      await _syncCoordinator.syncOnce(current.syncFolderPath!);
      // A first pull registers the device, so the device list can now
      // include this installation — refresh it rather than assuming.
      final devices = await _dataSource.getDevices();
      final failedEvents = await _pullService.getFailedEvents();
      final latest = state;
      if (latest is SyncLoaded) {
        emit(latest.copyWith(
          devices: devices.map(SyncDevice.fromJson).toList(),
          isPulling: false,
          failedEvents: failedEvents,
        ));
      }
    } catch (e) {
      final latest = state;
      if (latest is SyncLoaded) {
        emit(latest.copyWith(isPulling: false, pullError: () => e.toString()));
      }
    }
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
    _pollTimer = Timer.periodic(_pollInterval, (_) => add(const PullRequested()));
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
          _watchDebounceTimer = Timer(_watchDebounce, () => add(const PullRequested()));
        },
        // Recursive watching is not supported on every platform (e.g.
        // Linux throws asynchronously via the stream rather than on this
        // call) — not fatal either way, since the poll timer above is the
        // fallback regardless of why the watch failed.
        onError: (Object e) => log('sync folder watch failed: $path', error: e, name: 'SyncBloc'),
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
    _pollTimer?.cancel();
    _stopWatching();
    return super.close();
  }
}

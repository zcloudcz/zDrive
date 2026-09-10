import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/storage/app_preferences.dart';
import '../data/pull_sync_service.dart';
import '../data/sync_remote_data_source.dart';
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
  final List<SyncConflict> conflicts;
  final String? syncFolderPath;
  final bool isPulling;
  final String? pullError;

  const SyncLoaded({
    required this.devices,
    required this.conflicts,
    this.syncFolderPath,
    this.isPulling = false,
    this.pullError,
  });

  SyncLoaded copyWith({
    List<SyncDevice>? devices,
    List<SyncConflict>? conflicts,
    String? syncFolderPath,
    bool? isPulling,
    String? Function()? pullError,
  }) {
    return SyncLoaded(
      devices: devices ?? this.devices,
      conflicts: conflicts ?? this.conflicts,
      syncFolderPath: syncFolderPath ?? this.syncFolderPath,
      isPulling: isPulling ?? this.isPulling,
      pullError: pullError != null ? pullError() : this.pullError,
    );
  }

  @override
  List<Object?> get props =>
      [devices, conflicts, syncFolderPath, isPulling, pullError];
}

final class SyncError extends SyncState {
  final String message;

  const SyncError(this.message);

  @override
  List<Object?> get props => [message];
}

// --- Bloc ---

/// Status page for the (Phase 2) sync engine: registered devices, pending
/// conflicts, and — as of this change — the designated sync folder and the
/// pull loop that keeps it up to date. Push (uploading local changes) is a
/// separate, later task: this bloc only ever pulls.
class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final SyncRemoteDataSource _dataSource;
  final PullSyncService _pullService;
  final AppPreferences _preferences;

  // Polling, not SignalR: the hub has no backplane configured at
  // max_replicas=3, so a client subscribed to one replica would miss events
  // raised on another. 30s balances "changes show up promptly" against
  // hammering the gateway from every idle desktop client; short enough that
  // a user waiting on a sync does not perceive it as stalled, long enough
  // that it is not a meaningful load source at MVP scale.
  static const _pollInterval = Duration(seconds: 30);

  Timer? _pollTimer;

  SyncBloc({
    required SyncRemoteDataSource dataSource,
    required PullSyncService pullService,
    required AppPreferences preferences,
  })  : _dataSource = dataSource,
        _pullService = pullService,
        _preferences = preferences,
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
      final loaded = await _fetchLoadedState();
      emit(loaded);
      if (loaded.syncFolderPath != null) {
        _startPolling();
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
    await _preferences.setSyncFolderPath(event.path);
    final current = state;
    if (current is SyncLoaded) {
      emit(current.copyWith(syncFolderPath: event.path));
    } else {
      emit(await _fetchLoadedState());
    }
    _startPolling();
    add(const PullRequested());
  }

  Future<void> _onPullRequested(
    PullRequested event,
    Emitter<SyncState> emit,
  ) async {
    final current = state;
    if (current is! SyncLoaded || current.syncFolderPath == null) return;

    emit(current.copyWith(isPulling: true, pullError: () => null));
    try {
      await _pullService.pullOnce(current.syncFolderPath!);
      // A first pull registers the device, so the device list can now
      // include this installation — refresh it rather than assuming.
      final devices = await _dataSource.getDevices();
      final latest = state;
      if (latest is SyncLoaded) {
        emit(latest.copyWith(
          devices: devices.map(SyncDevice.fromJson).toList(),
          isPulling: false,
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
    final results = await Future.wait([
      _dataSource.getDevices(),
      _dataSource.getConflicts(),
    ]);
    return SyncLoaded(
      devices: results[0].map(SyncDevice.fromJson).toList(),
      // GetConflictsQueryHandler (SyncService) filters only on user, not
      // status, because the same endpoint backs a resolved-conflict
      // integration check (SyncFlowTests.ResolveConflict_StatusUpdated).
      // This page only cares about conflicts still needing action, so the
      // filter lives here instead of narrowing the shared query. Wire
      // value is "Pending" (ConflictStatus.ToString()), not lowercase.
      conflicts: results[1]
          .map(SyncConflict.fromJson)
          .where((c) => c.status == 'Pending')
          .toList(),
      syncFolderPath: _preferences.syncFolderPath,
    );
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => add(const PullRequested()));
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    return super.close();
  }
}

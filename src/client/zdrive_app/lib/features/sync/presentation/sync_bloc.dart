import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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

  const SyncLoaded({required this.devices, required this.conflicts});

  @override
  List<Object?> get props => [devices, conflicts];
}

final class SyncError extends SyncState {
  final String message;

  const SyncError(this.message);

  @override
  List<Object?> get props => [message];
}

// --- Bloc ---

/// Status page for the (Phase 2) sync engine: registered devices and any
/// pending conflicts. Read-only — conflict resolution is a separate task.
class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final SyncRemoteDataSource _dataSource;

  SyncBloc({required SyncRemoteDataSource dataSource})
      : _dataSource = dataSource,
        super(const SyncInitial()) {
    on<LoadSyncStatus>(_onLoadSyncStatus);
  }

  Future<void> _onLoadSyncStatus(
    LoadSyncStatus event,
    Emitter<SyncState> emit,
  ) async {
    emit(const SyncLoading());
    try {
      final results = await Future.wait([
        _dataSource.getDevices(),
        _dataSource.getConflicts(),
      ]);
      emit(SyncLoaded(
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
      ));
    } catch (e) {
      emit(SyncError(e.toString()));
    }
  }
}

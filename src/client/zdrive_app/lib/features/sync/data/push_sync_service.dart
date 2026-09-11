import 'package:injectable/injectable.dart';

import '../domain/sync_mirror_repository.dart';
import 'device_registration_service.dart';
import 'sync_remote_data_source.dart';

/// Mirrors SyncService's `SyncEventType` enum by declaration order — the
/// server binds it from the ordinal, not the name (see
/// [SyncRemoteDataSource.push]), so this enum's order must keep matching
/// `ZDrive.SyncService.Domain.Enums.SyncEventType` exactly.
enum SyncChangeType { create, update, delete, move, rename }

/// The entry point the files feature calls once one of its own local
/// operations (upload, rename, move, delete) has succeeded, so other
/// devices learn about it on their next pull. This does not touch local
/// disk or the mirror — it only reports to the server what already
/// happened; [PullSyncService] is what applies changes on the receiving
/// end.
@lazySingleton
class PushSyncService {
  final SyncRemoteDataSource _syncDataSource;
  final DeviceRegistrationService _deviceRegistration;
  final SyncMirrorRepository _mirror;

  PushSyncService(this._syncDataSource, this._deviceRegistration, this._mirror);

  /// Reports one local change for [fileId] to the server.
  Future<void> reportChange(String fileId, SyncChangeType type) async {
    final deviceId = await _deviceRegistration.ensureRegistered();
    // The pull cursor this device had already applied at the time of the
    // change — sent as baseCursor so the server can tell "I pushed after
    // seeing everything up to here" from a push based on stale knowledge
    // (see SyncRemoteDataSource.push's doc comment).
    final baseCursor = await _mirror.getCursor(deviceId);
    await _syncDataSource.push(
      deviceId,
      [
        {'fileId': fileId, 'eventType': type.index, 'metadata': null},
      ],
      baseCursor: baseCursor,
    );
  }
}

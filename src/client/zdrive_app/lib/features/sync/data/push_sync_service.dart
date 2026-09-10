import 'package:injectable/injectable.dart';

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

  PushSyncService(this._syncDataSource, this._deviceRegistration);

  /// Reports one local change for [fileId] to the server.
  Future<void> reportChange(String fileId, SyncChangeType type) async {
    final deviceId = await _deviceRegistration.ensureRegistered();
    await _syncDataSource.push(deviceId, [
      {'fileId': fileId, 'eventType': type.index, 'metadata': null},
    ]);
  }
}

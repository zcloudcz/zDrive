import 'package:injectable/injectable.dart';

import 'current_device_platform.dart';
import 'device_id_storage.dart';
import 'sync_remote_data_source.dart';

/// Registers this installation as a sync device and remembers the id.
///
/// Desktop only (Windows/macOS) — the only platforms the designated-folder
/// sync feature targets ([CurrentDevicePlatform] enforces that).
@lazySingleton
class DeviceRegistrationService {
  final SyncRemoteDataSource _dataSource;
  final DeviceIdStorage _idStorage;
  final CurrentDevicePlatform _platform;

  DeviceRegistrationService(this._dataSource, this._idStorage, this._platform);

  /// Returns this installation's device id, registering with the server if
  /// there is none yet, or if the stored id was deleted server-side (e.g. the
  /// user removed the device from another client) — in which case a fresh
  /// registration replaces it. Pull is always scoped to whatever id this
  /// returns, so a stale id would otherwise make every pull fail with 404.
  Future<String> ensureRegistered() async {
    final storedId = await _idStorage.deviceId;
    if (storedId != null) {
      final devices = await _dataSource.getDevices();
      if (devices.any((d) => d['id'] == storedId)) {
        return storedId;
      }
    }

    final device = await _dataSource.registerDevice(_platform.name, _platform.ordinal);
    final newId = device['id'] as String;
    await _idStorage.saveDeviceId(newId);
    return newId;
  }
}

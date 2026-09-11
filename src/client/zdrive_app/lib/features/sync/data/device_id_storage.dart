import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

/// Persists this installation's sync device id across app restarts.
///
/// Secure storage (not Hive) because a device id is an identity credential —
/// it scopes what the server will hand back on pull — the same reasoning
/// [TokenStorage] uses for auth tokens.
@lazySingleton
class DeviceIdStorage {
  static const _deviceIdKey = 'sync_device_id';

  final FlutterSecureStorage _storage;

  DeviceIdStorage() : _storage = const FlutterSecureStorage();

  Future<String?> get deviceId => _storage.read(key: _deviceIdKey);

  Future<void> saveDeviceId(String id) => _storage.write(key: _deviceIdKey, value: id);
}

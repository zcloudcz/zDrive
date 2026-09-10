import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../../../core/network/api_envelope.dart';

@lazySingleton
class SyncRemoteDataSource {
  final Dio _dio;

  SyncRemoteDataSource(this._dio);

  Future<List<Map<String, dynamic>>> getDevices() async {
    final response = await _dio.get('/sync/devices');
    return unwrapMapList(response);
  }

  // `platform` is the ordinal of SyncService's `DevicePlatform` enum
  // (Windows=0, MacOS=1, Android=2, iOS=3, Web=4), not its name — SyncService
  // registers no JsonStringEnumConverter (unlike FileService/NotificationService),
  // so System.Text.Json's default enum binding only accepts the numeric value.
  Future<Map<String, dynamic>> registerDevice(String name, int platform) async {
    final response = await _dio.post('/sync/devices', data: {'name': name, 'platform': platform});
    return unwrapMap(response);
  }

  Future<void> unregisterDevice(String id) async {
    final response = await _dio.delete('/sync/devices/$id');
    ensureSuccess(response);
  }

  /// Pulls sync events for [deviceId] created after [cursor]. The cursor is
  /// entirely client-owned: PullChangesQueryHandler is read-only and never
  /// writes it server-side (only push does, and to a different field), so
  /// nothing here can be used as a source of truth for "what was pulled" —
  /// the caller must persist `newCursor` itself.
  Future<Map<String, dynamic>> pull(String deviceId, int cursor) async {
    final response = await _dio.post(
      '/sync/pull',
      data: {'deviceId': deviceId, 'cursor': cursor},
    );
    return unwrapMap(response);
  }

  Future<List<Map<String, dynamic>>> getConflicts() async {
    final response = await _dio.get('/sync/conflicts');
    return unwrapMapList(response);
  }

  Future<void> resolveConflict(String id, String resolution) async {
    final response = await _dio.post('/sync/conflicts/$id/resolve', data: {'resolution': resolution});
    ensureSuccess(response);
  }
}

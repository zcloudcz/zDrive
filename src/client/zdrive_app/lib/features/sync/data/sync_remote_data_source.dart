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
}

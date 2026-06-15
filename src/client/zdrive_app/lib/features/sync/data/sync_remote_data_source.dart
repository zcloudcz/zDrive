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

  Future<Map<String, dynamic>> registerDevice(String name, String platform) async {
    final response = await _dio.post('/sync/devices', data: {'name': name, 'platform': platform});
    return unwrapMap(response);
  }

  Future<void> unregisterDevice(String id) async {
    final response = await _dio.delete('/sync/devices/$id');
    ensureSuccess(response);
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

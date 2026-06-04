import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class SyncRemoteDataSource {
  final Dio _dio;

  SyncRemoteDataSource(this._dio);

  Future<List<Map<String, dynamic>>> getDevices() async {
    final response = await _dio.get('/sync/devices');
    return (response.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> registerDevice(String name, String platform) async {
    final response = await _dio.post('/sync/devices', data: {'name': name, 'platform': platform});
    return response.data as Map<String, dynamic>;
  }

  Future<void> unregisterDevice(String id) async {
    await _dio.delete('/sync/devices/$id');
  }

  Future<List<Map<String, dynamic>>> getConflicts() async {
    final response = await _dio.get('/sync/conflicts');
    return (response.data as List).cast<Map<String, dynamic>>();
  }

  Future<void> resolveConflict(String id, String resolution) async {
    await _dio.post('/sync/conflicts/$id/resolve', data: {'resolution': resolution});
  }
}

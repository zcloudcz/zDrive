import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late SyncRemoteDataSource dataSource;

  // Wraps payloads in the backend envelope { success, data, error }.
  Response<dynamic> response(dynamic data, String path) => Response<dynamic>(
        data: {'success': true, 'data': data, 'error': null},
        statusCode: 200,
        requestOptions: RequestOptions(path: path),
      );

  setUp(() {
    dio = MockDio();
    dataSource = SyncRemoteDataSource(dio);
  });

  test('getDevices calls GET /sync/devices and returns the device list', () async {
    final devices = [
      {'id': 'dev-1', 'name': 'Laptop', 'platform': 'windows'},
      {'id': 'dev-2', 'name': 'Phone', 'platform': 'android'},
    ];
    when(() => dio.get('/sync/devices'))
        .thenAnswer((_) async => response(devices, '/sync/devices'));

    final result = await dataSource.getDevices();

    expect(result, hasLength(2));
    expect(result.first['id'], 'dev-1');
    verify(() => dio.get('/sync/devices')).called(1);
  });

  test('registerDevice posts name and the platform ordinal and returns the created device', () async {
    final created = {'id': 'dev-3', 'name': 'Tablet', 'platform': 'iOS'};
    // SyncService binds DevicePlatform from the raw System.Text.Json enum
    // encoding (no JsonStringEnumConverter registered), i.e. the ordinal —
    // 3 for iOS — not the name.
    when(() => dio.post('/sync/devices', data: {'name': 'Tablet', 'platform': 3}))
        .thenAnswer((_) async => response(created, '/sync/devices'));

    final result = await dataSource.registerDevice('Tablet', 3);

    expect(result['id'], 'dev-3');
    verify(() => dio.post('/sync/devices', data: {'name': 'Tablet', 'platform': 3}))
        .called(1);
  });

  test('unregisterDevice deletes the device by id', () async {
    when(() => dio.delete('/sync/devices/dev-1'))
        .thenAnswer((_) async => response(null, '/sync/devices/dev-1'));

    await dataSource.unregisterDevice('dev-1');

    verify(() => dio.delete('/sync/devices/dev-1')).called(1);
  });

  test('heartbeat posts to the device heartbeat endpoint', () async {
    when(() => dio.post('/sync/devices/dev-1/heartbeat'))
        .thenAnswer((_) async => response(true, '/sync/devices/dev-1/heartbeat'));

    await dataSource.heartbeat('dev-1');

    verify(() => dio.post('/sync/devices/dev-1/heartbeat')).called(1);
  });

  test('propagates DioException from the HTTP layer', () async {
    when(() => dio.get('/sync/devices')).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/sync/devices'),
        type: DioExceptionType.connectionError,
      ),
    );

    expect(dataSource.getDevices, throwsA(isA<DioException>()));
  });
}

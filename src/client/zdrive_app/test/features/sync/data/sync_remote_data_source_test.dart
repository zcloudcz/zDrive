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

  test('getConflicts calls GET /sync/conflicts and returns the conflict list', () async {
    final conflicts = [
      {'id': 'c-1', 'fileId': 'f-1', 'status': 'pending'},
    ];
    when(() => dio.get('/sync/conflicts'))
        .thenAnswer((_) async => response(conflicts, '/sync/conflicts'));

    final result = await dataSource.getConflicts();

    expect(result.single['status'], 'pending');
  });

  test('resolveConflict posts the chosen resolution', () async {
    when(() => dio.post('/sync/conflicts/c-1/resolve', data: {'resolution': 'keepLocal'}))
        .thenAnswer((_) async => response(null, '/sync/conflicts/c-1/resolve'));

    await dataSource.resolveConflict('c-1', 'keepLocal');

    verify(() => dio.post('/sync/conflicts/c-1/resolve', data: {'resolution': 'keepLocal'}))
        .called(1);
  });

  test('pull posts deviceId and cursor and returns events plus the new cursor', () async {
    final pullData = {
      'events': [
        {'id': 5, 'fileId': 'f-1', 'eventType': 'Create', 'metadata': null},
      ],
      'newCursor': 5,
    };
    when(() => dio.post('/sync/pull', data: {'deviceId': 'dev-1', 'cursor': 0}))
        .thenAnswer((_) async => response(pullData, '/sync/pull'));

    final pullResult = await dataSource.pull('dev-1', 0);

    expect(pullResult['newCursor'], 5);
    verify(() => dio.post('/sync/pull', data: {'deviceId': 'dev-1', 'cursor': 0})).called(1);
  });

  test('push posts deviceId and the events, eventType as the ordinal', () async {
    final events = [
      {'fileId': 'f-1', 'eventType': 0, 'metadata': null},
    ];
    when(() => dio.post('/sync/push', data: {'deviceId': 'dev-1', 'events': events}))
        .thenAnswer((_) async => response({'newCursor': 9, 'conflicts': []}, '/sync/push'));

    final result = await dataSource.push('dev-1', events);

    expect(result['newCursor'], 9);
    verify(() => dio.post('/sync/push', data: {'deviceId': 'dev-1', 'events': events}))
        .called(1);
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

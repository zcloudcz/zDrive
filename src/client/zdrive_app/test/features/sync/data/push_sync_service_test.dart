import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/sync/data/device_registration_service.dart';
import 'package:zdrive_app/features/sync/data/push_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

class MockDeviceRegistrationService extends Mock implements DeviceRegistrationService {}

void main() {
  late MockSyncRemoteDataSource mockDataSource;
  late MockDeviceRegistrationService mockDeviceRegistration;
  late PushSyncService service;

  setUp(() {
    mockDataSource = MockSyncRemoteDataSource();
    mockDeviceRegistration = MockDeviceRegistrationService();
    service = PushSyncService(mockDataSource, mockDeviceRegistration);

    when(() => mockDeviceRegistration.ensureRegistered()).thenAnswer((_) async => 'dev-1');
  });

  test('reportChange registers the device if needed and posts the event with '
      'the ordinal of SyncEventType', () async {
    when(() => mockDataSource.push('dev-1', any())).thenAnswer((_) async => {});

    await service.reportChange('file-1', SyncChangeType.create);

    verify(() => mockDataSource.push('dev-1', [
          {'fileId': 'file-1', 'eventType': 0, 'metadata': null},
        ])).called(1);
  });

  test('SyncChangeType ordinals match SyncService\'s SyncEventType enum order '
      '(Create=0, Update=1, Delete=2, Move=3, Rename=4)', () {
    expect(SyncChangeType.create.index, 0);
    expect(SyncChangeType.update.index, 1);
    expect(SyncChangeType.delete.index, 2);
    expect(SyncChangeType.move.index, 3);
    expect(SyncChangeType.rename.index, 4);
  });
}

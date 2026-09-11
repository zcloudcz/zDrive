import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/sync/data/device_registration_service.dart';
import 'package:zdrive_app/features/sync/data/push_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_repository.dart';

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

class MockDeviceRegistrationService extends Mock implements DeviceRegistrationService {}

class MockSyncMirrorRepository extends Mock implements SyncMirrorRepository {}

void main() {
  late MockSyncRemoteDataSource mockDataSource;
  late MockDeviceRegistrationService mockDeviceRegistration;
  late MockSyncMirrorRepository mockMirror;
  late PushSyncService service;

  setUp(() {
    mockDataSource = MockSyncRemoteDataSource();
    mockDeviceRegistration = MockDeviceRegistrationService();
    mockMirror = MockSyncMirrorRepository();
    service = PushSyncService(mockDataSource, mockDeviceRegistration, mockMirror);

    when(() => mockDeviceRegistration.ensureRegistered()).thenAnswer((_) async => 'dev-1');
    when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 7);
  });

  test('reportChange registers the device if needed and posts the event with '
      'the ordinal of SyncEventType, plus this device\'s current pull cursor '
      'as baseCursor', () async {
    when(() => mockDataSource.push('dev-1', any(), baseCursor: any(named: 'baseCursor')))
        .thenAnswer((_) async => {});

    await service.reportChange('file-1', SyncChangeType.create);

    verify(() => mockDataSource.push(
          'dev-1',
          [
            {'fileId': 'file-1', 'eventType': 0, 'metadata': null},
          ],
          baseCursor: 7,
        )).called(1);
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

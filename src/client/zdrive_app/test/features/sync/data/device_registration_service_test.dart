import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/sync/data/current_device_platform.dart';
import 'package:zdrive_app/features/sync/data/device_id_storage.dart';
import 'package:zdrive_app/features/sync/data/device_registration_service.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

class MockDeviceIdStorage extends Mock implements DeviceIdStorage {}

class MockCurrentDevicePlatform extends Mock implements CurrentDevicePlatform {}

void main() {
  late MockSyncRemoteDataSource mockDataSource;
  late MockDeviceIdStorage mockIdStorage;
  late MockCurrentDevicePlatform mockPlatform;
  late DeviceRegistrationService service;

  setUp(() {
    mockDataSource = MockSyncRemoteDataSource();
    mockIdStorage = MockDeviceIdStorage();
    mockPlatform = MockCurrentDevicePlatform();
    // Fixed stand-in for "this machine" so the test does not depend on which
    // OS actually runs it (CI runs flutter test on Linux).
    when(() => mockPlatform.name).thenReturn('Test PC');
    when(() => mockPlatform.ordinal).thenReturn(platformOrdinalWindows);
    service = DeviceRegistrationService(mockDataSource, mockIdStorage, mockPlatform);
  });

  test('registers a new device when none is stored, and persists the returned id', () async {
    when(() => mockIdStorage.deviceId).thenAnswer((_) async => null);
    when(() => mockDataSource.registerDevice('Test PC', platformOrdinalWindows)).thenAnswer(
      (_) async => {'id': 'dev-new', 'name': 'Test PC', 'platform': 'Windows'},
    );
    when(() => mockIdStorage.saveDeviceId('dev-new')).thenAnswer((_) async {});

    final id = await service.ensureRegistered();

    expect(id, 'dev-new');
    verify(() => mockDataSource.registerDevice('Test PC', platformOrdinalWindows)).called(1);
    verify(() => mockIdStorage.saveDeviceId('dev-new')).called(1);
  });

  test('reuses the stored id when the server still lists it, without re-registering', () async {
    when(() => mockIdStorage.deviceId).thenAnswer((_) async => 'dev-existing');
    when(() => mockDataSource.getDevices()).thenAnswer((_) async => [
          {'id': 'dev-existing', 'name': 'This PC', 'platform': 'Windows'},
          {'id': 'dev-other', 'name': 'Phone', 'platform': 'iOS'},
        ]);

    final id = await service.ensureRegistered();

    expect(id, 'dev-existing');
    verifyNever(() => mockDataSource.registerDevice(any(), any()));
    verifyNever(() => mockIdStorage.saveDeviceId(any()));
  });

  test('registers a fresh device and overwrites the stored id when the old one is gone server-side',
      () async {
    when(() => mockIdStorage.deviceId).thenAnswer((_) async => 'dev-deleted');
    when(() => mockDataSource.getDevices()).thenAnswer((_) async => [
          {'id': 'dev-other', 'name': 'Phone', 'platform': 'iOS'},
        ]);
    when(() => mockDataSource.registerDevice('Test PC', platformOrdinalWindows)).thenAnswer(
      (_) async => {'id': 'dev-fresh', 'name': 'Test PC', 'platform': 'Windows'},
    );
    when(() => mockIdStorage.saveDeviceId('dev-fresh')).thenAnswer((_) async {});

    final id = await service.ensureRegistered();

    expect(id, 'dev-fresh');
    verify(() => mockDataSource.registerDevice('Test PC', platformOrdinalWindows)).called(1);
    verify(() => mockIdStorage.saveDeviceId('dev-fresh')).called(1);
  });
}

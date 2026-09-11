import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zdrive_app/features/sync/data/device_registration_service.dart';
import 'package:zdrive_app/features/sync/data/push_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sqflite_sync_mirror_repository.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_entry.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_repository.dart';

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

class MockDeviceRegistrationService extends Mock implements DeviceRegistrationService {}

class MockSyncMirrorRepository extends Mock implements SyncMirrorRepository {}

class FakeOutboxItem extends Fake implements OutboxItem {}

void main() {
  late MockSyncRemoteDataSource mockDataSource;
  late MockDeviceRegistrationService mockDeviceRegistration;
  late MockSyncMirrorRepository mockMirror;
  late PushSyncService service;

  setUpAll(() {
    registerFallbackValue(FakeOutboxItem());
    registerFallbackValue(<OutboxItem>[]);
  });

  setUp(() {
    mockDataSource = MockSyncRemoteDataSource();
    mockDeviceRegistration = MockDeviceRegistrationService();
    mockMirror = MockSyncMirrorRepository();
    service = PushSyncService(mockDataSource, mockDeviceRegistration, mockMirror);

    when(() => mockDeviceRegistration.ensureRegistered()).thenAnswer((_) async => 'dev-1');
    when(() => mockDeviceRegistration.localDeviceId()).thenAnswer((_) async => 'dev-1');
    when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 7);
  });

  group('reportChange', () {
    test('enqueues the event (with this device\'s pull cursor as '
        'baseCursor) then immediately drains it', () async {
      when(() => mockMirror.commit(enqueue: any(named: 'enqueue'))).thenAnswer((_) async {});
      when(() => mockMirror.peekOutbox()).thenAnswer((_) async => [
            OutboxItem(id: 1, fileId: 'file-1', type: SyncChangeType.create, baseCursor: 7, createdAt: DateTime.now()),
          ]);
      when(() => mockDataSource.push('dev-1', any(), baseCursor: 7)).thenAnswer((_) async => {});
      when(() => mockMirror.removeOutbox(1)).thenAnswer((_) async {});

      await service.reportChange('file-1', SyncChangeType.create);

      final enqueued = verify(() => mockMirror.commit(enqueue: captureAny(named: 'enqueue')))
          .captured
          .single as List<OutboxItem>;
      expect(enqueued, hasLength(1));
      expect(enqueued.single.fileId, 'file-1');
      expect(enqueued.single.type, SyncChangeType.create);
      expect(enqueued.single.baseCursor, 7);
      verify(() => mockDataSource.push(
            'dev-1',
            [
              {'fileId': 'file-1', 'eventType': 0, 'metadata': null},
            ],
            baseCursor: 7,
          )).called(1);
      verify(() => mockMirror.removeOutbox(1)).called(1);
    });

    test('a drain failure is swallowed — the item stays enqueued, '
        'reportChange itself does not throw', () async {
      when(() => mockMirror.commit(enqueue: any(named: 'enqueue'))).thenAnswer((_) async {});
      when(() => mockMirror.peekOutbox()).thenAnswer((_) async => [
            OutboxItem(id: 1, fileId: 'file-1', type: SyncChangeType.create, baseCursor: 7, createdAt: DateTime.now()),
          ]);
      when(() => mockDataSource.push(any(), any(), baseCursor: any(named: 'baseCursor')))
          .thenThrow(Exception('unreachable'));

      await service.reportChange('file-1', SyncChangeType.create);

      verifyNever(() => mockMirror.removeOutbox(any()));
    });

    test('enqueueing needs no network call: ensureRegistered throwing does '
        'not stop the item from being queued, and reportChange itself does '
        'not throw (PR #14 review round 4, R4-1)', () async {
      // A real repository, not mockMirror, so the assertion below
      // (outboxCount == 1) reflects an actual queued row rather than a
      // hand-picked mock stub.
      final mirror = SqfliteSyncMirrorRepository.withDbPath(inMemoryDatabasePath);
      addTearDown(() async => (await mirror.debugDatabase).close());
      final freshDeviceRegistration = MockDeviceRegistrationService();
      final freshDataSource = MockSyncRemoteDataSource();
      when(() => freshDeviceRegistration.localDeviceId()).thenAnswer((_) async => 'dev-1');
      when(() => freshDeviceRegistration.ensureRegistered())
          .thenThrow(Exception('SyncService unreachable'));
      final freshService = PushSyncService(freshDataSource, freshDeviceRegistration, mirror);

      await freshService.reportChange('file-1', SyncChangeType.create);

      expect(await mirror.outboxCount(), 1);
    });

    test('SyncChangeType ordinals match SyncService\'s SyncEventType enum order '
        '(Create=0, Update=1, Delete=2, Move=3, Rename=4)', () {
      expect(SyncChangeType.create.index, 0);
      expect(SyncChangeType.update.index, 1);
      expect(SyncChangeType.delete.index, 2);
      expect(SyncChangeType.move.index, 3);
      expect(SyncChangeType.rename.index, 4);
    });
  });

  group('drainOutbox', () {
    test('sends items oldest-first, each with its own stored baseCursor, '
        'and removes each once sent', () async {
      when(() => mockMirror.peekOutbox()).thenAnswer((_) async => [
            OutboxItem(id: 1, fileId: 'file-1', type: SyncChangeType.create, baseCursor: 3, createdAt: DateTime.now()),
            OutboxItem(id: 2, fileId: 'file-2', type: SyncChangeType.update, baseCursor: 5, createdAt: DateTime.now()),
          ]);
      when(() => mockDataSource.push('dev-1', any(), baseCursor: any(named: 'baseCursor')))
          .thenAnswer((_) async => {});
      when(() => mockMirror.removeOutbox(any())).thenAnswer((_) async {});

      final sent = await service.drainOutbox();

      expect(sent, 2);
      verifyInOrder([
        () => mockDataSource.push(
              'dev-1',
              [
                {'fileId': 'file-1', 'eventType': 0, 'metadata': null},
              ],
              baseCursor: 3,
            ),
        () => mockMirror.removeOutbox(1),
        () => mockDataSource.push(
              'dev-1',
              [
                {'fileId': 'file-2', 'eventType': 1, 'metadata': null},
              ],
              baseCursor: 5,
            ),
        () => mockMirror.removeOutbox(2),
      ]);
    });

    test('stops at the first failure — that item and everything after it '
        'stay queued, only what already sent counts', () async {
      when(() => mockMirror.peekOutbox()).thenAnswer((_) async => [
            OutboxItem(id: 1, fileId: 'file-1', type: SyncChangeType.create, baseCursor: 1, createdAt: DateTime.now()),
            OutboxItem(id: 2, fileId: 'file-2', type: SyncChangeType.update, baseCursor: 2, createdAt: DateTime.now()),
            OutboxItem(id: 3, fileId: 'file-3', type: SyncChangeType.delete, baseCursor: 3, createdAt: DateTime.now()),
          ]);
      when(() => mockMirror.removeOutbox(1)).thenAnswer((_) async {});
      when(() => mockDataSource.push('dev-1', [
            {'fileId': 'file-1', 'eventType': 0, 'metadata': null},
          ], baseCursor: 1)).thenAnswer((_) async => {});
      when(() => mockDataSource.push('dev-1', [
            {'fileId': 'file-2', 'eventType': 1, 'metadata': null},
          ], baseCursor: 2)).thenThrow(Exception('unreachable'));

      final sent = await service.drainOutbox();

      expect(sent, 1);
      verify(() => mockMirror.removeOutbox(1)).called(1);
      verifyNever(() => mockMirror.removeOutbox(2));
      verifyNever(() => mockMirror.removeOutbox(3));
      verifyNever(() => mockDataSource.push('dev-1', [
            {'fileId': 'file-3', 'eventType': 2, 'metadata': null},
          ], baseCursor: 3));
    });

    test('an empty outbox sends nothing and returns 0', () async {
      when(() => mockMirror.peekOutbox()).thenAnswer((_) async => []);

      final sent = await service.drainOutbox();

      expect(sent, 0);
      verifyNever(() => mockDataSource.push(any(), any(), baseCursor: any(named: 'baseCursor')));
    });
  });

  group('restart: items enqueued by one instance are sent by a fresh one '
      'over the same database file', () {
    test('a real SqfliteSyncMirrorRepository persists the outbox across '
        'instances opening the same db path', () async {
      // A *file-backed* temp path, not sqflite_common_ffi's
      // inMemoryDatabasePath (which opens a fresh in-memory db every open,
      // the opposite of what this test needs) — standing in for "the same
      // database across an app restart".
      final tempDir = Directory.systemTemp.createTempSync('push_sync_restart_test_');
      final tempPath = '${tempDir.path}/mirror.db';

      final firstMirror = SqfliteSyncMirrorRepository.withDbPath(tempPath);
      await firstMirror.commit(enqueue: [
        OutboxItem(fileId: 'restart-file', type: SyncChangeType.create, baseCursor: 1, createdAt: DateTime.now()),
      ]);
      expect(await firstMirror.outboxCount(), 1);
      await (await firstMirror.debugDatabase).close();

      // A fresh repository instance and a fresh PushSyncService, standing
      // in for the app having restarted — nothing here is shared with
      // firstMirror except the file on disk.
      final secondMirror = SqfliteSyncMirrorRepository.withDbPath(tempPath);
      final freshDeviceRegistration = MockDeviceRegistrationService();
      final freshDataSource = MockSyncRemoteDataSource();
      when(() => freshDeviceRegistration.ensureRegistered()).thenAnswer((_) async => 'dev-1');
      when(() => freshDataSource.push('dev-1', any(), baseCursor: any(named: 'baseCursor')))
          .thenAnswer((_) async => {});
      final freshService = PushSyncService(freshDataSource, freshDeviceRegistration, secondMirror);

      final sent = await freshService.drainOutbox();

      expect(sent, 1);
      verify(() => freshDataSource.push(
            'dev-1',
            [
              {'fileId': 'restart-file', 'eventType': 0, 'metadata': null},
            ],
            baseCursor: 1,
          )).called(1);
      expect(await secondMirror.outboxCount(), 0);

      await (await secondMirror.debugDatabase).close();
      tempDir.deleteSync(recursive: true);
    });
  });

  test('outboxCount delegates to the mirror', () async {
    when(() => mockMirror.outboxCount()).thenAnswer((_) async => 3);
    expect(await service.outboxCount(), 3);
  });
}

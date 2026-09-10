import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:zdrive_app/features/files/domain/file_item.dart';
import 'package:zdrive_app/features/files/domain/file_repository.dart';
import 'package:zdrive_app/features/sync/data/device_registration_service.dart';
import 'package:zdrive_app/features/sync/data/pull_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_entry.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_repository.dart';

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

class MockDeviceRegistrationService extends Mock implements DeviceRegistrationService {}

class MockSyncMirrorRepository extends Mock implements SyncMirrorRepository {}

class MockFileRepository extends Mock implements FileRepository {}

class FakeSyncMirrorEntry extends Fake implements SyncMirrorEntry {}

void main() {
  late MockSyncRemoteDataSource mockSyncDataSource;
  late MockDeviceRegistrationService mockDeviceRegistration;
  late MockSyncMirrorRepository mockMirror;
  late MockFileRepository mockFileRepository;
  late PullSyncService service;
  late Directory tempDir;

  setUpAll(() => registerFallbackValue(FakeSyncMirrorEntry()));

  setUp(() {
    mockSyncDataSource = MockSyncRemoteDataSource();
    mockDeviceRegistration = MockDeviceRegistrationService();
    mockMirror = MockSyncMirrorRepository();
    mockFileRepository = MockFileRepository();
    service = PullSyncService(
      mockSyncDataSource,
      mockDeviceRegistration,
      mockMirror,
      mockFileRepository,
    );
    tempDir = Directory.systemTemp.createTempSync('pull_sync_test_');

    when(() => mockDeviceRegistration.ensureRegistered()).thenAnswer((_) async => 'dev-1');
    when(() => mockMirror.setCursor(any(), any())).thenAnswer((_) async {});
    when(() => mockMirror.upsert(any())).thenAnswer((_) async {});
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Map<String, dynamic> page(List<Map<String, dynamic>> events, int newCursor) =>
      {'events': events, 'newCursor': newCursor};

  test('applies a Create event: downloads the file, writes it under the sync folder, '
      'and advances the cursor', () async {
    final bytes = Uint8List.fromList(utf8.encode('hello world'));
    final now = DateTime.utc(2026, 1, 1);

    when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
    when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
          {'id': 1, 'fileId': 'file-1', 'eventType': 'Create', 'metadata': null},
        ], 1));
    when(() => mockFileRepository.getFile('file-1')).thenAnswer((_) async => FileItem(
          id: 'file-1',
          name: 'doc.txt',
          isFolder: false,
          sizeBytes: bytes.length,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockMirror.getByServerId('file-1')).thenAnswer((_) async => null);
    when(() => mockFileRepository.downloadFile('file-1')).thenAnswer((_) async => bytes);

    final applied = await service.pullOnce(tempDir.path);

    expect(applied, 1);
    final written = File(p.join(tempDir.path, 'doc.txt'));
    expect(written.existsSync(), isTrue);
    expect(written.readAsBytesSync(), bytes);

    final upserted = verify(() => mockMirror.upsert(captureAny())).captured.single
        as SyncMirrorEntry;
    expect(upserted.serverId, 'file-1');
    expect(upserted.localPath, written.path);
    expect(upserted.isFolder, isFalse);
    expect(upserted.contentHash, sha256.convert(bytes).toString());

    verify(() => mockMirror.setCursor('dev-1', 1)).called(1);
  });

  test('applies a Delete event: removes the local file and the mirror row, '
      'and advances the cursor', () async {
    final existingFile = File(p.join(tempDir.path, 'old.txt'))..writeAsStringSync('bye');
    final now = DateTime.utc(2026, 1, 1);

    when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
    when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
          {'id': 1, 'fileId': 'file-2', 'eventType': 'Delete', 'metadata': null},
        ], 1));
    when(() => mockMirror.getByServerId('file-2')).thenAnswer((_) async => SyncMirrorEntry(
          serverId: 'file-2',
          localPath: existingFile.path,
          isFolder: false,
          sizeBytes: 3,
          contentHash: 'irrelevant',
          updatedAt: now,
          syncedAt: now,
        ));
    when(() => mockMirror.deleteByServerId('file-2')).thenAnswer((_) async {});

    final applied = await service.pullOnce(tempDir.path);

    expect(applied, 1);
    expect(existingFile.existsSync(), isFalse);
    verify(() => mockMirror.deleteByServerId('file-2')).called(1);
    verify(() => mockMirror.setCursor('dev-1', 1)).called(1);
  });

  test('does not advance the cursor past an event whose apply failed', () async {
    final bytes = Uint8List.fromList(utf8.encode('ok'));
    final now = DateTime.utc(2026, 1, 1);

    when(() => mockMirror.getCursor('dev-1')).thenAnswer((_) async => 0);
    when(() => mockSyncDataSource.pull('dev-1', 0)).thenAnswer((_) async => page([
          {'id': 1, 'fileId': 'file-1', 'eventType': 'Create', 'metadata': null},
          {'id': 2, 'fileId': 'file-2', 'eventType': 'Create', 'metadata': null},
        ], 2));
    when(() => mockFileRepository.getFile('file-1')).thenAnswer((_) async => FileItem(
          id: 'file-1',
          name: 'ok.txt',
          isFolder: false,
          sizeBytes: bytes.length,
          parentId: null,
          createdAt: now,
          updatedAt: now,
        ));
    when(() => mockMirror.getByServerId('file-1')).thenAnswer((_) async => null);
    when(() => mockFileRepository.downloadFile('file-1')).thenAnswer((_) async => bytes);
    // The second event's lookup fails outright (e.g. a dropped connection —
    // not a 404, which pullOnce treats as "already deleted, reconcile" and
    // is exercised by the Create/Delete tests above).
    when(() => mockFileRepository.getFile('file-2')).thenThrow(Exception('network down'));

    await expectLater(service.pullOnce(tempDir.path), throwsA(isA<Exception>()));

    // Event 1 fully landed (file written, mirror row upserted) before event 2
    // was attempted, so its cursor commit must have happened...
    verify(() => mockMirror.setCursor('dev-1', 1)).called(1);
    // ...but event 2 never landed, so the cursor must never move past it.
    verifyNever(() => mockMirror.setCursor('dev-1', 2));
  });
}

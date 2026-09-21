import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zdrive_app/core/storage/app_preferences.dart';
import 'package:zdrive_app/features/files/data/file_remote_data_source.dart';
import 'package:zdrive_app/features/files/domain/file_repository.dart';
import 'package:zdrive_app/features/sync/data/device_id_storage.dart';
import 'package:zdrive_app/features/sync/data/device_registration_service.dart';
import 'package:zdrive_app/features/sync/data/local_change_scanner.dart';
import 'package:zdrive_app/features/sync/data/pull_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sqflite_sync_mirror_repository.dart';
import 'package:zdrive_app/features/sync/data/sync_coordinator.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_entry.dart';
import 'package:zdrive_app/features/sync/domain/sync_progress.dart';

class MockFileRemoteDataSource extends Mock implements FileRemoteDataSource {}

class MockDeviceRegistrationService extends Mock implements DeviceRegistrationService {}

class MockFileRepository extends Mock implements FileRepository {}

class MockDeviceIdStorage extends Mock implements DeviceIdStorage {}

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

/// Only what SyncCoordinator reads for the migration, but stateful: the
/// "decided" flag must survive between calls like the Hive box does.
class _FakePreferences extends Fake implements AppPreferences {
  @override
  String? syncFolderPath;

  @override
  bool cloudOnlyMigrationDecided = false;

  @override
  Future<void> setCloudOnlyMigrationDecided() async => cloudOnlyMigrationDecided = true;
}

/// The one-time cloud-only migration against the REAL sqflite mirror (in
/// memory) and a real temp directory; only the network side is mocked.
void main() {
  late MockFileRepository files;
  late MockDeviceRegistrationService device;
  late SqfliteSyncMirrorRepository mirror;
  late PullSyncService pull;
  late LocalChangeScanner scanner;
  late SyncCoordinator coordinator;
  late _FakePreferences prefs;
  late Directory root;
  final now = DateTime.utc(2026, 1, 1);

  String path(String relative) => p.joinAll([root.path, ...relative.split('/')]);

  String hashOf(String content) => sha256.convert(utf8.encode(content)).toString();

  /// A file as the old mirror-everything sync left it: on disk, downloaded,
  /// hash of its content recorded, not pinned.
  Future<void> legacyFile(String id, String relative, String content, {String? recordedHash}) async {
    final file = File(path(relative))..createSync(recursive: true);
    file.writeAsStringSync(content);
    await mirror.upsert(SyncMirrorEntry(
      serverId: id,
      localPath: path(relative),
      isFolder: false,
      sizeBytes: content.length,
      contentHash: recordedHash ?? hashOf(content),
      updatedAt: now,
      syncedAt: now,
    ));
  }

  Future<void> legacyFolder(String id, String relative) async {
    Directory(path(relative)).createSync(recursive: true);
    await mirror.upsert(SyncMirrorEntry(
      serverId: id,
      localPath: path(relative),
      isFolder: true,
      updatedAt: now,
      syncedAt: now,
    ));
  }

  Future<void> cloudOnlyFile(String id, String relative) => mirror.upsert(SyncMirrorEntry(
        serverId: id,
        localPath: path(relative),
        isFolder: false,
        sizeBytes: 100,
        updatedAt: now,
        syncedAt: now,
        downloaded: false,
      ));

  setUpAll(() {
    sqfliteFfiInit();
    registerFallbackValue(const Stream<List<int>>.empty());
    registerFallbackValue(CancelToken());
    registerFallbackValue((String _) async {});
  });

  setUp(() async {
    files = MockFileRepository();
    device = MockDeviceRegistrationService();
    mirror = SqfliteSyncMirrorRepository.withDbPath(inMemoryDatabasePath);
    // Same singleInstance-cache hazard as the other mirror tests: start clean.
    await mirror.clearAll();
    root = Directory.systemTemp.createTempSync('cloud_migration_');
    prefs = _FakePreferences()..syncFolderPath = root.path;
    when(() => device.ensureRegistered()).thenAnswer((_) async => 'dev-1');
    when(() => device.localDeviceId()).thenAnswer((_) async => 'dev-1');
    when(() => files.deleteFile(any(), originDeviceId: any(named: 'originDeviceId')))
        .thenAnswer((_) async {});
    pull = PullSyncService(MockFileRemoteDataSource(), device, mirror, files, isWindows: false);
    scanner = LocalChangeScanner(mirror, files, device, isWindows: false);
    coordinator = SyncCoordinator(
      pull,
      scanner,
      mirror,
      MockDeviceIdStorage(),
      prefs,
      device,
      MockSyncRemoteDataSource(),
    );
  });

  tearDown(() async {
    await (await mirror.debugDatabase).close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void verifyServerUntouched() {
    verifyNever(() => files.deleteFile(any(), originDeviceId: any(named: 'originDeviceId')));
    verifyNever(() => files.uploadFile(any(), any(), any(), any(), any(),
        originDeviceId: any(named: 'originDeviceId'),
        cancelToken: any(named: 'cancelToken'),
        onNodeCreated: any(named: 'onNodeCreated')));
    verifyNever(() => files.uploadNewVersion(any(), any(), any(), any(),
        originDeviceId: any(named: 'originDeviceId'),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken')));
  }

  group('estimateFreeable', () {
    test('Estimate_CountsOnlyDownloadedUnpinnedHashedFiles', () async {
      await legacyFile('a', 'a.txt', '12345');
      await legacyFile('b', 'Docs/b.txt', '1234567890');
      await legacyFolder('docs', 'Docs');
      // Excluded, one reason each:
      await legacyFile('direct', 'direct.txt', 'xx');
      await mirror.pin('direct'); // pinned itself
      await legacyFolder('pf', 'Pinned');
      await legacyFile('viaFolder', 'Pinned/in.txt', 'xx');
      await mirror.pin('pf'); // pinned through its ancestor
      await legacyFile('nohash', 'unfinished.txt', 'xx');
      await mirror.upsert(SyncMirrorEntry(
        serverId: 'nohash',
        localPath: path('unfinished.txt'),
        isFolder: false,
        updatedAt: now,
        syncedAt: now,
      )); // downloaded but no hash: an upload that never finished
      await cloudOnlyFile('cloud', 'cloud.txt'); // nothing on disk

      final estimate = await mirror.estimateFreeable();

      expect(estimate, const FreeableEstimate(count: 2, bytes: 15));
    });
  });

  group('pendingCloudOnlyMigration', () {
    test('NewInstall_EmptyMirror_NoDialogAndMarkedDone', () async {
      expect(await coordinator.pendingCloudOnlyMigration(root.path), isNull);
      expect(prefs.cloudOnlyMigrationDecided, isTrue);
    });

    test('NothingFreeable_OnlyCloudOnlyAndPinned_NoDialogAndMarkedDone', () async {
      await cloudOnlyFile('cloud', 'cloud.txt');
      await legacyFile('kept', 'kept.txt', 'abc');
      await mirror.pin('kept');

      expect(await coordinator.pendingCloudOnlyMigration(root.path), isNull);
      expect(prefs.cloudOnlyMigrationDecided, isTrue);
    });

    test('ExistingDownloadedFiles_Asks_AndDoesNotMarkDone', () async {
      await legacyFile('a', 'a.txt', '12345');

      final estimate = await coordinator.pendingCloudOnlyMigration(root.path);

      expect(estimate, const FreeableEstimate(count: 1, bytes: 5));
      // Only an explicit choice records it, so closing the app with the
      // dialog open (or "Decide later") asks again next start.
      expect(prefs.cloudOnlyMigrationDecided, isFalse);
      expect(await coordinator.pendingCloudOnlyMigration(root.path), isNotNull);
    });

    test('AlreadyDecided_NeverAsksAgain', () async {
      await legacyFile('a', 'a.txt', '12345');
      prefs.cloudOnlyMigrationDecided = true;

      expect(await coordinator.pendingCloudOnlyMigration(root.path), isNull);
    });

    test('StaleFolder_IsIgnored', () async {
      await legacyFile('a', 'a.txt', '12345');

      expect(await coordinator.pendingCloudOnlyMigration('/some/other/folder'), isNull);
      expect(prefs.cloudOnlyMigrationDecided, isFalse);
    });
  });

  group('freeUpEverythingUnpinned', () {
    Future<void> seed() async {
      await legacyFile('a', 'a.txt', 'aaa');
      await legacyFolder('docs', 'Docs');
      await legacyFile('b', 'Docs/b.txt', 'bbb');
      await legacyFile('edited', 'edited.txt', 'my unsynced edit', recordedHash: hashOf('what the server has'));
      await legacyFile('pinned', 'pinned.txt', 'ppp');
      await mirror.pin('pinned');
      await legacyFolder('pf', 'Keep');
      await legacyFile('kept', 'Keep/k.txt', 'kkk');
      await mirror.pin('pf');
    }

    test('BulkFreeUp_FreesMatchingKeepsEditedAndPinnedAndCountsThem', () async {
      await seed();

      final result = await coordinator.freeUpEverythingUnpinned(root.path);

      expect(result.freed, 2);
      expect(result.freedBytes, 6);
      expect(result.skippedUnsynced, [path('edited.txt')]);
      expect(result.keptPinned, greaterThanOrEqualTo(2)); // pinned.txt + Keep/k.txt (+ the folder)
      expect(File(path('a.txt')).existsSync(), isFalse);
      expect(File(path('Docs/b.txt')).existsSync(), isFalse);
      expect(Directory(path('Docs')).existsSync(), isFalse);
      expect(File(path('edited.txt')).readAsStringSync(), 'my unsynced edit');
      expect(File(path('pinned.txt')).existsSync(), isTrue);
      expect(File(path('Keep/k.txt')).existsSync(), isTrue);
      expect((await mirror.getByServerId('a'))!.downloaded, isFalse);
      expect((await mirror.getByServerId('edited'))!.downloaded, isTrue);
      // Nothing was unpinned to make room.
      expect(await mirror.isPinned('pinned'), isTrue);
      expect(await mirror.isPinned('pf'), isTrue);
      expect(prefs.cloudOnlyMigrationDecided, isTrue);
    });

    test('BulkFreeUp_ThenScan_PushesNoServerDeleteOrUpload', () async {
      await legacyFile('a', 'a.txt', 'aaa');
      await legacyFolder('docs', 'Docs');
      await legacyFile('b', 'Docs/b.txt', 'bbb');
      await legacyFile('pinned', 'pinned.txt', 'ppp');
      await mirror.pin('pinned');

      await coordinator.freeUpEverythingUnpinned(root.path);
      final pushed = await scanner.scanOnce(root.path);

      expect(pushed, 0);
      verifyServerUntouched();
      expect(await mirror.getByServerId('a'), isNotNull);
      expect(await mirror.getByServerId('b'), isNotNull);
    });

    test('BulkFreeUp_SecondRun_IsIdempotent', () async {
      await seed();
      await coordinator.freeUpEverythingUnpinned(root.path);

      final again = await coordinator.freeUpEverythingUnpinned(root.path);

      expect(again.freed, 0);
      expect(again.freedBytes, 0);
      expect(again.skippedUnsynced, [path('edited.txt')]);
      expect(File(path('edited.txt')).readAsStringSync(), 'my unsynced edit');
      expect(File(path('pinned.txt')).existsSync(), isTrue);
    });

    test('BulkFreeUp_AfterInterruptedRun_OnlyContinuesWithWhatIsLeft', () async {
      await seed();
      // The app died after the first item: 'a' is already cloud-only, the
      // decision was never recorded.
      await pull.freeUp('a', root.path);
      expect(prefs.cloudOnlyMigrationDecided, isFalse);

      final result = await coordinator.freeUpEverythingUnpinned(root.path);

      expect(result.freed, 1); // Docs/b.txt only
      expect(File(path('Docs/b.txt')).existsSync(), isFalse);
      expect(prefs.cloudOnlyMigrationDecided, isTrue);
    });

    test('BulkFreeUp_CrashBetweenRowFlipAndFileDelete_LeavesTheFileAndPushesNothing', () async {
      await legacyFile('a', 'a.txt', 'aaa');
      // freeUp flips the row first, deletes second; the crash left this.
      final row = (await mirror.getByServerId('a'))!;
      await mirror.upsert(SyncMirrorEntry(
        serverId: 'a',
        localPath: row.localPath,
        isFolder: false,
        sizeBytes: row.sizeBytes,
        updatedAt: now,
        syncedAt: now,
        downloaded: false,
      ));

      final result = await coordinator.freeUpEverythingUnpinned(root.path);
      await scanner.scanOnce(root.path);

      expect(result.freed, 0);
      expect(File(path('a.txt')).readAsStringSync(), 'aaa'); // never lost
      verifyServerUntouched();
    });

    test('BulkFreeUp_ReportsProgressForEveryFileExamined', () async {
      await seed();
      final snapshots = <SyncProgress>[];

      await coordinator.freeUpEverythingUnpinned(root.path, progress: SyncProgressTracker(snapshots.add));

      expect(snapshots.first.phase, SyncPhase.deleting);
      expect(snapshots.first.totalFiles, 3); // a, b, edited: the estimate excludes pinned
      // Every examined file (freed, kept-edited, kept-pinned) is finished.
      expect(snapshots.last.completedFiles, 5);
    });

    test('BulkFreeUp_StaleFolder_DoesNothingAndDecidesNothing', () async {
      await seed();
      prefs.syncFolderPath = '/another/folder';

      final result = await coordinator.freeUpEverythingUnpinned(root.path);

      expect(result.freed, 0);
      expect(File(path('a.txt')).existsSync(), isTrue);
      expect(prefs.cloudOnlyMigrationDecided, isFalse);
    });
  });

  group('keepEverythingOnDevice', () {
    test('KeepAll_PinsTopLevelItemsSoNothingIsFreeableAndNothingChanges', () async {
      await legacyFile('a', 'a.txt', 'aaa');
      await legacyFolder('docs', 'Docs');
      await legacyFile('b', 'Docs/b.txt', 'bbb');

      await coordinator.keepEverythingOnDevice(root.path);

      expect(await mirror.isPinned('a'), isTrue);
      expect(await mirror.isPinned('docs'), isTrue);
      expect(await mirror.isPinned('b'), isFalse); // covered by its folder
      expect(await mirror.estimateFreeable(), const FreeableEstimate(count: 0, bytes: 0));
      expect(prefs.cloudOnlyMigrationDecided, isTrue);
      expect(File(path('a.txt')).existsSync(), isTrue);
      expect(File(path('Docs/b.txt')).existsSync(), isTrue);

      // A later bulk free-up (or the per-item action's safety net) frees nothing.
      final result = await coordinator.freeUpEverythingUnpinned(root.path);
      expect(result.freed, 0);
      expect(File(path('Docs/b.txt')).existsSync(), isTrue);
    });
  });
}

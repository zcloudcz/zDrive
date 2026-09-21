import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zdrive_app/features/files/data/file_dtos.dart';
import 'package:zdrive_app/features/files/data/file_remote_data_source.dart';
import 'package:zdrive_app/features/files/domain/file_item.dart';
import 'package:zdrive_app/features/files/domain/file_repository.dart';
import 'package:zdrive_app/features/sync/data/device_registration_service.dart';
import 'package:zdrive_app/features/sync/data/local_change_scanner.dart';
import 'package:zdrive_app/features/sync/data/pull_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sqflite_sync_mirror_repository.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_entry.dart';

class MockFileRemoteDataSource extends Mock implements FileRemoteDataSource {}

class MockDeviceRegistrationService extends Mock implements DeviceRegistrationService {}

class MockFileRepository extends Mock implements FileRepository {}

/// A real mirror that runs [onFreedRowWrite] right before AND right after the
/// free-up primitive writes a row's cloud-only form. That is how the test
/// puts a scan "between the file delete and the flag flip": with the safe
/// order (flag first, delete second) neither scan can see a downloaded row
/// with its file missing; with the reversed order the "before" scan does.
class _ObservedMirror extends SqfliteSyncMirrorRepository {
  _ObservedMirror() : super.withDbPath(inMemoryDatabasePath);

  Future<void> Function()? onFreedRowWrite;

  @override
  Future<void> upsert(SyncMirrorEntry entry) async {
    final hook = entry.downloaded ? null : onFreedRowWrite;
    await hook?.call();
    await super.upsert(entry);
    await hook?.call();
  }
}

/// Free-up, the folder-collision retry and pin transfer, against the REAL
/// sqflite mirror (in memory) and a real temp directory; only the network side
/// is mocked.
void main() {
  late MockFileRemoteDataSource dataSource;
  late MockDeviceRegistrationService device;
  late MockFileRepository files;
  late _ObservedMirror mirror;
  late PullSyncService service;
  late Directory root;
  final now = DateTime.utc(2026, 1, 1);

  FileItem item(String id, String name, {String? parent, bool folder = false}) => FileItem(
        id: id,
        name: name,
        isFolder: folder,
        sizeBytes: folder ? null : 3,
        parentId: parent,
        createdAt: now,
        updatedAt: now,
      );

  void serve(List<FileItem> items) {
    for (final i in items) {
      when(() => files.getFile(i.id)).thenAnswer((_) async => i);
      if (!i.isFolder) {
        when(() => files.downloadFileStream(i.id))
            .thenAnswer((_) => Stream.value(Uint8List.fromList(utf8.encode('abc'))));
      }
    }
    Future<PagedResult<FileItem>> children(String? parent) async {
      final list = items.where((i) => i.parentId == parent).toList();
      return PagedResult(items: list, totalCount: list.length, page: 1, pageSize: 50);
    }

    when(() => files.listChildren(any(), page: any(named: 'page')))
        .thenAnswer((inv) => children(inv.positionalArguments[0] as String?));
  }

  void feed(List<(int, String, String)> events) {
    when(() => dataSource.getChanges(any(), deviceId: any(named: 'deviceId'))).thenAnswer(
      (_) async => ChangeFeedPageDto(
        changes: [
          for (final e in events)
            ChangeFeedItemDto(id: e.$1, fileId: e.$2, type: e.$3, occurredAt: now),
        ],
        nextCursor: events.isEmpty ? 0 : events.last.$1,
        hasMore: false,
      ),
    );
  }

  String path(String relative) => p.joinAll([root.path, ...relative.split('/')]);

  /// What the coordinator does for "Always keep": pin, then hydrate.
  Future<void> keep(String id) async {
    await mirror.pin(id);
    await service.hydrate(id, root.path);
  }

  /// What the coordinator does for "Free up": unpin, then the primitive.
  Future<FreeUpResult> free(String id) async {
    await mirror.unpin(id);
    return service.freeUp(id, root.path);
  }

  setUpAll(() {
    registerFallbackValue(const Stream<List<int>>.empty());
    registerFallbackValue(CancelToken());
    registerFallbackValue((String _) async {});
  });

  setUp(() async {
    dataSource =MockFileRemoteDataSource();
    device = MockDeviceRegistrationService();
    files = MockFileRepository();
    sqfliteFfiInit();
    mirror = _ObservedMirror();
    // Same singleInstance-cache hazard as the repository test: start clean.
    await mirror.clearAll();
    service = PullSyncService(dataSource, device, mirror, files, isWindows: false);
    root = Directory.systemTemp.createTempSync('pull_offline_');
    when(() => device.ensureRegistered()).thenAnswer((_) async => 'dev-1');
    when(() => device.localDeviceId()).thenAnswer((_) async => 'dev-1');
    feed([]);
  });

  tearDown(() async {
    await (await mirror.debugDatabase).close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  final docs = item('docs', 'Docs', folder: true);
  final inner = item('inner', 'inner.txt', parent: 'docs');
  final top = item('top', 'top.txt');

  group('freeUp', () {
    test('FreeUp_UneditedFile_DeletedAndRowBecomesCloudOnly', () async {
      serve([top]);
      await keep('top');
      expect(File(path('top.txt')).existsSync(), isTrue);

      final result = await free('top');

      expect(result.freed, 1);
      expect(result.skippedUnsynced, isEmpty);
      expect(File(path('top.txt')).existsSync(), isFalse);
      final row = (await mirror.getByServerId('top'))!;
      expect(row.downloaded, isFalse);
      // Same shape as a file that was cloud-only from the start: no hash,
      // size still known, path kept so it can be hydrated back.
      expect(row.contentHash, isNull);
      expect(row.sizeBytes, 3);
      expect(row.localPath, path('top.txt'));
      expect(await mirror.isPinned('top'), isFalse);
    });

    test('FreeUp_EditedFile_KeptDownloadedAndReported', () async {
      serve([top]);
      await keep('top');
      File(path('top.txt')).writeAsStringSync('my unsynced edit');

      final result = await free('top');

      expect(result.freed, 0);
      expect(result.skippedUnsynced, [path('top.txt')]);
      expect(File(path('top.txt')).readAsStringSync(), 'my unsynced edit');
      final row = (await mirror.getByServerId('top'))!;
      expect(row.downloaded, isTrue);
      expect(row.contentHash, isNotNull);
    });

    test('FreeUp_FileMissingOnDisk_KeptDownloadedAndReported', () async {
      serve([top]);
      await keep('top');
      File(path('top.txt')).deleteSync();

      final result = await free('top');

      expect(result.skippedUnsynced, [path('top.txt')]);
      expect((await mirror.getByServerId('top'))!.downloaded, isTrue);
    });

    test('FreeUp_FileWithoutHashYet_IsNeverDeleted', () async {
      // A downloaded row with a null hash is an interrupted upload: the bytes
      // on disk are the only copy.
      File(path('new.txt')).writeAsStringSync('only copy');
      await mirror.upsert(SyncMirrorEntry(
        serverId: 'new',
        localPath: path('new.txt'),
        isFolder: false,
        updatedAt: now,
        syncedAt: now,
      ));

      final result = await service.freeUp('new', root.path);

      expect(result.skippedUnsynced, hasLength(1));
      expect(File(path('new.txt')).existsSync(), isTrue);
    });

    test('FreeUp_FilePinnedThroughAncestor_Kept', () async {
      serve([docs, inner]);
      await keep('docs');

      // Only the file is asked to be freed; the folder above stays pinned.
      final result = await free('inner');

      expect(result.keptPinned, 1);
      expect(result.freed, 0);
      expect(File(path('Docs/inner.txt')).existsSync(), isTrue);
      expect((await mirror.getByServerId('inner'))!.downloaded, isTrue);
    });

    test('FreeUp_Folder_FreesChildrenRemovesEmptyDirAndFlipsFolderRow', () async {
      final sub = item('sub', 'Sub', parent: 'docs', folder: true);
      final deep = item('deep', 'deep.txt', parent: 'sub');
      serve([docs, inner, sub, deep]);
      await keep('docs');

      final result = await free('docs');

      expect(result.freed, 2);
      expect(Directory(path('Docs')).existsSync(), isFalse);
      for (final id in ['docs', 'inner', 'sub', 'deep']) {
        expect((await mirror.getByServerId(id))!.downloaded, isFalse, reason: id);
      }
    });

    test('FreeUp_FolderWithEditedChild_KeepsThatChildItsFolderChainAndRows', () async {
      final sub = item('sub', 'Sub', parent: 'docs', folder: true);
      final deep = item('deep', 'deep.txt', parent: 'sub');
      serve([docs, inner, sub, deep]);
      await keep('docs');
      File(path('Docs/Sub/deep.txt')).writeAsStringSync('edited');

      final result = await free('docs');

      expect(result.freed, 1); // inner.txt only
      expect(result.skippedUnsynced, [path('Docs/Sub/deep.txt')]);
      expect(File(path('Docs/inner.txt')).existsSync(), isFalse);
      expect(File(path('Docs/Sub/deep.txt')).readAsStringSync(), 'edited');
      // Nothing under them may claim to be cloud-only while the edit lives there.
      expect((await mirror.getByServerId('sub'))!.downloaded, isTrue);
      expect((await mirror.getByServerId('docs'))!.downloaded, isTrue);
      expect((await mirror.getByServerId('deep'))!.downloaded, isTrue);
    });

    test('FreeUp_FolderWithUntrackedLocalFile_KeepsDirectoryAndItsRow', () async {
      serve([docs, inner]);
      await keep('docs');
      File(path('Docs/mine.txt')).writeAsStringSync('not synced, not in the mirror');

      await free('docs');

      expect(File(path('Docs/mine.txt')).existsSync(), isTrue);
      expect((await mirror.getByServerId('docs'))!.downloaded, isTrue);
      expect((await mirror.getByServerId('inner'))!.downloaded, isFalse);
    });

    test('FreeUp_FolderWithPinnedSubfolder_KeepsPinnedPartOnly', () async {
      final sub = item('sub', 'Sub', parent: 'docs', folder: true);
      final deep = item('deep', 'deep.txt', parent: 'sub');
      serve([docs, inner, sub, deep]);
      await keep('docs');
      await mirror.pin('sub');

      final result = await free('docs');

      expect(File(path('Docs/inner.txt')).existsSync(), isFalse);
      expect(File(path('Docs/Sub/deep.txt')).existsSync(), isTrue);
      expect(result.keptPinned, 1); // deep.txt; the pinned folder rows are not counted
      expect((await mirror.getByServerId('docs'))!.downloaded, isTrue);
    });

    test('FreeUp_CloudOnlyItem_IsANoOp', () async {
      serve([top]);
      await service.pullOnce(root.path);

      final result = await service.freeUp('top', root.path);

      expect(result.freed, 0);
      expect(result.skippedUnsynced, isEmpty);
    });

    group('scanner', () {
      late LocalChangeScanner scanner;

      setUp(() {
        scanner = LocalChangeScanner(mirror, files, device, isWindows: false);
        when(() => files.deleteFile(any(), originDeviceId: any(named: 'originDeviceId')))
            .thenAnswer((_) async {});
      });

      void verifyServerUntouched() {
        verifyNever(() => files.deleteFile(any(), originDeviceId: any(named: 'originDeviceId')));
        verifyNever(() => files.uploadFile(any(), any(), any(), any(), any(),
            originDeviceId: any(named: 'originDeviceId'),
            cancelToken: any(named: 'cancelToken'),
            onNodeCreated: any(named: 'onNodeCreated')));
      }

      test('FreeUp_ThenScan_DoesNotPushAServerDelete', () async {
        serve([docs, inner, top]);
        await keep('docs');
        await keep('top');
        await free('docs');
        await free('top');

        final pushed = await scanner.scanOnce(root.path);

        expect(pushed, 0);
        verifyServerUntouched();
        expect((await mirror.getByServerId('top'))!.downloaded, isFalse);
        expect(await mirror.getByServerId('inner'), isNotNull);
      });

      test('FreeUp_ScanAroundTheFlagFlip_NeverSeesDownloadedRowWithMissingFile', () async {
        serve([top]);
        await keep('top');
        var scans = 0;
        mirror.onFreedRowWrite = () async {
          scans++;
          await scanner.scanOnce(root.path);
        };

        await free('top');

        expect(scans, 2);
        // Neither scan (before the flip: file still there; after the flip:
        // row cloud-only, file still there) may reach the server.
        verifyServerUntouched();
        expect(File(path('top.txt')).existsSync(), isFalse);
        expect((await mirror.getByServerId('top'))!.downloaded, isFalse);
      });
    });
  });

  group('pin transfer', () {
    DioException notFound() => DioException(
          requestOptions: RequestOptions(path: '/x'),
          response: Response(requestOptions: RequestOptions(path: '/x'), statusCode: 404),
          type: DioExceptionType.badResponse,
        );

    test('Commit_ItemRecreatedUnderNewServerIdAtSamePath_PinMovesToNewId', () async {
      SyncMirrorEntry row(String id) => SyncMirrorEntry(
            serverId: id,
            localPath: path('a.txt'),
            isFolder: false,
            sizeBytes: 3,
            contentHash: 'h',
            updatedAt: now,
            syncedAt: now,
          );
      await mirror.upsert(row('old'));
      await mirror.pin('old');

      await mirror.commit(deleteServerIds: ['old'], upserts: [row('new')]);

      expect(await mirror.isPinned('new'), isTrue);
      expect(await mirror.isPinned('old'), isFalse);
    });

    test('Commit_PlainDelete_DropsPinAndTransfersNothing', () async {
      await mirror.upsert(SyncMirrorEntry(
        serverId: 'old',
        localPath: path('a.txt'),
        isFolder: false,
        updatedAt: now,
        syncedAt: now,
      ));
      await mirror.upsert(SyncMirrorEntry(
        serverId: 'other',
        localPath: path('b.txt'),
        isFolder: false,
        updatedAt: now,
        syncedAt: now,
      ));
      await mirror.pin('old');

      await mirror.commit(deleteServerIds: ['old']);

      expect(await mirror.isPinned('old'), isFalse);
      expect(await mirror.isPinned('other'), isFalse);
    });

    test('Scan_LocalEditOfFileDeletedElsewhere_ReuploadKeepsThePin', () async {
      // The carry-over from PR 62: server copy deleted on another device, the
      // user edits the pinned local file, the scanner re-uploads it as a NEW
      // node — the pin must follow it.
      File(path('a.txt')).writeAsStringSync('edited locally');
      final past = now.subtract(const Duration(days: 1));
      await mirror.upsert(SyncMirrorEntry(
        serverId: 'old',
        localPath: path('a.txt'),
        isFolder: false,
        sizeBytes: 3,
        contentHash: sha256.convert(utf8.encode('abc')).toString(),
        updatedAt: past,
        syncedAt: past,
      ));
      await mirror.pin('old');
      when(() => files.uploadNewVersion(any(), any(), any(), any(),
          originDeviceId: any(named: 'originDeviceId'),
          onProgress: any(named: 'onProgress'),
          cancelToken: any(named: 'cancelToken'))).thenThrow(notFound());
      when(() => files.uploadFile(any(), any(), any(), any(), any(),
              originDeviceId: any(named: 'originDeviceId'),
              cancelToken: any(named: 'cancelToken'),
              onNodeCreated: any(named: 'onNodeCreated')))
          .thenAnswer((inv) async {
        await (inv.namedArguments[#onNodeCreated] as Future<void> Function(String))('new');
        return 'new';
      });
      final scanner = LocalChangeScanner(mirror, files, device, isWindows: false);

      await scanner.scanOnce(root.path);

      expect(await mirror.getByServerId('old'), isNull);
      expect(await mirror.getByServerId('new'), isNotNull);
      expect(await mirror.isPinned('new'), isTrue);
      expect(await mirror.isPinned('old'), isFalse);
    });
  });

  group('cloud-only folder collision', () {
    test('LocalFolderFirst_ThenRemoteFolderAppears_ScannerNeverAdoptsIt', () async {
      // Review round 1 of PR 63: the collision used to be thrown BEFORE the
      // cloud-only row was written, so a folder this device had never seen
      // got no row; the scanner then adopted the server folder on its 409
      // and deleting the local folder later trashed the whole server subtree.
      serve([]);
      await service.pullOnce(root.path); // bootstrap of an empty server
      Directory(path('Docs')).createSync();
      File(path('Docs/mine.txt')).writeAsStringSync('mine');
      // ...then a Create event for the remote "Docs" arrives.
      serve([docs, inner]);
      feed([(1, 'docs', 'Create')]);

      await service.pullOnce(root.path);

      final row = await mirror.getByServerId('docs');
      expect(row, isNotNull, reason: 'the cloud-only row must exist so the scanner sees the path as taken');
      expect(row!.downloaded, isFalse);
      expect((await mirror.getFailedEvents()).map((f) => f.fileId), contains('docs'));

      final scanner = LocalChangeScanner(mirror, files, device, isWindows: false);
      await scanner.scanOnce(root.path);

      verifyNever(() => files.createFolder(any(), any(), originDeviceId: any(named: 'originDeviceId')));
      expect((await mirror.getByServerId('docs'))!.downloaded, isFalse);

      // The user deletes their local folder: nothing may be trashed remotely.
      Directory(path('Docs')).deleteSync(recursive: true);
      await scanner.scanOnce(root.path);
      verifyNever(() => files.deleteFile(any(), originDeviceId: any(named: 'originDeviceId')));
    });

    test('QuarantinedCollidingFolder_PullRetry_StaysQuarantinedNoFlicker', () async {
      serve([docs, inner]);
      await service.pullOnce(root.path); // bootstrap: cloud-only rows only
      // The user creates a local "Docs" afterwards; the scanner quarantines it.
      Directory(path('Docs')).createSync();
      File(path('Docs/mine.txt')).writeAsStringSync('mine');
      final scanner = LocalChangeScanner(mirror, files, device, isWindows: false);
      await scanner.scanOnce(root.path);
      expect((await mirror.getFailedEvents()).map((f) => f.fileId), contains('docs'));

      // Make the failure old enough for pull's retry loop to pick it up.
      final db = await mirror.debugDatabase;
      await db.update('failed_events', {
        'failedAt': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      });
      await service.pullOnce(root.path);

      expect((await mirror.getFailedEvents()).map((f) => f.fileId), contains('docs'));
      expect(File(path('Docs/mine.txt')).readAsStringSync(), 'mine');
      expect((await mirror.getByServerId('docs'))!.downloaded, isFalse);
    });
  });

  group('getOfflineStatuses', () {
    test('Statuses_CoverEveryCombinationInOneCall', () async {
      final sub = item('sub', 'Sub', parent: 'docs', folder: true);
      serve([docs, inner, sub, top]);
      await keep('docs'); // docs + inner + sub downloaded and pinned via docs
      await service.pullOnce(root.path);
      await mirror.upsert(SyncMirrorEntry(
        serverId: 'loose',
        localPath: path('loose.txt'),
        isFolder: false,
        contentHash: 'h',
        updatedAt: now,
        syncedAt: now,
      ));

      final statuses = await mirror.getOfflineStatuses(['docs', 'inner', 'loose', 'top', 'unknown']);

      expect(statuses['docs'], OfflineStatus.alwaysKeep);
      expect(statuses['inner'], OfflineStatus.alwaysKeepViaFolder);
      expect(statuses['loose'], OfflineStatus.available);
      expect(statuses['top'], OfflineStatus.cloudOnly);
      expect(statuses['unknown'], OfflineStatus.cloudOnly);
    });

    test('Statuses_DirectPinInsidePinnedFolder_IsViaFolder_SoMenuOffersNoFreeUp', () async {
      final sub = item('sub', 'Sub', parent: 'docs', folder: true);
      serve([docs, inner, sub]);
      await keep('docs');
      await mirror.pin('inner'); // redundant explicit pin under a pinned folder
      await service.pullOnce(root.path);

      final statuses = await mirror.getOfflineStatuses(['inner']);

      expect(statuses['inner'], OfflineStatus.alwaysKeepViaFolder);
    });

    test('Statuses_PinnedButNotOnDisk_IsDownloading_AndParentPinCoversRowlessItems', () async {
      serve([docs, inner]);
      await service.pullOnce(root.path); // cloud-only rows for docs + inner
      await mirror.pin('docs');

      final statuses = await mirror.getOfflineStatuses(['docs', 'inner', 'fresh'], parentId: 'docs');

      expect(statuses['docs'], OfflineStatus.downloading);
      expect(statuses['inner'], OfflineStatus.downloading);
      // No mirror row yet, but the listed folder is pinned: pull would fetch it.
      expect(statuses['fresh'], OfflineStatus.downloading);
    });
  });
}

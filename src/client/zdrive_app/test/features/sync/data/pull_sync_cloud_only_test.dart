import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
import 'package:zdrive_app/features/sync/data/pull_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sqflite_sync_mirror_repository.dart';

class MockFileRemoteDataSource extends Mock implements FileRemoteDataSource {}

class MockDeviceRegistrationService extends Mock implements DeviceRegistrationService {}

class MockFileRepository extends Mock implements FileRepository {}

/// Cloud-only-by-default pull behaviour, against the REAL sqflite mirror (in
/// memory) so pins, path-prefix matching and the downloaded flag are
/// exercised for real; only the network side is mocked.
void main() {
  late MockFileRemoteDataSource dataSource;
  late MockDeviceRegistrationService device;
  late MockFileRepository files;
  late SqfliteSyncMirrorRepository mirror;
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

  DioException notFound() => DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(requestOptions: RequestOptions(path: '/x'), statusCode: 404),
        type: DioExceptionType.badResponse,
      );

  /// Registers [items] as the server's live state: getFile, listChildren and
  /// downloadFileStream all answer from it.
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
  List<String> onDisk() =>
      root.listSync(recursive: true).map((e) => p.relative(e.path, from: root.path)).toList();

  setUp(() async {
    dataSource = MockFileRemoteDataSource();
    device = MockDeviceRegistrationService();
    files = MockFileRepository();
    sqfliteFfiInit();
    mirror = SqfliteSyncMirrorRepository.withDbPath(inMemoryDatabasePath);
    // Same singleInstance-cache hazard as the repository test: start clean.
    await mirror.clearAll();
    service = PullSyncService(dataSource, device, mirror, files, isWindows: false);
    root = Directory.systemTemp.createTempSync('pull_cloud_only_');
    when(() => device.ensureRegistered()).thenAnswer((_) async => 'dev-1');
    feed([]);
  });

  tearDown(() async {
    await (await mirror.debugDatabase).close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  final docs = item('docs', 'Docs', folder: true);
  final inner = item('inner', 'inner.txt', parent: 'docs');
  final top = item('top', 'top.txt');

  test('Bootstrap_NothingPinned_DownloadsNothingButFillsMirror', () async {
    serve([docs, inner, top]);

    await service.pullOnce(root.path);

    expect(onDisk(), isEmpty, reason: 'no files, no placeholders, no empty folders');
    verifyNever(() => files.downloadFileStream(any()));
    for (final id in ['docs', 'inner', 'top']) {
      final row = await mirror.getByServerId(id);
      expect(row, isNotNull, reason: id);
      expect(row!.downloaded, isFalse, reason: id);
    }
    expect((await mirror.getByServerId('inner'))!.localPath, path('Docs/inner.txt'));
  });

  test('Bootstrap_PinnedFolder_DownloadsSubtreeOnly', () async {
    serve([docs, inner, top]);
    await mirror.pin('docs');

    await service.pullOnce(root.path);

    expect(File(path('Docs/inner.txt')).existsSync(), isTrue);
    expect(File(path('top.txt')).existsSync(), isFalse);
    expect((await mirror.getByServerId('inner'))!.downloaded, isTrue);
    expect((await mirror.getByServerId('top'))!.downloaded, isFalse);
  });

  test('Create_UnderPinnedFolder_Downloads_ElsewhereStaysCloudOnly', () async {
    serve([docs, inner]);
    await mirror.pin('docs');
    await service.pullOnce(root.path); // bootstrap: Docs is materialised

    final later = item('later', 'later.txt', parent: 'docs');
    final elsewhere = item('elsewhere', 'elsewhere.txt');
    serve([docs, inner, later, elsewhere]);
    feed([(1, 'later', 'Create'), (2, 'elsewhere', 'Create')]);
    await service.pullOnce(root.path);

    expect(File(path('Docs/later.txt')).existsSync(), isTrue);
    expect(File(path('elsewhere.txt')).existsSync(), isFalse);
    expect((await mirror.getByServerId('elsewhere'))!.downloaded, isFalse);
  });

  test('Create_UnderPinnedFolderNeverSeenBefore_ResolvesAncestorsAndDownloads', () async {
    // A brand-new subfolder of a pinned folder, created on the server after
    // bootstrap: its file must still count as pinned through the ancestor.
    serve([docs, inner]);
    await mirror.pin('docs');
    await service.pullOnce(root.path);

    final sub = item('sub', 'Sub', parent: 'docs', folder: true);
    final deep = item('deep', 'deep.txt', parent: 'sub');
    serve([docs, inner, sub, deep]);
    feed([(1, 'deep', 'Create')]);
    await service.pullOnce(root.path);

    expect(File(path('Docs/Sub/deep.txt')).existsSync(), isTrue);
    expect((await mirror.getByServerId('sub'))!.downloaded, isTrue);
  });

  test('Unpin_DoesNotDeleteAnythingAndDownloadedFilesKeepSyncing', () async {
    serve([docs, inner]);
    await mirror.pin('docs');
    await service.pullOnce(root.path);
    await mirror.unpin('docs');

    // Remote content changed: the downloaded file keeps following the server
    // (PR 3 owns freeing space), it does not silently turn cloud-only.
    serve([docs, inner]);
    when(() => files.downloadFileStream('inner'))
        .thenAnswer((_) => Stream.value(Uint8List.fromList(utf8.encode('new'))));
    feed([(1, 'inner', 'Update')]);
    await service.pullOnce(root.path);

    expect(File(path('Docs/inner.txt')).readAsStringSync(), 'new');
    expect((await mirror.getByServerId('inner'))!.downloaded, isTrue);
  });

  test('RemoteDelete_CloudOnlyItem_RemovesMirrorRowsAndTouchesNoDisk', () async {
    serve([docs, inner, top]);
    await service.pullOnce(root.path);
    // A user's own file sitting at the virtual path must survive.
    File(path('top.txt')).writeAsStringSync('mine');

    when(() => files.getFile('top')).thenThrow(notFound());
    when(() => files.getFile('docs')).thenThrow(notFound());
    feed([(1, 'top', 'Delete'), (2, 'docs', 'Delete')]);
    await service.pullOnce(root.path);

    expect(await mirror.getByServerId('top'), isNull);
    expect(await mirror.getByServerId('docs'), isNull);
    expect(await mirror.getByServerId('inner'), isNull, reason: 'children of the deleted folder go too');
    expect(File(path('top.txt')).readAsStringSync(), 'mine');
  });

  test('RemoteRename_CloudOnlyFolder_UpdatesMirrorPathsAndCreatesNothing', () async {
    serve([docs, inner]);
    await service.pullOnce(root.path);

    final renamed = item('docs', 'Papers', folder: true);
    serve([renamed, inner]);
    feed([(1, 'docs', 'Update')]);
    await service.pullOnce(root.path);

    expect((await mirror.getByServerId('docs'))!.localPath, path('Papers'));
    expect((await mirror.getByServerId('inner'))!.localPath, path('Papers/inner.txt'));
    expect(onDisk(), isEmpty);
  });

  test('RemoteRename_CloudOnlyFile_UpdatesMirrorPathOnly', () async {
    serve([top]);
    await service.pullOnce(root.path);

    serve([item('top', 'renamed.txt')]);
    feed([(1, 'top', 'Update')]);
    await service.pullOnce(root.path);

    final row = (await mirror.getByServerId('top'))!;
    expect(row.localPath, path('renamed.txt'));
    expect(row.downloaded, isFalse);
    expect(onDisk(), isEmpty);
  });

  test('CloudOnlyItem_UntrackedLocalFileAtItsPath_IsQuarantinedNotAdopted', () async {
    File(path('top.txt')).writeAsStringSync('mine');
    serve([top]);

    await service.pullOnce(root.path);

    expect(File(path('top.txt')).readAsStringSync(), 'mine');
    expect(await mirror.getByServerId('top'), isNull);
    expect((await mirror.getFailedEvents()).single.fileId, 'top');
  });

  group('hydrate', () {
    test('Hydrate_Folder_DownloadsMissingFilesAndSkipsDownloaded', () async {
      final sub = item('sub', 'Sub', parent: 'docs', folder: true);
      final deep = item('deep', 'deep.txt', parent: 'sub');
      serve([docs, inner, sub, deep]);
      await service.pullOnce(root.path); // everything cloud-only
      // One file was already downloaded earlier (e.g. hydrated on its own).
      await service.hydrate('inner', root.path);
      clearInteractions(files);
      serve([docs, inner, sub, deep]);
      File(path('Docs/inner.txt')).writeAsStringSync('local edit');

      await mirror.pin('docs');
      await service.hydrate('docs', root.path);

      expect(File(path('Docs/Sub/deep.txt')).existsSync(), isTrue);
      expect((await mirror.getByServerId('sub'))!.downloaded, isTrue);
      verifyNever(() => files.downloadFileStream('inner'));
      expect(File(path('Docs/inner.txt')).readAsStringSync(), 'local edit');
    });

    test('Hydrate_SingleFile_DownloadsItAndItsCloudOnlyParents', () async {
      serve([docs, inner, top]);
      await service.pullOnce(root.path);

      await service.hydrate('inner', root.path);

      expect(File(path('Docs/inner.txt')).existsSync(), isTrue);
      expect(File(path('top.txt')).existsSync(), isFalse);
      expect((await mirror.getByServerId('docs'))!.downloaded, isTrue,
          reason: 'the scanner must see the new directory as tracked');
    });
  });

  test('Move_CloudOnlySubtreeIntoPinnedFolder_HydratesDescendants', () async {
    // The change feed has one row for the moved folder, none for its
    // descendants - so pull itself must fetch them.
    final pinned = item('pinned', 'Pinned', folder: true);
    serve([pinned, docs, inner]);
    await mirror.pin('pinned');
    await service.pullOnce(root.path);
    expect(File(path('Docs/inner.txt')).existsSync(), isFalse);

    final moved = item('docs', 'Docs', parent: 'pinned', folder: true);
    serve([pinned, moved, inner]);
    feed([(1, 'docs', 'Move')]);
    await service.pullOnce(root.path);

    expect(File(path('Pinned/Docs/inner.txt')).existsSync(), isTrue);
    expect((await mirror.getByServerId('inner'))!.downloaded, isTrue);
  });

  test('Hydrate_InterleavedWithPull_WaitsForThePullToFinish', () async {
    final a = item('a', 'a.txt');
    final b = item('b', 'b.txt');
    serve([a, b]);
    await mirror.pin('a');
    final gate = Completer<void>();
    when(() => files.downloadFileStream('a')).thenAnswer((_) async* {
      await gate.future;
      yield Uint8List.fromList(utf8.encode('abc'));
    });

    final pull = service.pullOnce(root.path);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final hydrate = service.hydrate('b', root.path);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    verifyNever(() => files.downloadFileStream('b'));

    gate.complete();
    await Future.wait([pull, hydrate]);

    expect(File(path('a.txt')).existsSync(), isTrue);
    expect(File(path('b.txt')).existsSync(), isTrue);
    expect(await mirror.getFailedEvents(), isEmpty);
  });

  test('Hydrate_FailedOnUnpinnedItem_IsRetriedByPullWithDownloadForced', () async {
    serve([top]);
    await service.pullOnce(root.path); // cloud-only
    File(path('top.txt')).writeAsStringSync('mine');
    await service.hydrate('top', root.path);
    expect((await mirror.getFailedEvents()).single.fileId, 'top');

    // The user gets the blocking file out of the way; the quarantine
    // backoff has elapsed.
    File(path('top.txt')).deleteSync();
    await (await mirror.debugDatabase)
        .update('failed_events', {'failedAt': DateTime.utc(2020).toIso8601String()});
    await service.pullOnce(root.path);

    expect(File(path('top.txt')).existsSync(), isTrue, reason: 'retry must keep the hydrate intent');
    expect(await mirror.getFailedEvents(), isEmpty);
  });

  test('DeleteRow_RemovesItsPin', () async {
    serve([docs, inner]);
    await mirror.pin('docs');
    await service.pullOnce(root.path);
    when(() => files.getFile('docs')).thenThrow(notFound());
    feed([(1, 'docs', 'Delete')]);
    await service.pullOnce(root.path);

    expect(await mirror.isPinned('docs'), isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zdrive_app/features/sync/data/sqflite_sync_mirror_repository.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_entry.dart';

void main() {
  // `getApplicationSupportDirectory()` needs a platform channel that plain
  // `flutter test` doesn't provide, so production code never runs under
  // test — SqfliteSyncMirrorRepository.withDbPath(inMemoryDatabasePath)
  // (a sqflite_common_ffi special path opening a fresh in-memory database
  // per open, no platform channel needed) is what makes this file possible.
  // See F10 in the PR #12 review.
  late SqfliteSyncMirrorRepository repository;

  setUp(() {
    repository = SqfliteSyncMirrorRepository.withDbPath(inMemoryDatabasePath);
  });

  SyncMirrorEntry entry({
    required String serverId,
    required String localPath,
    bool isFolder = false,
    String? contentHash,
  }) =>
      SyncMirrorEntry(
        serverId: serverId,
        localPath: localPath,
        isFolder: isFolder,
        contentHash: contentHash,
        updatedAt: DateTime.utc(2026, 1, 1),
        syncedAt: DateTime.utc(2026, 1, 1),
      );

  group('mirror rows', () {
    test('getByServerId returns null when nothing was upserted', () async {
      expect(await repository.getByServerId('missing'), isNull);
    });

    test('upsert then getByServerId round-trips every field', () async {
      await repository.upsert(entry(
        serverId: 'file-1',
        localPath: '/sync/doc.txt',
        contentHash: 'abc123',
      ));

      final row = await repository.getByServerId('file-1');
      expect(row, isNotNull);
      expect(row!.localPath, '/sync/doc.txt');
      expect(row.isFolder, isFalse);
      expect(row.contentHash, 'abc123');
    });

    test('upsert replaces an existing row for the same serverId', () async {
      await repository.upsert(entry(serverId: 'file-1', localPath: '/sync/a.txt'));
      await repository.upsert(entry(serverId: 'file-1', localPath: '/sync/b.txt'));

      final row = await repository.getByServerId('file-1');
      expect(row!.localPath, '/sync/b.txt');
    });

    test('deleteByServerId removes the row', () async {
      await repository.upsert(entry(serverId: 'file-1', localPath: '/sync/a.txt'));
      await repository.deleteByServerId('file-1');
      expect(await repository.getByServerId('file-1'), isNull);
    });
  });

  group('cursor', () {
    test('getCursor defaults to 0 for a device never seen before', () async {
      expect(await repository.getCursor('dev-1'), 0);
    });

    test('setCursor then getCursor round-trips, keyed per device', () async {
      await repository.setCursor('dev-1', 42);
      await repository.setCursor('dev-2', 7);

      expect(await repository.getCursor('dev-1'), 42);
      expect(await repository.getCursor('dev-2'), 7);
    });
  });

  group('rePathChildren', () {
    test('re-parents every row under the old prefix, and nothing else', () async {
      final oldDir = p.join('sync', 'old');
      final newDir = p.join('sync', 'new');

      await repository.upsert(entry(serverId: 'folder-1', localPath: oldDir, isFolder: true));
      await repository.upsert(
          entry(serverId: 'file-1', localPath: p.join(oldDir, 'a.txt')));
      await repository.upsert(
          entry(serverId: 'file-2', localPath: p.join(oldDir, 'nested', 'b.txt')));
      await repository.upsert(
          entry(serverId: 'file-3', localPath: p.join('sync', 'unrelated.txt')));

      await repository.rePathChildren(oldDir, newDir);

      expect((await repository.getByServerId('file-1'))!.localPath, p.join(newDir, 'a.txt'));
      expect((await repository.getByServerId('file-2'))!.localPath,
          p.join(newDir, 'nested', 'b.txt'));
      // The folder's own row is not a "child" of its own prefix (no
      // separator after it) — PullSyncService re-paths it itself via a
      // normal upsert, this method only handles what is nested under it.
      expect((await repository.getByServerId('folder-1'))!.localPath, oldDir);
      expect((await repository.getByServerId('file-3'))!.localPath, p.join('sync', 'unrelated.txt'));
    });
  });

  group('getChildrenUnder', () {
    test('returns only rows strictly nested under the prefix, not the '
        'prefix\'s own row or an unrelated sibling', () async {
      final folderDir = p.join('sync', 'Photos');

      await repository.upsert(entry(serverId: 'folder-1', localPath: folderDir, isFolder: true));
      await repository.upsert(
          entry(serverId: 'file-1', localPath: p.join(folderDir, 'a.jpg')));
      await repository.upsert(
          entry(serverId: 'file-2', localPath: p.join(folderDir, 'nested', 'b.jpg')));
      await repository.upsert(
          entry(serverId: 'file-3', localPath: p.join('sync', 'unrelated.txt')));

      final children = await repository.getChildrenUnder(folderDir);

      expect(children.map((e) => e.serverId), containsAll(['file-1', 'file-2']));
      expect(children.map((e) => e.serverId), isNot(contains('folder-1')));
      expect(children.map((e) => e.serverId), isNot(contains('file-3')));
    });
  });

  group('bootstrap flag', () {
    test('isBootstrapped is false until markBootstrapped is called', () async {
      expect(await repository.isBootstrapped('dev-1'), isFalse);
      await repository.markBootstrapped('dev-1');
      expect(await repository.isBootstrapped('dev-1'), isTrue);
    });

    test('is tracked per device', () async {
      await repository.markBootstrapped('dev-1');
      expect(await repository.isBootstrapped('dev-2'), isFalse);
    });
  });

  group('failed events', () {
    test('getFailedEvents is empty until something is recorded', () async {
      expect(await repository.getFailedEvents(), isEmpty);
    });

    test('recordFailedEvent then getFailedEvents round-trips', () async {
      await repository.recordFailedEvent('file-1', 5, 'unsafe name');

      final failed = await repository.getFailedEvents();
      expect(failed, hasLength(1));
      expect(failed.single.fileId, 'file-1');
      expect(failed.single.eventId, 5);
      expect(failed.single.reason, 'unsafe name');
    });

    test('recording again for the same file replaces, not duplicates', () async {
      await repository.recordFailedEvent('file-1', 5, 'first reason');
      await repository.recordFailedEvent('file-1', 9, 'second reason');

      final failed = await repository.getFailedEvents();
      expect(failed, hasLength(1));
      expect(failed.single.eventId, 9);
      expect(failed.single.reason, 'second reason');
    });

    test('clearFailedEvent removes the record', () async {
      await repository.recordFailedEvent('file-1', 5, 'unsafe name');
      await repository.clearFailedEvent('file-1');
      expect(await repository.getFailedEvents(), isEmpty);
    });
  });
}

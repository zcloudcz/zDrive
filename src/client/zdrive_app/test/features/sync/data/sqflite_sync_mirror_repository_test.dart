import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zdrive_app/features/sync/data/sqflite_sync_mirror_repository.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_entry.dart';

/// The pre-#14 (v1) schema — every table except sync_outbox — recreated by
/// hand so the migration test below can open a database that looks exactly
/// like a device already running #12 would have, without depending on the
/// repository's own (now v2) onCreate.
Future<void> _createV1Database(String dbPath) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE mirror_files (
            serverId TEXT PRIMARY KEY,
            localPath TEXT NOT NULL,
            isFolder INTEGER NOT NULL,
            sizeBytes INTEGER,
            contentHash TEXT,
            updatedAt TEXT NOT NULL,
            syncedAt TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE sync_cursor (
            deviceId TEXT PRIMARY KEY,
            cursor INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE bootstrap_state (
            deviceId TEXT PRIMARY KEY
          )
        ''');
        await db.execute('''
          CREATE TABLE failed_events (
            fileId TEXT PRIMARY KEY,
            eventId INTEGER NOT NULL,
            reason TEXT NOT NULL,
            failedAt TEXT NOT NULL
          )
        ''');
      },
    ),
  );
  await db.close();
}

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

  // sqflite_common_ffi's singleInstance cache is keyed by the (literal)
  // path string, and ':memory:' is no exception — without closing it, the
  // next test's `openDatabase(inMemoryDatabasePath)` can hand back this
  // same still-open connection instead of a fresh one, leaking rows into
  // whichever test happens to run next. Only visible to a test that reads
  // back a whole table (peekOutbox, getFailedEvents) rather than one known
  // key, which is why this was not needed before the outbox tests below.
  tearDown(() async {
    await (await repository.debugDatabase).close();
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

    test('re-parents a direct child of a root sync folder without doubling '
        'the separator (F7)', () async {
      final root = p.rootPrefix(Directory.current.absolute.path);
      final newDir = p.join('sync', 'new');

      await repository.upsert(entry(serverId: 'file-1', localPath: p.join(root, 'a.txt')));

      await repository.rePathChildren(root, newDir);

      expect((await repository.getByServerId('file-1'))!.localPath, p.join(newDir, 'a.txt'));
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

    // The sync folder itself can be a filesystem root ("C:\" on Windows,
    // "/" on Linux) — p.rootPrefix gives the real one for whichever
    // platform the test happens to run on. A root already ends with the
    // separator, so naively appending another (the pre-F7 bug) built a
    // prefix nothing could ever match, making the mirror look permanently
    // empty (PR #12 review, F7).
    test('a root sync folder does not double the separator, so its direct '
        'children are still found (F7)', () async {
      final root = p.rootPrefix(Directory.current.absolute.path);
      final childPath = p.join(root, 'a.txt');

      await repository.upsert(entry(serverId: 'file-1', localPath: childPath));

      final children = await repository.getChildrenUnder(root);

      expect(children.map((e) => e.serverId), contains('file-1'));
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

  OutboxItem outboxItem({int? id, String fileId = 'file-1', SyncChangeType type = SyncChangeType.create}) =>
      OutboxItem(id: id, fileId: fileId, type: type, baseCursor: 3, createdAt: DateTime.utc(2026, 1, 1));

  group('commit / outbox (PR #14 review round 3)', () {
    test('commit upserts the mirror and enqueues the outbox atomically', () async {
      await repository.commit(
        upserts: [entry(serverId: 'file-1', localPath: '/sync/a.txt')],
        enqueue: [outboxItem(fileId: 'file-1')],
      );

      expect(await repository.getByServerId('file-1'), isNotNull);
      final queued = await repository.peekOutbox();
      expect(queued, hasLength(1));
      expect(queued.single.fileId, 'file-1');
      expect(queued.single.type, SyncChangeType.create);
      expect(queued.single.baseCursor, 3);
      expect(queued.single.id, isNotNull); // assigned by AUTOINCREMENT
    });

    test('commit deletes by serverId and, with deleteUnderPath, everything '
        'still tracked under a folder', () async {
      final folderPath = p.join('sync', 'proj');
      await repository.upsert(entry(serverId: 'proj-id', localPath: folderPath, isFolder: true));
      await repository.upsert(entry(serverId: 'a-id', localPath: p.join(folderPath, 'a.txt')));
      await repository.upsert(entry(serverId: 'unrelated-id', localPath: p.join('sync', 'other.txt')));

      await repository.commit(
        deleteServerIds: ['proj-id'],
        deleteUnderPath: folderPath,
        enqueue: [outboxItem(fileId: 'proj-id', type: SyncChangeType.delete)],
      );

      expect(await repository.getByServerId('proj-id'), isNull);
      expect(await repository.getByServerId('a-id'), isNull);
      expect(await repository.getByServerId('unrelated-id'), isNotNull);
    });

    test('commit with rePath re-parents children before upserting the '
        'folder\'s own row to its new path', () async {
      final oldPath = p.join('sync', 'Docs');
      final newPath = p.join('sync', 'docs');
      await repository.upsert(entry(serverId: 'docs-id', localPath: oldPath, isFolder: true));
      await repository.upsert(entry(serverId: 'child-id', localPath: p.join(oldPath, 'x.txt')));

      await repository.commit(
        rePath: (from: oldPath, to: newPath),
        upserts: [entry(serverId: 'docs-id', localPath: newPath, isFolder: true)],
        enqueue: [outboxItem(fileId: 'docs-id', type: SyncChangeType.rename)],
      );

      expect((await repository.getByServerId('docs-id'))!.localPath, newPath);
      expect((await repository.getByServerId('child-id'))!.localPath, p.join(newPath, 'x.txt'));
    });

    test('peekOutbox returns rows oldest id first', () async {
      await repository.commit(enqueue: [outboxItem(fileId: 'file-1')]);
      await repository.commit(enqueue: [outboxItem(fileId: 'file-2')]);
      await repository.commit(enqueue: [outboxItem(fileId: 'file-3')]);

      final queued = await repository.peekOutbox();

      expect(queued.map((o) => o.fileId), ['file-1', 'file-2', 'file-3']);
    });

    test('removeOutbox removes exactly the given row', () async {
      await repository.commit(enqueue: [outboxItem(fileId: 'file-1')]);
      await repository.commit(enqueue: [outboxItem(fileId: 'file-2')]);
      final ids = (await repository.peekOutbox()).map((o) => o.id!).toList();

      await repository.removeOutbox(ids.first);

      final remaining = await repository.peekOutbox();
      expect(remaining, hasLength(1));
      expect(remaining.single.fileId, 'file-2');
    });

    test('outboxCount reflects how many rows are queued', () async {
      expect(await repository.outboxCount(), 0);
      await repository.commit(enqueue: [outboxItem(fileId: 'file-1')]);
      await repository.commit(enqueue: [outboxItem(fileId: 'file-2')]);
      expect(await repository.outboxCount(), 2);
    });

    // Teeth check: remove the db.transaction wrapping in commit() (run each
    // step as its own auto-committing statement) and this fails — the
    // upsert below lands before the forced failure on enqueue, instead of
    // rolling back with it.
    test('a commit whose enqueue part fails leaves the mirror unchanged '
        '(the whole call is one transaction)', () async {
      await repository.upsert(entry(serverId: 'file-1', localPath: '/sync/original.txt'));
      // Force a mid-transaction failure without needing an invalid
      // OutboxItem (every one of its fields is already non-nullable) —
      // dropping the outbox table makes the enqueue insert below throw.
      await (await repository.debugDatabase).execute('DROP TABLE sync_outbox');

      await expectLater(
        repository.commit(
          upserts: [entry(serverId: 'file-1', localPath: '/sync/changed.txt')],
          enqueue: [outboxItem(fileId: 'file-1')],
        ),
        throwsA(anything),
      );

      // The upsert that ran earlier in the same transaction must not have
      // stuck — it is only committed together with the (failed) enqueue.
      expect((await repository.getByServerId('file-1'))!.localPath, '/sync/original.txt');
    });
  });

  group('schema migration v1 -> v2 (PR #14 review round 3)', () {
    test('opening a v1 database (no sync_outbox table) through the '
        'repository adds the outbox and keeps existing mirror rows', () async {
      final tempDir = Directory.systemTemp.createTempSync('sync_mirror_migration_test_');
      final dbPath = p.join(tempDir.path, 'mirror.db');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      await _createV1Database(dbPath);
      // Seed a row directly against the v1 schema, standing in for a
      // device that already has synced content before ever seeing #14.
      final seedDb = await databaseFactoryFfi.openDatabase(dbPath);
      await seedDb.insert('mirror_files', {
        'serverId': 'pre-existing-id',
        'localPath': p.join('sync', 'already-synced.txt'),
        'isFolder': 0,
        'sizeBytes': 5,
        'contentHash': 'abc',
        'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'syncedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      });
      await seedDb.close();

      final migrated = SqfliteSyncMirrorRepository.withDbPath(dbPath);

      // The pre-existing row survived the upgrade...
      final row = await migrated.getByServerId('pre-existing-id');
      expect(row, isNotNull);
      expect(row!.localPath, p.join('sync', 'already-synced.txt'));
      // ...and the outbox now exists and works.
      expect(await migrated.outboxCount(), 0);
      await migrated.commit(enqueue: [outboxItem(fileId: 'pre-existing-id')]);
      expect(await migrated.outboxCount(), 1);

      await (await migrated.debugDatabase).close();
    });
  });
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/sync_mirror_entry.dart';
import '../domain/sync_mirror_repository.dart';
import 'local_change_scanner.dart' show syncPathKey;

/// sqflite over drift: the schema is a handful of small tables with no joins
/// or migrations planned, so drift's code-generated query builder buys
/// nothing here that plain SQL statements don't already give us.
@LazySingleton(as: SyncMirrorRepository)
class SqfliteSyncMirrorRepository implements SyncMirrorRepository {
  static const _filesTable = 'mirror_files';
  static const _cursorTable = 'sync_cursor';
  static const _bootstrapTable = 'bootstrap_state';
  static const _failedTable = 'failed_events';
  static const _pinsTable = 'pinned_items';

  final String? _dbPathOverride;

  SqfliteSyncMirrorRepository() : _dbPathOverride = null;

  /// Test-only escape hatch: opens [dbPath] (e.g. sqflite_common_ffi's
  /// `inMemoryDatabasePath`) instead of a file under
  /// getApplicationSupportDirectory(), which needs a platform channel plain
  /// `flutter test` doesn't have. Not annotated for injectable, so DI keeps
  /// using the default constructor above.
  @visibleForTesting
  SqfliteSyncMirrorRepository.withDbPath(String dbPath) : _dbPathOverride = dbPath;

  Database? _db;

  Future<Database> get _database async {
    final existing = _db;
    if (existing != null) return existing;

    // sqflite talks to the platform's native SQLite plugin on Android/iOS,
    // which has no desktop counterpart — sqflite_common_ffi supplies one via
    // the system's sqlite3 library for Windows/macOS/Linux.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = _dbPathOverride ??
        p.join((await getApplicationSupportDirectory()).path, 'zdrive_sync.db');

    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $_filesTable (
              serverId TEXT PRIMARY KEY,
              localPath TEXT NOT NULL,
              isFolder INTEGER NOT NULL,
              sizeBytes INTEGER,
              contentHash TEXT,
              updatedAt TEXT NOT NULL,
              syncedAt TEXT NOT NULL,
              downloaded INTEGER NOT NULL DEFAULT 1
            )
          ''');
          await db.execute(_pinsTableSql);
          await db.execute('''
            CREATE TABLE $_cursorTable (
              deviceId TEXT PRIMARY KEY,
              cursor INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE $_bootstrapTable (
              deviceId TEXT PRIMARY KEY
            )
          ''');
          await db.execute('''
            CREATE TABLE $_failedTable (
              fileId TEXT PRIMARY KEY,
              eventId INTEGER NOT NULL,
              reason TEXT NOT NULL,
              failedAt TEXT NOT NULL
            )
          ''');
          // No sync_outbox table — the push outbox this version once had is
          // gone (FileService's server-generated change feed replaces
          // client push entirely, see PullSyncService/LocalChangeScanner).
        },
        // A device already running #12 has a version-1 database (every
        // table above except sync_outbox); #14 added sync_outbox for v2.
        // Both steps below run in sequence for a v1 database, in order, so
        // it ends up at v3 exactly like a v2 database does.
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            // Historical v1 -> v2 step (PR #14): create the outbox table
            // that existed between v2 and v3. Kept working even though the
            // v3 step below immediately drops it again, so an old v1
            // database passes through the same intermediate shape a v2
            // database always did on its way to v3.
            await db.execute(_historicOutboxTableSql);
          }
          if (oldVersion < 3) {
            // The push outbox no longer exists — drop it if this database
            // ever had one.
            await db.execute('DROP TABLE IF EXISTS sync_outbox');
            // The feed is a brand new id sequence that starts empty when
            // the server change ships — every stored cursor from before it
            // must reset to 0 ("everything since then"); pull is
            // idempotent, so re-applying whatever a stale cursor would
            // have skipped is safe. Mirror rows themselves are untouched.
            await db.update(_cursorTable, {'cursor': 0});
          }
          if (oldVersion < 4) {
            // Cloud-only support. DEFAULT 1: every row that exists before
            // this step was mirrored to disk, so it stays "downloaded".
            // ALTER has no IF NOT EXISTS, so check first (same rollback-then-
            // upgrade re-run concern as the outbox step above).
            final columns = await db.rawQuery('PRAGMA table_info($_filesTable)');
            if (!columns.any((c) => c['name'] == 'downloaded')) {
              await db.execute(
                'ALTER TABLE $_filesTable ADD COLUMN downloaded INTEGER NOT NULL DEFAULT 1',
              );
            }
            await db.execute(_pinsTableSql);
          }
        },
      ),
    );
    _db = db;
    return db;
  }

  // IF NOT EXISTS: onUpgrade may re-run after a rollback (see below).
  static const _pinsTableSql =
      'CREATE TABLE IF NOT EXISTS $_pinsTable (serverId TEXT PRIMARY KEY)';

  // IF NOT EXISTS: this step must stay idempotent (PR #14 review round 4,
  // R4-3) — sqflite_common_ffi has no onDowngrade, so opening a v2 db,
  // rolling back to a v1 build, then opening v2 again re-runs onUpgrade(1,
  // 2) and would otherwise fail with "table already exists". Kept only for
  // [onUpgrade]'s oldVersion < 2 step above — see its comment.
  static const _historicOutboxTableSql = '''
    CREATE TABLE IF NOT EXISTS sync_outbox (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      fileId TEXT NOT NULL,
      changeType INTEGER NOT NULL,
      baseCursor INTEGER NOT NULL,
      createdAt TEXT NOT NULL
    )
  ''';

  @override
  Future<SyncMirrorEntry?> getByServerId(String serverId) async {
    final db = await _database;
    final rows = await db.query(_filesTable, where: 'serverId = ?', whereArgs: [serverId]);
    if (rows.isEmpty) return null;
    return _fromRow(rows.single);
  }

  @override
  Future<void> upsert(SyncMirrorEntry entry) async {
    final db = await _database;
    await db.insert(_filesTable, _entryRow(entry), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Map<String, Object?> _entryRow(SyncMirrorEntry entry) => {
        'serverId': entry.serverId,
        'localPath': entry.localPath,
        'isFolder': entry.isFolder ? 1 : 0,
        'sizeBytes': entry.sizeBytes,
        'contentHash': entry.contentHash,
        'updatedAt': entry.updatedAt.toIso8601String(),
        'syncedAt': entry.syncedAt.toIso8601String(),
        'downloaded': entry.downloaded ? 1 : 0,
      };

  @override
  Future<void> deleteByServerId(String serverId) async {
    final db = await _database;
    await db.transaction((txn) => _deleteRow(txn, serverId));
  }

  // A deleted item must not leave a pin behind: pins are keyed by serverId,
  // so a stale one would be harmless today but confusing for the UI.
  Future<void> _deleteRow(DatabaseExecutor executor, String serverId) async {
    await executor.delete(_filesTable, where: 'serverId = ?', whereArgs: [serverId]);
    await executor.delete(_pinsTable, where: 'serverId = ?', whereArgs: [serverId]);
  }

  // Runs before _deleteRow (which drops the pin). The successor is found by
  // local path, the only identity a recreated item keeps.
  Future<void> _transferPin(DatabaseExecutor executor, String serverId, List<String> beingDeleted) async {
    final pinned = await executor.query(_pinsTable, where: 'serverId = ?', whereArgs: [serverId]);
    if (pinned.isEmpty) return;
    final old = await executor.query(_filesTable, where: 'serverId = ?', whereArgs: [serverId]);
    if (old.isEmpty) return;
    final key = syncPathKey(old.single['localPath'] as String);
    final rows = await executor.query(_filesTable);
    for (final row in rows) {
      final id = row['serverId'] as String;
      if (beingDeleted.contains(id) || syncPathKey(row['localPath'] as String) != key) continue;
      await executor.insert(_pinsTable, {'serverId': id}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  @override
  Future<int> getCursor(String deviceId) async {
    final db = await _database;
    final rows = await db.query(_cursorTable, where: 'deviceId = ?', whereArgs: [deviceId]);
    if (rows.isEmpty) return 0;
    return rows.single['cursor'] as int;
  }

  @override
  Future<void> setCursor(String deviceId, int cursor) async {
    final db = await _database;
    await db.insert(
      _cursorTable,
      {'deviceId': deviceId, 'cursor': cursor},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> rePathChildren(String oldPrefix, String newPrefix) async {
    final db = await _database;
    await _rePathChildren(db, oldPrefix, newPrefix);
  }

  @override
  Future<List<SyncMirrorEntry>> getChildrenUnder(String dirPath) async {
    final db = await _database;
    final rows = await _rowsUnder(db, dirPath);
    return rows.map(_fromRow).toList();
  }

  @override
  Future<bool> isBootstrapped(String deviceId) async {
    final db = await _database;
    final rows = await db.query(_bootstrapTable, where: 'deviceId = ?', whereArgs: [deviceId]);
    return rows.isNotEmpty;
  }

  @override
  Future<void> markBootstrapped(String deviceId) async {
    final db = await _database;
    await db.insert(
      _bootstrapTable,
      {'deviceId': deviceId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> recordFailedEvent(String fileId, int eventId, String reason) async {
    final db = await _database;
    await db.insert(
      _failedTable,
      {
        'fileId': fileId,
        'eventId': eventId,
        'reason': reason,
        'failedAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> clearFailedEvent(String fileId) async {
    final db = await _database;
    await db.delete(_failedTable, where: 'fileId = ?', whereArgs: [fileId]);
  }

  @override
  Future<List<SyncFailedEvent>> getFailedEvents() async {
    final db = await _database;
    final rows = await db.query(_failedTable, orderBy: 'failedAt DESC');
    return rows
        .map((row) => SyncFailedEvent(
              fileId: row['fileId'] as String,
              eventId: row['eventId'] as int,
              reason: row['reason'] as String,
              failedAt: DateTime.parse(row['failedAt'] as String),
            ))
        .toList();
  }

  @override
  Future<void> commit({
    List<SyncMirrorEntry> upserts = const [],
    List<String> deleteServerIds = const [],
    String? deleteUnderPath,
    ({String from, String to})? rePath,
  }) async {
    final db = await _database;
    // Everything below runs against `txn`, never `db` — a plain db.insert
    // mid-way would auto-commit itself before a later step in this same
    // call could fail, defeating the whole point of grouping these writes
    // (PR #14 review round 3, teeth-checked: pulling any one of these calls
    // out of the transaction makes a rolled-back write stick).
    await db.transaction((txn) async {
      if (rePath != null) {
        await _rePathChildren(txn, rePath.from, rePath.to);
      }
      for (final entry in upserts) {
        await txn.insert(_filesTable, _entryRow(entry), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final serverId in deleteServerIds) {
        await _transferPin(txn, serverId, deleteServerIds);
        await _deleteRow(txn, serverId);
      }
      if (deleteUnderPath != null) {
        await _deleteChildren(txn, deleteUnderPath);
      }
    });
  }

  @override
  Future<void> pin(String serverId) async {
    final db = await _database;
    await db.insert(_pinsTable, {'serverId': serverId}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  @override
  Future<void> unpin(String serverId) async {
    final db = await _database;
    await db.delete(_pinsTable, where: 'serverId = ?', whereArgs: [serverId]);
  }

  @override
  Future<bool> isPinned(String serverId) async {
    final db = await _database;
    final rows = await db.query(_pinsTable, where: 'serverId = ?', whereArgs: [serverId]);
    return rows.isNotEmpty;
  }

  @override
  Future<bool> isEffectivelyPinned(String serverId, String localPath) async {
    if (await isPinned(serverId)) return true;
    final prefixes = await _pinnedFolderPrefixes(await _database);
    return _underAny(localPath, prefixes);
  }

  // Pins are few (user-chosen), so scan-and-filter over the pinned rows
  // only — same trade-off as _rowsUnder.
  Future<List<String>> _pinnedFolderPrefixes(DatabaseExecutor executor) async {
    final pinned = await executor.rawQuery(
      'SELECT f.localPath FROM $_pinsTable p JOIN $_filesTable f ON f.serverId = p.serverId '
      'WHERE f.isFolder = 1',
    );
    // Case-insensitive like every other path comparison in sync.
    return [for (final row in pinned) _childPrefix(syncPathKey(row['localPath'] as String))];
  }

  bool _underAny(String localPath, List<String> prefixes) {
    final key = syncPathKey(localPath);
    return prefixes.any(key.startsWith);
  }

  @override
  Future<Map<String, OfflineStatus>> getOfflineStatuses(
    List<String> serverIds, {
    String? parentId,
  }) async {
    if (serverIds.isEmpty) return {};
    final db = await _database;
    final entries = <String, SyncMirrorEntry>{};
    final directPins = <String>{};
    // SQLite caps bound variables (999 on older builds); a listing page is far
    // smaller, but chunk anyway so a big folder can never hit the cap.
    for (var i = 0; i < serverIds.length; i += 500) {
      final chunk = serverIds.sublist(i, i + 500 > serverIds.length ? serverIds.length : i + 500);
      final marks = List.filled(chunk.length, '?').join(',');
      for (final row in await db.query(_filesTable, where: 'serverId IN ($marks)', whereArgs: chunk)) {
        entries[row['serverId'] as String] = _fromRow(row);
      }
      for (final row in await db.query(_pinsTable, where: 'serverId IN ($marks)', whereArgs: chunk)) {
        directPins.add(row['serverId'] as String);
      }
    }
    final prefixes = await _pinnedFolderPrefixes(db);
    var parentPinned = false;
    if (parentId != null) {
      final parent = await getByServerId(parentId);
      parentPinned = await isPinned(parentId) || (parent != null && _underAny(parent.localPath, prefixes));
    }

    return {
      for (final id in serverIds)
        id: _status(
          entries[id],
          direct: directPins.contains(id),
          viaFolder: parentPinned || (entries[id] != null && _underAny(entries[id]!.localPath, prefixes)),
        ),
    };
  }

  OfflineStatus _status(SyncMirrorEntry? entry, {required bool direct, required bool viaFolder}) {
    final downloaded = entry?.downloaded ?? false;
    if (direct || viaFolder) {
      if (!downloaded) return OfflineStatus.downloading;
      // Covered by a pinned folder wins over a direct pin: "free up" on the
      // item would only drop its redundant pin and free nothing (the folder
      // still covers it), so the menu must not offer it.
      return viaFolder ? OfflineStatus.alwaysKeepViaFolder : OfflineStatus.alwaysKeep;
    }
    return downloaded ? OfflineStatus.available : OfflineStatus.cloudOnly;
  }

  @override
  Future<void> clearAll() async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete(_filesTable);
      await txn.delete(_cursorTable);
      await txn.delete(_bootstrapTable);
      await txn.delete(_failedTable);
      await txn.delete(_pinsTable);
    });
  }

  // oldPrefix/dirPath already ends with the separator when the sync folder
  // is a filesystem root ("C:\", "/") — appending another would build a
  // prefix no stored path can ever start with, so every row under it
  // silently stops matching (PR #12 review, F7). The one place this rule
  // lives (PR #14 review round 4, R4-5) — every prefix-based query below
  // goes through this instead of repeating it.
  String _childPrefix(String dirPath) =>
      dirPath.endsWith(Platform.pathSeparator) ? dirPath : '$dirPath${Platform.pathSeparator}';

  // Scan-and-filter, not a LIKE query — a LIKE pattern would need to escape
  // '%'/'_' in the prefix (both legal filename characters), fine for a local
  // per-user mirror table. Takes a [DatabaseExecutor] rather than [Database]
  // or [Transaction] specifically, since both implement it (PR #14 review
  // round 4, R4-5) — shared by [getChildrenUnder] (outside any transaction)
  // and [commit]'s deleteUnderPath handling (inside one).
  Future<List<Map<String, Object?>>> _rowsUnder(DatabaseExecutor executor, String dirPath) async {
    final prefix = _childPrefix(dirPath);
    final rows = await executor.query(_filesTable);
    return rows.where((row) => (row['localPath'] as String).startsWith(prefix)).toList();
  }

  // Shared by the public rePathChildren (outside any transaction) and
  // commit's rePath handling (inside one) — see _rowsUnder's doc comment for
  // why a DatabaseExecutor rather than one specific type.
  Future<void> _rePathChildren(DatabaseExecutor executor, String oldPrefix, String newPrefix) async {
    final prefix = _childPrefix(oldPrefix);
    final rows = await _rowsUnder(executor, oldPrefix);
    // One batch, not one statement per row: a remote rename of a folder
    // with thousands of files under it must re-path them all in one go —
    // atomically (a batch on a Database runs as one transaction, and inside
    // commit's transaction it simply joins it) and fast (per-row autocommit
    // statements took ~5 s for 2000 rows, the batch ~50 ms; PR #14 review
    // round 5).
    final batch = executor.batch();
    for (final row in rows) {
      final path = row['localPath'] as String;
      batch.update(
        _filesTable,
        {'localPath': p.join(newPrefix, path.substring(prefix.length))},
        where: 'serverId = ?',
        whereArgs: [row['serverId']],
      );
    }
    await batch.commit(noResult: true);
  }

  // Only used from commit's deleteUnderPath handling (inside a transaction)
  // today, but takes a DatabaseExecutor for the same reason as _rowsUnder
  // and _rePathChildren above rather than being pinned to Transaction.
  Future<void> _deleteChildren(DatabaseExecutor executor, String dirPath) async {
    final rows = await _rowsUnder(executor, dirPath);
    // Batched for the same reasons as _rePathChildren above.
    final batch = executor.batch();
    for (final row in rows) {
      batch.delete(_filesTable, where: 'serverId = ?', whereArgs: [row['serverId']]);
      batch.delete(_pinsTable, where: 'serverId = ?', whereArgs: [row['serverId']]);
    }
    await batch.commit(noResult: true);
  }

  /// Test-only escape hatch so a repository test can force a mid-transaction
  /// failure (e.g. drop a table before calling [commit]) to prove atomicity.
  @visibleForTesting
  Future<Database> get debugDatabase => _database;

  SyncMirrorEntry _fromRow(Map<String, Object?> row) => SyncMirrorEntry(
        serverId: row['serverId'] as String,
        localPath: row['localPath'] as String,
        isFolder: (row['isFolder'] as int) == 1,
        sizeBytes: row['sizeBytes'] as int?,
        contentHash: row['contentHash'] as String?,
        updatedAt: DateTime.parse(row['updatedAt'] as String),
        syncedAt: DateTime.parse(row['syncedAt'] as String),
        downloaded: (row['downloaded'] as int) == 1,
      );
}

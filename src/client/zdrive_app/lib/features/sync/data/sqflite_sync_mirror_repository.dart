import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/sync_mirror_entry.dart';
import '../domain/sync_mirror_repository.dart';

/// sqflite over drift: the schema is a handful of small tables with no joins
/// or migrations planned, so drift's code-generated query builder buys
/// nothing here that plain SQL statements don't already give us.
@LazySingleton(as: SyncMirrorRepository)
class SqfliteSyncMirrorRepository implements SyncMirrorRepository {
  static const _filesTable = 'mirror_files';
  static const _cursorTable = 'sync_cursor';
  static const _bootstrapTable = 'bootstrap_state';
  static const _failedTable = 'failed_events';
  static const _outboxTable = 'sync_outbox';

  // IF NOT EXISTS: onUpgrade must be idempotent (PR #14 review round 4,
  // R4-3) — sqflite_common_ffi has no onDowngrade, so opening a v2 db,
  // rolling back to a v1 build, then opening v2 again re-runs onUpgrade(1,
  // 2) and would otherwise fail with "table already exists".
  static const _createOutboxTableSql = '''
    CREATE TABLE IF NOT EXISTS $_outboxTable (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      fileId TEXT NOT NULL,
      changeType INTEGER NOT NULL,
      baseCursor INTEGER NOT NULL,
      createdAt TEXT NOT NULL
    )
  ''';

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
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $_filesTable (
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
          await db.execute(_createOutboxTableSql);
        },
        // A device already running #12 has a version-1 database (every
        // table above except sync_outbox) — add just the new table rather
        // than recreating the schema, so its existing mirror rows survive
        // the upgrade untouched.
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(_createOutboxTableSql);
          }
        },
      ),
    );
    _db = db;
    return db;
  }

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
      };

  @override
  Future<void> deleteByServerId(String serverId) async {
    final db = await _database;
    await db.delete(_filesTable, where: 'serverId = ?', whereArgs: [serverId]);
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
    List<OutboxItem> enqueue = const [],
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
        await txn.delete(_filesTable, where: 'serverId = ?', whereArgs: [serverId]);
      }
      if (deleteUnderPath != null) {
        await _deleteChildren(txn, deleteUnderPath);
      }
      for (final item in enqueue) {
        await txn.insert(_outboxTable, {
          'fileId': item.fileId,
          'changeType': item.type.index,
          'baseCursor': item.baseCursor,
          'createdAt': item.createdAt.toIso8601String(),
        });
      }
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
    for (final row in rows) {
      final path = row['localPath'] as String;
      await executor.update(
        _filesTable,
        {'localPath': p.join(newPrefix, path.substring(prefix.length))},
        where: 'serverId = ?',
        whereArgs: [row['serverId']],
      );
    }
  }

  // Only used from commit's deleteUnderPath handling (inside a transaction)
  // today, but takes a DatabaseExecutor for the same reason as _rowsUnder
  // and _rePathChildren above rather than being pinned to Transaction.
  Future<void> _deleteChildren(DatabaseExecutor executor, String dirPath) async {
    final rows = await _rowsUnder(executor, dirPath);
    for (final row in rows) {
      await executor.delete(_filesTable, where: 'serverId = ?', whereArgs: [row['serverId']]);
    }
  }

  @override
  Future<List<OutboxItem>> peekOutbox({int limit = 100}) async {
    final db = await _database;
    final rows = await db.query(_outboxTable, orderBy: 'id ASC', limit: limit);
    return rows
        .map((row) => OutboxItem(
              id: row['id'] as int,
              fileId: row['fileId'] as String,
              type: SyncChangeType.values[row['changeType'] as int],
              baseCursor: row['baseCursor'] as int,
              createdAt: DateTime.parse(row['createdAt'] as String),
            ))
        .toList();
  }

  @override
  Future<void> removeOutbox(int id) async {
    final db = await _database;
    await db.delete(_outboxTable, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<int> outboxCount() async {
    final db = await _database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $_outboxTable');
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Test-only escape hatch so a repository test can force a mid-transaction
  /// failure (e.g. drop the outbox table before calling [commit]) to prove
  /// atomicity, without a way to construct an invalid [OutboxItem] through
  /// the public API — every one of its fields is already non-nullable.
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
      );
}

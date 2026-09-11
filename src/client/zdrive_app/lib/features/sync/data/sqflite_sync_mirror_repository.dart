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
        version: 1,
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
    await db.insert(_filesTable, {
      'serverId': entry.serverId,
      'localPath': entry.localPath,
      'isFolder': entry.isFolder ? 1 : 0,
      'sizeBytes': entry.sizeBytes,
      'contentHash': entry.contentHash,
      'updatedAt': entry.updatedAt.toIso8601String(),
      'syncedAt': entry.syncedAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

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
    // A LIKE query would need to escape '%'/'_' in the prefix (a legal
    // filename character on both platforms), so this scans and filters in
    // Dart instead — fine for a local per-user mirror table.
    //
    // oldPrefix already ends with the separator when the sync folder is a
    // filesystem root ("C:\", "/") — appending another would build a
    // prefix no stored path can ever start with, so every row under it
    // silently stops matching (PR #12 review, F7). `prefix.length` (not
    // oldPrefix.length) is used below for the same reason: it is the one
    // guaranteed to strip exactly one separator regardless of whether
    // oldPrefix already had one.
    final prefix =
        oldPrefix.endsWith(Platform.pathSeparator) ? oldPrefix : '$oldPrefix${Platform.pathSeparator}';
    final rows = await db.query(_filesTable);
    final batch = db.batch();
    for (final row in rows) {
      final path = row['localPath'] as String;
      if (path.startsWith(prefix)) {
        batch.update(
          _filesTable,
          {'localPath': p.join(newPrefix, path.substring(prefix.length))},
          where: 'serverId = ?',
          whereArgs: [row['serverId']],
        );
      }
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<List<SyncMirrorEntry>> getChildrenUnder(String dirPath) async {
    final db = await _database;
    // Same scan-and-filter approach as rePathChildren, and for the same
    // reason: a LIKE query would need to escape '%'/'_' in the prefix. See
    // rePathChildren's doc comment for why a root path (already ending
    // with the separator) must not get a second one appended (F7).
    final prefix = dirPath.endsWith(Platform.pathSeparator) ? dirPath : '$dirPath${Platform.pathSeparator}';
    final rows = await db.query(_filesTable);
    return rows.map(_fromRow).where((entry) => entry.localPath.startsWith(prefix)).toList();
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

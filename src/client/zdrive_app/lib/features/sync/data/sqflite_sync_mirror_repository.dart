import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/sync_mirror_entry.dart';
import '../domain/sync_mirror_repository.dart';

/// sqflite over drift: the schema is two small tables with no joins or
/// migrations planned, so drift's code-generated query builder buys nothing
/// here that a handful of plain SQL statements don't already give us.
@LazySingleton(as: SyncMirrorRepository)
class SqfliteSyncMirrorRepository implements SyncMirrorRepository {
  static const _filesTable = 'mirror_files';
  static const _cursorTable = 'sync_cursor';

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

    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'zdrive_sync.db');

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

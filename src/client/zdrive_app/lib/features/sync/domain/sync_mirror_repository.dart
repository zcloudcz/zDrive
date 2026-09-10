import 'sync_mirror_entry.dart';

/// Local metadata mirror: what pull has already applied, and the per-device
/// pull cursor. Backed by SQLite ([CLAUDE.md]'s mandated store for this)
/// rather than Hive, because reconciliation reads/writes one row per pulled
/// file and needs the cursor update to be the atomic, durable commit point
/// for "this event landed" — a relational table matches that shape directly.
abstract class SyncMirrorRepository {
  Future<SyncMirrorEntry?> getByServerId(String serverId);

  Future<void> upsert(SyncMirrorEntry entry);

  Future<void> deleteByServerId(String serverId);

  /// The last sync-event id fully applied for [deviceId], or 0 if none yet.
  Future<int> getCursor(String deviceId);

  Future<void> setCursor(String deviceId, int cursor);
}

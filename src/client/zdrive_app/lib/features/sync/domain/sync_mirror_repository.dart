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

  /// Re-parents every mirror row whose [SyncMirrorEntry.localPath] lives
  /// under [oldPrefix] to [newPrefix] instead — used when a folder is
  /// renamed/moved on disk (a directory rename, not a delete+recreate; see
  /// PR #12 review F2) so its children's recorded paths follow it rather
  /// than going stale.
  Future<void> rePathChildren(String oldPrefix, String newPrefix);

  /// Every tracked entry whose [SyncMirrorEntry.localPath] lives strictly
  /// under [dirPath] (not [dirPath] itself) — used by a folder delete to
  /// find exactly what it is safe to remove, so it never has to fall back
  /// to a recursive OS delete that cannot tell "the mirror put this here"
  /// from "whatever the OS resolved the path to" (see PR #12 review round
  /// 3, B1).
  Future<List<SyncMirrorEntry>> getChildrenUnder(String dirPath);

  /// Whether the one-time full-tree backfill has already run for
  /// [deviceId]. Distinct from the cursor being 0, which also means
  /// "nothing pulled yet" but stays true after a completed backfill if the
  /// account legitimately had zero sync events at that moment.
  Future<bool> isBootstrapped(String deviceId);

  Future<void> markBootstrapped(String deviceId);

  /// Records that the event [eventId] for [fileId] could not be applied for
  /// a permanent reason (see PullSyncService) — the cursor still advances
  /// past it, so this is how that gets surfaced instead of silently
  /// swallowed.
  Future<void> recordFailedEvent(String fileId, int eventId, String reason);

  /// Clears a previously recorded failure for [fileId] — called after a
  /// later event for the same file applies successfully.
  Future<void> clearFailedEvent(String fileId);

  /// Recorded failures, most recent first.
  Future<List<SyncFailedEvent>> getFailedEvents();
}

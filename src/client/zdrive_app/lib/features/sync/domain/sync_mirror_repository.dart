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

  /// Applies a mirror change and enqueues the outbox report(s) it
  /// represents in one atomic transaction — the persistent-outbox
  /// replacement for the in-memory "write server, then report" two-step
  /// [LocalChangeScanner] used to do (PR #14 review round 3). A scan that
  /// dies right after calling this always leaves the mirror and the outbox
  /// consistent with each other: either both landed, or neither did, so
  /// there is never a mirror row with an owed report nobody remembers, or a
  /// report for a mirror row that was never written.
  ///
  /// [upserts] writes/replaces rows by serverId. [deleteServerIds] removes
  /// rows by serverId. [deleteUnderPath], when given, additionally removes
  /// every row strictly nested under that local path (a folder delete
  /// trashing its tracked subtree). [rePath], when given, re-parents every
  /// row nested under `rePath.from` to live under `rePath.to` instead (a
  /// folder rename) — applied before [upserts], so the folder's own row can
  /// be upserted straight to its new path in the same call. [enqueue] adds
  /// outbox rows, in order — a move-then-rename adds two, in that order.
  Future<void> commit({
    List<SyncMirrorEntry> upserts = const [],
    List<String> deleteServerIds = const [],
    String? deleteUnderPath,
    ({String from, String to})? rePath,
    List<OutboxItem> enqueue = const [],
  });

  /// The oldest [limit] outbox rows, oldest first — what
  /// [PushSyncService.drainOutbox] sends next.
  Future<List<OutboxItem>> peekOutbox({int limit = 100});

  /// Removes one outbox row once its report has been sent.
  Future<void> removeOutbox(int id);

  /// How many reports are still owed — shown in the sync UI so a queue that
  /// keeps failing to drain is visible instead of silent (PR #14 review
  /// round 3, finding C).
  Future<int> outboxCount();
}

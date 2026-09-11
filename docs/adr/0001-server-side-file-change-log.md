# 0001 — Server-side file change log in FileService

## Status

Accepted.

## Context

Sync events currently originate on the client: after a client changes a file
through FileService, it separately calls SyncService's `POST /sync/push`
(the push path added in #13/#14) to announce the change. That works for the
desktop app, but nothing forces every other client onto the same path — the
web UI, the mobile app's own file browser, and the headless `ZDrive.BackupCli`
all call FileService directly and none of them call SyncService push. A file
created from the web currently never reaches a desktop device: SyncService
only knows about changes whoever pushed to it, not everything FileService
actually did.

The fix has to live in FileService, not SyncService, because FileService is
the only place every client's write already goes through.

Numbers behind the sizing: MVP scale is ~100 users × 500 changes/day ≈ 0.6
changes/s; ~100 devices polling every 30s ≈ 3 requests/s. This is well within
what a single Postgres table serves directly — no broker, no dedicated
service, no service-to-service call needed to make this durable enough.

## Decision

FileService owns an append-only change log (`file_changes`), written in the
**same database transaction** as the change it records, and serves it as a
cursor-paged feed (`GET /api/v1/files/changes?cursor=&limit=`).

- **Same-transaction write**: a `SaveChangesInterceptor`
  (`FileChangeInterceptor`) inspects the `FileNode` entries in the
  `ChangeTracker` inside `SavingChanges`/`SavingChangesAsync` and adds
  `FileChange` rows to the same `DbContext` before it commits. One
  `SaveChanges` call, one transaction — no dual write, no outbox to keep in
  sync with a second store.
- **Cursor paging**: `id` is a bigint identity column; clients page with
  `id > cursor`, ordered by `id`. Simple, index-friendly
  (`(tenant_id, user_id, id)`), and naturally resumable — a device just
  remembers the last id it saw.
- **Own-device echo suppression**: the desktop sync client tags its own
  writes with the `X-Device-Id` request header; the feed excludes rows whose
  `origin_device_id` matches the caller's own header, so a device doesn't
  download back the write it just made. Every other client (web, the app's
  own file browser, BackupCli) sends no header, so every device — including
  the one that made the change, if it does not tag itself — receives it.

### Alternatives rejected

- **FileService outbox relayed to SyncService** (push the log to SyncService
  instead of serving it directly): needs service-to-service auth, a relay
  worker, retry/backoff on relay failure, and ends up storing the same data
  in two places anyway. Doesn't remove any of the problems a feed table
  already solves, just adds a hop.
- **Azure Service Bus / RabbitMQ**: new infrastructure to operate for
  ~1 event/s. A durable outbox pattern is still needed underneath a broker to
  avoid dual-write inconsistency, so the broker is pure overhead at this
  scale — it doesn't remove the need for what we just built, it wraps it.

## Consequences

- SyncService's own pull/push/conflict-resolution endpoints become obsolete
  once clients move to polling this feed instead — that migration is out of
  scope for this change; SyncService is untouched here.
- Device registration and identity stay in SyncService; this ADR only adds
  the feed FileService serves, not a new device concept.
- No data loss on failure: the change row is written in the same transaction
  as the mutation, so a partial write is impossible — either both commit or
  neither does.

### Known limitation: the 5-second commit-order hold-back

Identity values (`id`) are assigned at row-insert time inside a transaction,
not at commit time. A transaction that inserted `FileChange` id `N+1` can
still commit *after* another transaction that inserted id `N+2`, if the first
transaction's SaveChanges call simply took longer. A reader that saw `N+2`
and advanced its cursor past it would then skip `N+1` forever — it already
moved on.

The feed closes this window by only returning rows with
`occurred_at <= now - 5s`. Any transaction that takes under 5 seconds from
insert to commit is guaranteed to be visible before a reader's cursor could
pass it. This is a real limit, not just a defensive margin: a transaction
that takes longer than 5 seconds to commit can still be skipped. Nothing
today does — but if a future FileService change makes the file-mutation
transaction slow (e.g. synchronous work added inside the same SaveChanges
scope), this window needs revisiting.

If a client omits `X-Device-Id` (or a different device made the change), the
device just re-applies a change it may already have — redundant work, not
data corruption.

## Not doing (yet) — and what would change that

- **No message broker.** Add one only once realistic load exceeds roughly
  50 changes/s, or once a second consumer besides "poll the feed" shows up
  (today's ~0.6 changes/s and 3 requests/s are nowhere close).
- **No retention or pruning of `file_changes`.** Revisit once the table
  reaches tens of millions of rows — nothing prunes it today, and nothing
  needs to yet.
- **No backfill of changes made before this ships.** The log starts empty;
  existing clients start reading from cursor 0 and simply see no history
  older than the deploy. Backfilling would mean reconstructing change rows
  from `file_nodes`/`file_versions` state that doesn't record what actually
  happened (only current state), which is a different, larger problem.
- **No realtime push.** Devices poll; NotificationService/SignalR push is a
  separate concern this ADR does not touch.

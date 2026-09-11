import 'dart:developer';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../files/domain/file_item.dart';
import '../../files/domain/file_repository.dart';
import '../domain/sync_mirror_entry.dart';
import '../domain/sync_mirror_repository.dart';
import 'device_registration_service.dart';
import 'sync_remote_data_source.dart';

/// The server returns at most this many events per pull
/// (`PullChangesQueryHandler.MaxEventsPerPull`) — a full page means there may
/// be more, so [pullOnce] keeps polling until a short page tells it the tail
/// is reached.
const _maxEventsPerPage = 500;

/// Thrown when a server-supplied name cannot become a safe local path —
/// either it is not a single plain path segment (a drive letter, a UNC
/// root, a separator, or `.`/`..`), or the path it would resolve to lands
/// outside the designated sync folder. `package:path` itself documents that
/// `p.join` discards everything before a later absolute segment, which is
/// exactly what would let a name like `C:\Users\<u>\...\Startup\x.cmd`
/// escape the folder pull is supposed to be confined to. Permanent:
/// retrying changes nothing, so the event is quarantined rather than
/// retried forever (see the PR #12 review, F1).
class UnsafeRemoteNameException implements Exception {
  final String message;
  const UnsafeRemoteNameException(this.message);

  @override
  String toString() => 'unsafe remote name: $message';
}

/// Thrown when applying a pull event would overwrite a local file pull did
/// not itself write — either nothing was ever synced to that path before,
/// or the bytes on disk no longer match what was last synced there (a local
/// edit since). Pull refuses to clobber user data; the event is quarantined
/// instead of retried (see the PR #12 review, F3).
class LocalConflictException implements Exception {
  final String message;
  const LocalConflictException(this.message);

  @override
  String toString() => 'local conflict: $message';
}

/// Applies remote sync events into the designated local folder.
///
/// Ordering guarantee: events are applied one at a time, strictly in the
/// order the server returned them (already ascending by id). The mirror
/// cursor for this device only advances to an event's id *after* that
/// event's disk write and mirror-row update both complete — so if the app
/// dies mid-[pullOnce], the persisted cursor never points past work that
/// did not land. The event that was in flight (and everything after it)
/// will be re-delivered on the next pull; re-applying it is safe because
/// writing a file, removing one that is already gone, and renaming one that
/// has already moved are all idempotent. Move/rename gets this deliberately:
/// [_applyUpsert] deletes the stale path *before* committing the mirror row,
/// not after, so a crash in between never leaves an orphaned duplicate that
/// nothing would ever go back and clean up.
///
/// A *permanent* failure (an unsafe name, or a local file pull refuses to
/// overwrite) does not get the "block until it succeeds" treatment above:
/// it is quarantined instead — recorded via
/// [SyncMirrorRepository.recordFailedEvent], with the cursor still advancing
/// past it — because retrying it immediately would fail the same way and
/// block every event behind it. It is not abandoned, though: [pullOnce]
/// retries every quarantined entry on each call, before draining the event
/// log (see the retry loop there) — so a cause that clears up on its own
/// (a locked file gets closed, a removable drive comes back) recovers on
/// the next poll instead of staying stuck forever. Anything else (a network
/// error, an exception we don't recognise) still blocks the cursor, since
/// those usually do resolve on a later retry.
@lazySingleton
class PullSyncService {
  final SyncRemoteDataSource _syncDataSource;
  final DeviceRegistrationService _deviceRegistration;
  final SyncMirrorRepository _mirror;
  final FileRepository _fileRepository;

  // Win32 name rules (see [violatesWin32NameRules]) only apply on the
  // Windows client — the server does not enforce them and a macOS/Linux
  // client syncs such names normally. Injected (defaulting to the real
  // host) so tests can exercise both branches instead of inheriting
  // whatever OS happens to run them.
  final bool _isWindows;

  PullSyncService(
    this._syncDataSource,
    this._deviceRegistration,
    this._mirror,
    this._fileRepository, {
    bool? isWindows,
  }) : _isWindows = isWindows ?? Platform.isWindows;

  // Guards pullOnce against concurrent invocations on this singleton. The
  // bloc already has its own isPulling check (sync_bloc.dart), but that only
  // protects calls that go through the bloc — PullSyncService is injected
  // and callable from anywhere (a background task, another route), and two
  // overlapping pullOnce calls would each read the same starting cursor and
  // could commit it out of order. Memoizing the in-flight future makes a
  // second caller await the first call's result instead of starting its own
  // (see PR #12 review round 2, R6/F4).
  Future<int>? _inFlight;

  /// Pulls and applies everything pending for this device, draining
  /// multiple pages if the server reports more than fit in one. On this
  /// device's first ever sync, also backfills the designated folder from
  /// whatever currently exists in FileService (see [_bootstrap]) — the
  /// event log only ever covers files touched *after* an event was first
  /// raised for them, so a file nobody has touched since before this
  /// feature shipped would otherwise never arrive. Returns the number of
  /// events applied (the backfill is not counted — it is not an event).
  Future<int> pullOnce(String syncFolderPath) {
    return _inFlight ??= _pullOnce(syncFolderPath).whenComplete(() => _inFlight = null);
  }

  /// Caps how many quarantined rows a single poll retries. Without this, a
  /// quarantine that has grown large (e.g. pointing sync at a folder that
  /// already duplicates thousands of already-uploaded files) would cost one
  /// getFile per row on every single poll, forever (PR #12 review round 3,
  /// B2b). Rows beyond the cap simply wait for a later poll —
  /// [_retryQuarantined] always works the longest-untouched ones first, so
  /// every row eventually gets a turn.
  static const _maxRetriesPerPoll = 20;

  /// How long a just-retried row is left alone before being retried again.
  /// Without this, a row that fails the exact same way every time would be
  /// retried on every ~30s poll forever, at whatever cost that failure
  /// carries (PR #12 review round 3, B2b) — Win32-unsafe names no longer
  /// carry a download cost (see [violatesWin32NameRules]), but this backs
  /// off any other repeatedly-failing row too, not just that one cause.
  static const _retryBackoff = Duration(minutes: 5);

  Future<int> _pullOnce(String syncFolderPath) async {
    final deviceId = await _deviceRegistration.ensureRegistered();

    // Runs before the drain below so a fix picked up here does not race a
    // fresh failure for the same file later in this same call.
    await _retryQuarantined(syncFolderPath);

    var applied = 0;
    while (true) {
      final cursor = await _mirror.getCursor(deviceId);
      final page = await _syncDataSource.pull(deviceId, cursor);
      final events = (page['events'] as List).cast<Map<String, dynamic>>();
      if (events.isEmpty) break;

      for (final event in events) {
        await _applyEvent(event, deviceId, syncFolderPath);
        applied++;
      }

      if (events.length < _maxEventsPerPage) break;
    }

    // Runs after the event-log drain above, not before: that way the
    // cursor this device has already committed to covers everything the
    // event log holds as of now, and anything raised while the walk below
    // is still running simply has an id past that point — the very next
    // pull picks it up normally. The walk itself never touches the cursor,
    // so there is no way for it to skip an event.
    if (!await _mirror.isBootstrapped(deviceId)) {
      await _bootstrap(syncFolderPath);
      await _mirror.markBootstrapped(deviceId);
    }

    return applied;
  }

  /// Events pull could not apply for a permanent reason — see the class doc
  /// comment. A thin passthrough so the presentation layer can surface them
  /// without depending on [SyncMirrorRepository] directly.
  Future<List<SyncFailedEvent>> getFailedEvents() => _mirror.getFailedEvents();

  /// Retries every quarantined entry whose cause may no longer hold (the
  /// file that was locked is closed now, the drive is back). _applyUpsert
  /// is keyed on fileId and fetches current server state, not the original
  /// event — so a failed row is already re-appliable without replaying
  /// anything from the event log. It alone covers both directions: if the
  /// file is now gone server-side, its internal 404 handling falls through
  /// to _applyDelete itself. Bounded by [_maxRetriesPerPoll] and
  /// [_retryBackoff] (PR #12 review round 3, B2b), and every exception is
  /// caught here (B2c): a quarantined row that keeps failing must not
  /// escape and abort [_pullOnce] before the fresh-event drain that follows
  /// this call even runs.
  Future<void> _retryQuarantined(String syncFolderPath) async {
    final now = DateTime.now();
    final due = (await _mirror.getFailedEvents())
        .where((f) => now.difference(f.failedAt) >= _retryBackoff)
        .toList()
      // Oldest-failed first: whatever gets retried below has its failedAt
      // re-stamped to now, sorting it to the back for the next poll — so a
      // quarantine larger than the per-poll budget still gets worked
      // through over time instead of the same rows winning every time.
      ..sort((a, b) => a.failedAt.compareTo(b.failedAt));

    for (final failed in due.take(_maxRetriesPerPoll)) {
      try {
        await _applyUpsert(failed.fileId, syncFolderPath);
        await _mirror.clearFailedEvent(failed.fileId);
      } catch (e, st) {
        // Still failing — still an unsafe name, still a local conflict, a
        // transient FileSystemException, or something this loop was never
        // taught to expect (a non-404 DioException, say, or a programming
        // error). Whichever it is, it must not propagate (B2c) — but it is
        // logged and its own reason recorded, not the stale reason from the
        // first attempt, so a later different failure is visible instead of
        // silently hiding behind whatever tripped first.
        log('quarantine retry failed for ${failed.fileId}', error: e, stackTrace: st, name: 'PullSyncService');
        await _mirror.recordFailedEvent(failed.fileId, failed.eventId, e.toString());
      }
    }
  }

  Future<void> _applyEvent(
    Map<String, dynamic> event,
    String deviceId,
    String syncFolderPath,
  ) async {
    final eventId = (event['id'] as num).toInt();
    final fileId = event['fileId'] as String;
    final eventType = event['eventType'] as String;

    try {
      if (eventType == 'Delete') {
        await _applyDelete(fileId, syncFolderPath);
      } else {
        // Create/Update/Move/Rename are all handled the same way: fetch the
        // file's current state and reconcile the local copy against it.
        // This also covers move/rename without a separate code path — the
        // mirror lookup inside finds the entry's previous local path (if
        // any) and relocates it when the resolved path has changed.
        await _applyUpsert(fileId, syncFolderPath);
      }
      // A previous failure for this file, if any, no longer applies now
      // that a later event for it has gone through cleanly.
      await _mirror.clearFailedEvent(fileId);
    } on UnsafeRemoteNameException catch (e) {
      await _mirror.recordFailedEvent(fileId, eventId, e.toString());
    } on LocalConflictException catch (e) {
      await _mirror.recordFailedEvent(fileId, eventId, e.toString());
    } on FileSystemException catch (e) {
      // A name Windows can't represent, a path past MAX_PATH, a locked
      // file, a disk that is briefly full or unplugged — quarantined
      // without trying to tell a permanent cause from a transient one (that
      // would need an OS-error-code allowlist, more machinery than this is
      // worth). The retry loop at the top of pullOnce re-attempts every
      // quarantined entry on each poll, so a transient cause clears itself
      // on its own; a genuinely permanent one just stays listed.
      await _mirror.recordFailedEvent(fileId, eventId, e.message);
    }

    await _mirror.setCursor(deviceId, eventId);
  }

  Future<void> _applyDelete(String fileId, String syncFolderPath) async {
    final entry = await _mirror.getByServerId(fileId);
    if (entry == null) return; // Never pulled locally — nothing to remove.

    if (entry.isFolder) {
      _assertWithinSyncFolder(syncFolderPath, entry.localPath);
      if (!await _deleteTrackedFolder(entry.localPath)) {
        // Untracked or locally-modified content is still under this
        // folder — see _deleteTrackedFolder's doc comment. Routed through
        // the same refuse-to-overwrite exception _applyUpsert already uses
        // for files, so this reuses the existing quarantine/retry
        // machinery instead of a parallel one: the mirror row for this
        // folder is left in place (nothing below runs), and
        // _retryQuarantined's next _applyUpsert call 404s straight back
        // into this same method and tries again — finishing the job on its
        // own once whatever is left resolves (PR #12 review round 3, B1).
        throw LocalConflictException(
            'folder still holds untracked or locally modified content, not removed: ${entry.localPath}');
      }
    } else {
      await _deleteLocal(syncFolderPath, entry.localPath);
    }

    await _mirror.deleteByServerId(fileId);
  }

  Future<void> _applyUpsert(String fileId, String syncFolderPath) async {
    final FileItem remote;
    try {
      remote = await _fileRepository.getFile(fileId);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // The file is gone by the time we looked it up (e.g. a Create
        // immediately followed by a Delete) — reconcile as a delete instead
        // of failing the whole pull over a stale event.
        await _applyDelete(fileId, syncFolderPath);
        return;
      }
      rethrow;
    }

    final previous = await _mirror.getByServerId(fileId);
    final dirPath = await _resolveLocalDirPath(remote.parentId, syncFolderPath);
    final localPath = _safeChildPath(syncFolderPath, dirPath, remote.name, _isWindows);
    final moved = previous != null && previous.localPath != localPath;

    String? contentHash;
    if (remote.isFolder) {
      if (moved && previous.isFolder) {
        await Directory(localPath).parent.create(recursive: true);
        try {
          // A directory rename moves every child with it — creating an
          // empty folder at the new path and recursively deleting the old
          // one (the previous approach) would destroy every child that has
          // no sync event of its own to re-download it with.
          await Directory(previous.localPath).rename(localPath);
        } on PathNotFoundException {
          // Already renamed by an earlier attempt at this same event that
          // crashed before the mirror commit below — the directory is
          // already at the new path, but the child re-path below still
          // needs to run.
        }
        await _mirror.rePathChildren(previous.localPath, localPath);
      } else {
        await Directory(localPath).create(recursive: true);
      }
    } else {
      // Order matters here: check for a local conflict *before* touching
      // anything on disk, so a refusal to overwrite never leaves behind a
      // deleted "moved from" copy with nothing written at the new path.
      if (await _wouldOverwriteLocalChange(localPath, previous)) {
        throw LocalConflictException(
            'local file differs from what was last synced: $localPath');
      }
      if (moved) {
        // Moved/renamed file: remove the stale copy before committing the
        // mirror row below, not after — see the class doc comment. Deleting
        // first is safe to repeat: an already-gone file is a no-op
        // (_deleteLocal). This branch only runs for files (see the
        // `remote.isFolder` check above), so previous is always a file too.
        await _deleteLocal(syncFolderPath, previous.localPath);
      }
      final bytes = await _fileRepository.downloadFile(fileId);
      await File(localPath).parent.create(recursive: true);
      await File(localPath).writeAsBytes(bytes, flush: true);
      contentHash = sha256.convert(bytes).toString();
    }

    await _mirror.upsert(SyncMirrorEntry(
      serverId: remote.id,
      localPath: localPath,
      isFolder: remote.isFolder,
      sizeBytes: remote.sizeBytes,
      contentHash: contentHash,
      updatedAt: remote.updatedAt,
      syncedAt: DateTime.now(),
    ));
  }

  /// True if writing to [localPath] would clobber something pull did not
  /// itself put there: either nothing was ever synced to this path before
  /// and a file already sits there (untracked), or something was synced but
  /// its on-disk bytes no longer match [previous]'s recorded hash (edited
  /// locally since).
  Future<bool> _wouldOverwriteLocalChange(
    String localPath,
    SyncMirrorEntry? previous,
  ) async {
    final file = File(localPath);
    if (!await file.exists()) return false;
    if (previous == null) return true;
    final onDiskHash = sha256.convert(await file.readAsBytes()).toString();
    return onDiskHash != previous.contentHash;
  }

  /// Resolves [folderId]'s local directory path under [syncFolderPath],
  /// walking the parentId chain as needed and caching each folder it visits
  /// as a mirror row — so later files under the same folder resolve from
  /// the mirror instead of re-walking the chain.
  Future<String> _resolveLocalDirPath(String? folderId, String syncFolderPath) async {
    if (folderId == null) return syncFolderPath;

    final cached = await _mirror.getByServerId(folderId);
    if (cached != null) return cached.localPath;

    final folder = await _fileRepository.getFile(folderId);
    final parentPath = await _resolveLocalDirPath(folder.parentId, syncFolderPath);
    final dirPath = _safeChildPath(syncFolderPath, parentPath, folder.name, _isWindows);

    await Directory(dirPath).create(recursive: true);
    await _mirror.upsert(SyncMirrorEntry(
      serverId: folder.id,
      localPath: dirPath,
      isFolder: true,
      updatedAt: folder.updatedAt,
      syncedAt: DateTime.now(),
    ));

    return dirPath;
  }

  /// Deletes the file at [path]. Folders go through [_deleteTrackedFolder]
  /// instead — see its doc comment for why a folder delete can never be
  /// this simple.
  Future<void> _deleteLocal(String syncFolderPath, String path) async {
    _assertWithinSyncFolder(syncFolderPath, path);
    try {
      await File(path).delete();
    } on PathNotFoundException {
      // Already gone locally — deleting is idempotent, not an error.
    }
  }

  /// Removes everything under [path] that this mirror can prove pull
  /// itself put there — each tracked file whose on-disk bytes still match
  /// [SyncMirrorEntry.contentHash], and each tracked subfolder once it is
  /// empty — then [path] itself, all with non-recursive OS calls. Never
  /// `Directory.delete(recursive: true)`: that call removes whatever the OS
  /// resolves the path to, which is not always the folder the mirror
  /// tracks (a trailing dot/space or a case-only difference can make it
  /// resolve onto an existing sibling instead), and even without that, a
  /// file the user saved locally into a synced folder is not pull's to
  /// remove just because the folder itself was deleted server-side (PR #12
  /// review round 3, B1; and round 1's F3, whose folder-delete half was
  /// never actually fixed until now). [_tryRemoveEmptyDir] can also clear a
  /// short list of regenerable OS metadata files (`.DS_Store`, `Thumbs.db`)
  /// directly inside each folder before attempting the remove — see its doc
  /// comment (PR #12 review round 4, C1; tightened in round 5, D1: only
  /// when [keptAny] below is false, and only when the folder holds nothing
  /// else). Returns whether [path] ended up empty and was removed; false
  /// means something is still there and nothing more was touched — the
  /// caller ([_applyDelete]) quarantines that instead of treating it as
  /// done.
  Future<bool> _deleteTrackedFolder(String path) async {
    final tracked = await _mirror.getChildrenUnder(path);

    // Whether the hash-guard below kept any tracked file in place. A kept
    // file means this folder cannot end up empty no matter what, and the
    // kept file may itself be named `.DS_Store` — sweeping OS metadata in
    // that case would delete the very edit the guard just decided to keep
    // (PR #12 review round 5, D1).
    var keptAny = false;
    for (final file in tracked.where((e) => !e.isFolder)) {
      if (await _wouldOverwriteLocalChange(file.localPath, file)) {
        // Edited locally since sync — not pull's to remove. Left in place,
        // mirror row and all: once this folder stops being tracked (or a
        // later retry finds it finally empty), the row simply stops
        // mattering to anything.
        keptAny = true;
        continue;
      }
      try {
        await File(file.localPath).delete();
      } on PathNotFoundException {
        // Already gone.
      }
      await _mirror.deleteByServerId(file.serverId);
    }

    // Deepest paths first, so a child folder is empty before its own
    // parent is attempted. A path under another is always longer than it
    // (at minimum one more separator plus a non-empty name), so sorting by
    // length alone is sufficient depth ordering here.
    final dirs = tracked.where((e) => e.isFolder).toList()
      ..sort((a, b) => b.localPath.length.compareTo(a.localPath.length));
    for (final dir in dirs) {
      if (await _tryRemoveEmptyDir(dir.localPath, sweepOsMetadata: !keptAny)) {
        await _mirror.deleteByServerId(dir.serverId);
      }
      // Else: not empty — something untracked, or a file skipped above,
      // is still inside. Leave it and its mirror row; nothing recurses
      // into it.
    }

    return _tryRemoveEmptyDir(path, sweepOsMetadata: !keptAny);
  }

  /// OS-regenerated metadata files that hold no user data — Finder writes
  /// `.DS_Store` whenever a folder is opened, and Explorer writes
  /// `Thumbs.db` (thumbnail cache). Left in place, either would make a
  /// folder that pull otherwise emptied out look "not empty" forever,
  /// wedging every remote delete of a folder that was ever opened in
  /// Finder / Explorer (PR #12 review round 4, C1). `desktop.ini`
  /// (Explorer's folder-view settings) is deliberately NOT in this list:
  /// unlike the other two, the OS does not regenerate it on its own — it
  /// is written when a user customizes a folder's view, which is user
  /// intent, not OS noise, and Explorer marks such folders ReadOnly, so
  /// the containing folder would fail to delete anyway once the
  /// customization is gone (PR #12 review round 5, D1). A customized
  /// Windows folder therefore stays in place and is reported as skipped,
  /// same as any other folder pull cannot fully empty.
  static const _osMetadataFileNames = ['.DS_Store', 'Thumbs.db'];

  /// Non-recursive directory removal that treats "not empty" as a normal
  /// outcome, not an error — see [_deleteTrackedFolder]. When
  /// [sweepOsMetadata] is true, first lists [path] non-recursively; if
  /// every entry is a plain file (not a directory or link) named in
  /// [_osMetadataFileNames], those files are deleted and removal proceeds
  /// as normal. Otherwise nothing is deleted and this returns false
  /// immediately — a folder holding anything else (a user file, a
  /// subdirectory, or a tracked file the hash guard kept, see
  /// [_deleteTrackedFolder]) is left completely untouched, metadata
  /// included, because sweeping would not lead to a removal anyway.
  /// [sweepOsMetadata] is false for every folder [_deleteTrackedFolder]
  /// knows cannot end up empty (it kept a locally-changed tracked file
  /// somewhere in this subtree); in that case this goes straight to the
  /// rmdir attempt (PR #12 review round 5, D1). Returns whether [path] is
  /// gone (already gone counts).
  Future<bool> _tryRemoveEmptyDir(
    String path, {
    required bool sweepOsMetadata,
  }) async {
    if (sweepOsMetadata) {
      List<FileSystemEntity> entries;
      try {
        entries = await Directory(path).list(followLinks: false).toList();
      } on PathNotFoundException {
        return true; // Already gone.
      }
      final allMetadata = entries.every(
        (e) => e is File && _osMetadataFileNames.contains(p.basename(e.path)),
      );
      if (!allMetadata) {
        return false; // Something else is in here; leave it all alone.
      }
      for (final entry in entries) {
        try {
          await entry.delete();
        } on FileSystemException {
          // Raced with something else touching it; the rmdir below will
          // simply fail and the existing conflict path handles it.
        }
      }
    }
    try {
      await Directory(path).delete();
      return true;
    } on PathNotFoundException {
      return true;
    } on FileSystemException {
      return false; // Not empty.
    }
  }

  /// Bootstrap has no event log to quarantine a skipped item against — there
  /// is no real eventId behind it — so skips are recorded with this sentinel
  /// instead. [pullOnce]'s retry loop does not care whether an eventId is
  /// real or this placeholder; it always retries by fileId (see R3/F5),
  /// which is what actually gets a bootstrap skip out of quarantine later.
  static const _bootstrapEventId = 0;

  /// Backfills [syncFolderPath] and the mirror from FileService's current
  /// tree — see [pullOnce] for why and when this runs. Resumable: a folder
  /// already known to the mirror is still walked (there may be new children
  /// under it since the last attempt), but a file already known is skipped.
  /// An item bootstrap cannot safely write is recorded via
  /// [SyncMirrorRepository.recordFailedEvent] rather than dropped silently —
  /// the same Skipped-items list the delta path (F1/F3/F5) surfaces through,
  /// so the promise in the non-empty-folder dialog ("listed as skipped
  /// instead") holds for backfilled files too, not just delta ones.
  Future<void> _bootstrap(String syncFolderPath) async {
    await _bootstrapFolder(null, syncFolderPath, syncFolderPath);
  }

  Future<void> _bootstrapFolder(
    String? folderId,
    String dirPath,
    String syncFolderPath,
  ) async {
    var page = 1;
    while (true) {
      final result = await _fileRepository.listChildren(folderId, page: page);
      for (final item in result.items) {
        if (item.isDeleted) continue;
        await _bootstrapItem(item, dirPath, syncFolderPath);
      }
      if (!result.hasMore) break;
      page++;
    }
  }

  Future<void> _bootstrapItem(
    FileItem item,
    String dirPath,
    String syncFolderPath,
  ) async {
    final existing = await _mirror.getByServerId(item.id);

    if (item.isFolder) {
      String localPath;
      if (existing != null) {
        localPath = existing.localPath;
      } else {
        try {
          localPath = _safeChildPath(syncFolderPath, dirPath, item.name, _isWindows);
          await Directory(localPath).create(recursive: true);
          await _mirror.upsert(SyncMirrorEntry(
            serverId: item.id,
            localPath: localPath,
            isFolder: true,
            updatedAt: item.updatedAt,
            syncedAt: DateTime.now(),
          ));
        } on UnsafeRemoteNameException catch (e) {
          // The whole subtree under an unsafe folder name would otherwise be
          // invisible: not synced, not listed, and never revisited (siblings
          // still need walking, so this returns rather than rethrows).
          await _mirror.recordFailedEvent(item.id, _bootstrapEventId, e.toString());
          return;
        } on FileSystemException catch (e) {
          // The OS refused to create the directory for a reason no name
          // check predicts (a permission-denied parent, a path already
          // occupied by a file, a full disk). This call used to sit outside
          // every try, so this exact failure escaped through _bootstrap
          // into _pullOnce, markBootstrapped never ran, and every later
          // poll re-walked the whole tree only to fail here again, forever
          // (PR #12 review round 3, B3).
          await _mirror.recordFailedEvent(item.id, _bootstrapEventId, e.message);
          return;
        }
      }
      await _bootstrapFolder(item.id, localPath, syncFolderPath);
      return;
    }

    if (existing != null) return; // Already delivered by the drain above, or a previous run.

    try {
      final localPath = _safeChildPath(syncFolderPath, dirPath, item.name, _isWindows);
      // Same untracked-file guard as delta apply (F3): backfill must not
      // clobber a file the user already has.
      if (await File(localPath).exists()) {
        await _mirror.recordFailedEvent(
          item.id,
          _bootstrapEventId,
          'local conflict: local file differs from what was last synced: $localPath',
        );
        return;
      }

      final bytes = await _fileRepository.downloadFile(item.id);
      await File(localPath).parent.create(recursive: true);
      await File(localPath).writeAsBytes(bytes, flush: true);
      await _mirror.upsert(SyncMirrorEntry(
        serverId: item.id,
        localPath: localPath,
        isFolder: false,
        sizeBytes: item.sizeBytes,
        contentHash: sha256.convert(bytes).toString(),
        updatedAt: item.updatedAt,
        syncedAt: DateTime.now(),
      ));
    } on UnsafeRemoteNameException catch (e) {
      await _mirror.recordFailedEvent(item.id, _bootstrapEventId, e.toString());
    } on FileSystemException catch (e) {
      await _mirror.recordFailedEvent(item.id, _bootstrapEventId, e.message);
    }
  }
}

/// Windows and POSIX both forbid `/`; Windows additionally forbids `\` and
/// `:` (drive letters), and treats a bare `.`/`..` as a directory reference
/// rather than a real entry. That second point is broader than just those
/// two literals: Win32 trims trailing dots and spaces off a path component
/// before resolving it, so `".. "`, `"..."`, `". "` and `"   "` all resolve
/// the *same way* `.`/`..` do even though none of them equal those literals
/// as strings — verified directly against this app's own path handling
/// (`Directory(p.join(root, '.. ')).delete(recursive: true)` deletes `root`
/// itself, and `p.canonicalize`/`p.isWithin` do not catch it, because they
/// only special-case the exact strings `.`/`..`; see PR #12 review round 2,
/// R1). Rejecting anything that is *only* dots and spaces closes that
/// without needing the two literal checks separately. A server-supplied
/// name has to be exactly one plain path segment for `p.join` to be safe.
bool _isPlainSegment(String name, bool isWindows) =>
    name.isNotEmpty &&
    !RegExp(r'^[. ]+$').hasMatch(name) &&
    !name.contains('/') &&
    !name.contains('\\') &&
    !name.contains(':') &&
    // Win32-specific unwritable names (a trailing dot/space, a reserved
    // device stem, an illegal character) are rejected only on Windows —
    // per the PR #12 review round 3 human decision, the server does not
    // enforce these and a macOS client syncs such names normally. [isWindows]
    // is [PullSyncService]'s injected platform decision (defaulting to
    // [Platform.isWindows]), not a direct read of the host here, so tests can
    // exercise both branches without depending on the OS they happen to run
    // on. See [violatesWin32NameRules].
    !(isWindows && violatesWin32NameRules(name));

/// Characters Win32 forbids in a path segment beyond the ones already
/// checked above (`/`, `\`, `:`): `< > " | ? *` and the C0 control range.
/// macOS and Linux allow all of these in a filename.
final RegExp _win32IllegalChars = RegExp(r'[<>"|?*\x00-\x1F]');

/// `CON`, `PRN`, `AUX`, `NUL`, `COM0`-`COM9`, `LPT0`-`LPT9`, case-insensitive,
/// with or without an extension — `nul.txt` is just as reserved as bare
/// `nul` to this check. Whether a given one of these actually fails to
/// write is Windows version- and build-dependent (on the machine the PR #12
/// review ran its probes on, only bare `nul` failed — `aux`, `com1` and
/// `nul.txt` all wrote fine), and that dependence is exactly why they are
/// rejected up front instead of discovered at write time.
const _win32ReservedStems = {
  'con', 'prn', 'aux', 'nul', //
  'com0', 'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9', //
  'lpt0', 'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

/// True if Win32 cannot write [name] as given: a trailing dot or space
/// (Win32 silently trims these off before resolving a path component,
/// which is what let a remote `foo.` alias the local `foo` a sibling
/// already occupies — PR #12 review round 3, B1), one of
/// [_win32IllegalChars], or a reserved device stem. Deliberately
/// platform-agnostic: the only production call site ([_isPlainSegment])
/// gates it behind [PullSyncService]'s injected `isWindows` decision, but the
/// rule table itself is exercised directly in tests without needing to fake
/// the host OS.
@visibleForTesting
bool violatesWin32NameRules(String name) =>
    name.endsWith('.') ||
    name.endsWith(' ') ||
    _win32IllegalChars.hasMatch(name) ||
    _win32ReservedStems.contains(name.split('.').first.toLowerCase());

/// Joins [name] under [dirPath], rejecting it outright if it is not a safe
/// path segment, then asserting the canonicalised result still lands inside
/// [syncFolderPath]. [_isPlainSegment] is the primary control; the
/// canonicalised containment check is the backstop — it is checked on the
/// resolved result, not as a string prefix on the raw input. The *returned*
/// path is the plain join, not the canonicalised one: on Windows,
/// `p.canonicalize` lowercases the whole path, and that is not the path
/// this app should be writing to, storing in the mirror, or showing the
/// user.
String _safeChildPath(String syncFolderPath, String dirPath, String name, bool isWindows) {
  if (!_isPlainSegment(name, isWindows)) {
    throw UnsafeRemoteNameException(name);
  }
  final joined = p.join(dirPath, name);
  _assertWithinSyncFolder(syncFolderPath, joined);
  return joined;
}

void _assertWithinSyncFolder(String syncFolderPath, String path) {
  final root = p.canonicalize(syncFolderPath);
  final resolved = p.canonicalize(path);
  if (!p.isWithin(root, resolved)) {
    throw UnsafeRemoteNameException('resolved path escapes the sync folder: $path');
  }
}

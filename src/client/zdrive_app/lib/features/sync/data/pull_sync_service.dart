import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
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

  PullSyncService(
    this._syncDataSource,
    this._deviceRegistration,
    this._mirror,
    this._fileRepository,
  );

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

  Future<int> _pullOnce(String syncFolderPath) async {
    final deviceId = await _deviceRegistration.ensureRegistered();

    // A quarantined entry's cause may no longer hold by the next poll (the
    // file that was locked is closed now, the drive is back). _applyUpsert
    // and _applyDelete are keyed on fileId and fetch current server state,
    // not on the original event — so a failed row is already re-appliable
    // without replaying anything from the event log. _applyUpsert alone
    // covers both directions: if the file is now gone server-side, its
    // internal 404 handling falls through to _applyDelete itself. Runs
    // before the drain below so a fix picked up here does not race a fresh
    // failure for the same file later in this same call.
    for (final failed in await _mirror.getFailedEvents()) {
      try {
        await _applyUpsert(failed.fileId, syncFolderPath);
        await _mirror.clearFailedEvent(failed.fileId);
      } on UnsafeRemoteNameException {
        // Still an unsafe name — stays quarantined.
      } on LocalConflictException {
        // Still conflicts with an untracked local change — stays quarantined.
      } on FileSystemException {
        // Still failing at the OS level — try again on the next poll.
      }
    }

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

    await _deleteLocal(syncFolderPath, entry.localPath, entry.isFolder);
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
    final localPath = _safeChildPath(syncFolderPath, dirPath, remote.name);
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
        // (_deleteLocal).
        await _deleteLocal(syncFolderPath, previous.localPath, previous.isFolder);
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
    final dirPath = _safeChildPath(syncFolderPath, parentPath, folder.name);

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

  Future<void> _deleteLocal(String syncFolderPath, String path, bool isFolder) async {
    _assertWithinSyncFolder(syncFolderPath, path);
    try {
      if (isFolder) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }
    } on PathNotFoundException {
      // Already gone locally — deleting is idempotent, not an error.
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
          localPath = _safeChildPath(syncFolderPath, dirPath, item.name);
        } on UnsafeRemoteNameException catch (e) {
          // The whole subtree under an unsafe folder name would otherwise be
          // invisible: not synced, not listed, and never revisited (siblings
          // still need walking, so this returns rather than rethrows).
          await _mirror.recordFailedEvent(item.id, _bootstrapEventId, e.toString());
          return;
        }
        await Directory(localPath).create(recursive: true);
        await _mirror.upsert(SyncMirrorEntry(
          serverId: item.id,
          localPath: localPath,
          isFolder: true,
          updatedAt: item.updatedAt,
          syncedAt: DateTime.now(),
        ));
      }
      await _bootstrapFolder(item.id, localPath, syncFolderPath);
      return;
    }

    if (existing != null) return; // Already delivered by the drain above, or a previous run.

    try {
      final localPath = _safeChildPath(syncFolderPath, dirPath, item.name);
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
bool _isPlainSegment(String name) =>
    name.isNotEmpty &&
    !RegExp(r'^[. ]+$').hasMatch(name) &&
    !name.contains('/') &&
    !name.contains('\\') &&
    !name.contains(':');

/// Joins [name] under [dirPath], rejecting it outright if it is not a safe
/// path segment, then asserting the canonicalised result still lands inside
/// [syncFolderPath]. [_isPlainSegment] is the primary control; the
/// canonicalised containment check is the backstop — it is checked on the
/// resolved result, not as a string prefix on the raw input. The *returned*
/// path is the plain join, not the canonicalised one: on Windows,
/// `p.canonicalize` lowercases the whole path, and that is not the path
/// this app should be writing to, storing in the mirror, or showing the
/// user.
String _safeChildPath(String syncFolderPath, String dirPath, String name) {
  if (!_isPlainSegment(name)) {
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

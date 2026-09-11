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
import 'push_sync_service.dart';
import 'sync_name_rules.dart';

/// Finds local changes under the designated sync folder and reports them to
/// the server — the push half of sync. State-based, not event-based: every
/// call diffs the current disk contents against the mirror
/// ([SyncMirrorRepository], the same table [PullSyncService] maintains), so
/// there is no local change queue to lose — anything done while offline is
/// simply found by the next [scanOnce].
///
/// Conflicts are last-write-wins: a local edit is uploaded as the new
/// current version regardless of what else happened to the file server-side
/// (see [_uploadChangedFile]'s 404 handling and [_uploadNewFile]'s 409
/// handling for the two ways that surfaces).
@lazySingleton
class LocalChangeScanner {
  final SyncMirrorRepository _mirror;
  final FileRepository _fileRepository;
  final PushSyncService _push;

  // Same injected-platform pattern as PullSyncService: the scanner must skip
  // exactly what pull refuses to create (see isSyncableName), including its
  // Windows-only name rules, and tests need to exercise both branches
  // without depending on the host OS.
  final bool _isWindows;

  // Whether the OS the sync folder lives on treats file/folder names as
  // equal ignoring case (Windows and macOS; Linux is not). Drives the
  // case-only rename detection in [_applyCaseRenameIfAny] (F4) — on a
  // case-sensitive host "Docs" and "docs" really are two different names,
  // so the whole check would be wrong there.
  final bool _isCaseInsensitive;

  LocalChangeScanner(
    this._mirror,
    this._fileRepository,
    this._push, {
    // Test seam only — GetIt has no `bool` to inject, so the generator must
    // leave this param out of the generated factory call; the default below
    // then reads the real platform.
    @ignoreParam bool? isWindows,
    @ignoreParam bool? isCaseInsensitive,
  })  : _isWindows = isWindows ?? Platform.isWindows,
        _isCaseInsensitive = isCaseInsensitive ?? (Platform.isWindows || Platform.isMacOS);

  /// A local path that failed during the last [scanOnce] that touched it,
  /// and when. Kept only in memory — an app restart clears it and retries
  /// immediately, which is an accepted limit (see [_isBackedOff]) rather
  /// than a persisted retry queue nobody asked for.
  final Map<String, DateTime> _failedPaths = {};

  /// How long a just-failed path is left alone before being retried again —
  /// same rationale and duration as PullSyncService's quarantine backoff: a
  /// path that fails the exact same way every poll must not be retried on
  /// every single scan forever.
  static const _retryBackoff = Duration(minutes: 5);

  bool _isBackedOff(String path) {
    final failedAt = _failedPaths[path];
    return failedAt != null && DateTime.now().difference(failedAt) < _retryBackoff;
  }

  void _recordFailure(String path, Object error, StackTrace stackTrace) {
    log('scan failed for $path', error: error, stackTrace: stackTrace, name: 'LocalChangeScanner');
    _failedPaths[path] = DateTime.now();
  }

  /// Test-only seam for exercising a retried scan without waiting out
  /// [_retryBackoff] (PR #12 review, F2 test b).
  @visibleForTesting
  void debugClearBackoff() => _failedPaths.clear();

  /// Test-only seam for simulating a new file this scan could not hash (a
  /// locked file, antivirus holding it open) without depending on
  /// OS-specific file-locking behaviour (PR #12 review, F2 test c).
  @visibleForTesting
  void debugBackOff(String path) => _failedPaths[path] = DateTime.now();

  /// Paths this test run is forcing to behave as if `File.stat()` reported
  /// "size unknown" (type == notFound, size == -1) in the unhashed-new-file
  /// check inside [_applyMoves] — the real trigger (PR #14 review round 2,
  /// finding 6) needs a file to vanish or become unreadable in the narrow
  /// window between the disk walk and that later stat call, which a
  /// portable test cannot reliably race. Same rationale as [debugBackOff].
  final Set<String> _forcedUnknownSizePaths = {};

  @visibleForTesting
  void debugForceUnknownSize(String path) => _forcedUnknownSizePaths.add(path);

  /// Server writes that succeeded this session but whose report is still
  /// owed, keyed by serverId — flushed as step 0 of every [scanOnce] before
  /// anything else runs (PR #14 review round 2, findings 1-3). In memory
  /// only: an app restart loses this map. That is safe, not silent data
  /// loss, because the matching mirror row was deliberately never written
  /// (see [_MirrorEffect]) — after a restart the affected path still looks
  /// exactly like it did before the write, so it is simply retried as a
  /// fresh operation: a changed/new file looks changed/new again and is
  /// re-uploaded (accepting at most one extra identical version — see
  /// [_uploadChangedFile]'s 404 branch), and a move/rename or delete is
  /// caught by [_applyMove]/[_deleteMissingFolder]'s own "already applied
  /// server-side" handling. Every path still ends in exactly one report,
  /// just not always via the cheaper flush below.
  final Map<String, _PendingReport> _pendingReports = {};

  /// Attempts [type] for [serverId]; on failure, logs and returns false
  /// instead of throwing. Every call site here has already made the
  /// matching server write, so a caller that gets false records a
  /// [_PendingReport] rather than losing the event outright (PR #14 review
  /// round 2, findings 1-3).
  Future<bool> _tryReport(String serverId, SyncChangeType type) async {
    try {
      await _push.reportChange(serverId, type);
      return true;
    } catch (e, st) {
      log('report deferred for $serverId ($type): SyncService unreachable',
          error: e, stackTrace: st, name: 'LocalChangeScanner');
      return false;
    }
  }

  /// Step 0 of every [scanOnce]: sends whatever reports are still owed from
  /// a previous scan's already-completed server writes, in order, then
  /// applies each one's mirror effect once its reports land. Stops at the
  /// first failure (see the comment inside) instead of pushing on to the
  /// rest of the scan.
  Future<({int pushed, bool ok})> _flushPendingReports() async {
    var pushed = 0;
    // Snapshot the keys: entries are removed from _pendingReports as they
    // flush successfully, and the loop must not revisit one just removed.
    for (final serverId in _pendingReports.keys.toList()) {
      final pending = _pendingReports[serverId]!;
      try {
        for (final type in pending.reports) {
          await _push.reportChange(serverId, type);
        }
        await pending.effect.apply(_mirror, serverId);
        _pendingReports.remove(serverId);
        pushed++;
      } catch (e, st) {
        // SyncService is still unreachable (or otherwise erroring): stop
        // the whole scan here rather than moving on to steps 1-6, which
        // would make brand new server writes whose reports could fail the
        // exact same way, compounding the backlog this flush exists to
        // drain. This entry stays in _pendingReports for the next scan;
        // whatever flushed earlier in this same loop is already gone from
        // the map, its report sent and its mirror effect applied.
        log('SyncService unreachable, scan paused with '
            '${_pendingReports.length} report(s) still owed',
            error: e, stackTrace: st, name: 'LocalChangeScanner');
        return (pushed: pushed, ok: false);
      }
    }
    return (pushed: pushed, ok: true);
  }

  /// Diffs [syncFolderPath] against the mirror and pushes whatever differs.
  /// Reads as the ordered list of steps below — each step's own doc comment
  /// explains why that order matters. Returns how many local changes were
  /// reported to the server (folder creation alone is not counted — it
  /// never calls [PushSyncService]: a pulling device fetches a file's
  /// parent folder directly by id rather than replaying a folder-create
  /// event, so pushing one would be dead weight).
  Future<int> scanOnce(String syncFolderPath) async {
    final root = syncFolderPath;

    // --- Step 0: flush reports still owed from a previous scan's server
    // writes (PR #14 review round 2, findings 1-3) ---
    // Must run before anything below reads the mirror or disk. An item
    // with a pending report has a deliberately stale mirror row (see
    // _PendingReport) and must not be touched by the rest of this scan —
    // that invariant holds automatically here, because a flush failure
    // returns immediately, before step 1 even starts.
    final flush = await _flushPendingReports();
    if (!flush.ok) return flush.pushed;

    final mirrorEntries = await _mirror.getChildrenUnder(root);
    final mirrorByPath = <String, SyncMirrorEntry>{
      for (final e in mirrorEntries) e.localPath: e,
    };
    final disk = await _walkDisk(root);
    final c = _classify(root, mirrorEntries, disk);

    // --- 0b. Case-only folder rename (F4) ---
    // Must run before anything below creates or deletes a folder: on a
    // case-insensitive platform, a "new" directory that differs from a
    // missing tracked one only by case is that folder renamed in place, not
    // a fresh folder plus a delete of the old one (createFolder would 409
    // on the server's own case-insensitive name check, and the scanner has
    // nothing else that explains that 409). Ends the scan immediately on a
    // match, win or lose (see [_applyCaseRenameIfAny]): the snapshot above
    // is now stale either way, so the next scan recomputes cleanly instead
    // of this one working off data a partial rename may have invalidated.
    final caseRenamePushed = await _applyCaseRenameIfAny(c.newDirs, c.missingDirEntries, mirrorByPath);
    if (caseRenamePushed != null) return flush.pushed + caseRenamePushed;

    var pushed = flush.pushed;

    // --- 1. Create folders ---
    for (final dir in c.newDirs) {
      await _createFolder(dir, root, mirrorByPath);
    }

    // --- 2. Moves/renames by content hash ---
    final moves = await _applyMoves(c.newFiles, c.missingFiles, root, mirrorByPath);
    pushed += moves.pushed;

    // --- 3. Upload new files (whatever step 2 did not claim as a move) ---
    pushed += await _uploadNewFiles(moves.remainingNewFiles, moves.hashes, root, mirrorByPath);

    // --- 4. Upload changed files ---
    pushed += await _uploadChangedFiles(c.changeCandidates, root, mirrorByPath);

    // --- 5 & 6. Delete missing files, then missing folders (top-most only) ---
    pushed += await _deleteMissing(c.missingFiles, c.topMostMissingDirs, moves.protectedMissingFiles);

    return pushed;
  }

  /// Walks [root] once, collecting every syncable directory and file path —
  /// used as the "what is actually on disk right now" side of [_classify].
  Future<({Set<String> dirs, Set<String> files})> _walkDisk(String root) async {
    final dirs = <String>{};
    final files = <String>{};
    await for (final entity in Directory(root).list(recursive: true, followLinks: false)) {
      if (entity is Link) continue; // never followed, never reported
      if (!_isSyncablePath(root, entity.path)) continue;
      if (entity is Directory) {
        dirs.add(entity.path);
      } else if (entity is File) {
        files.add(entity.path);
      }
    }
    return (dirs: dirs, files: files);
  }

  /// Diffs the mirror against [disk] into what each later step needs: new
  /// directories/files, tracked files present on disk (change candidates),
  /// and tracked files/directories no longer on disk (missing). Backed-off
  /// paths (see [_isBackedOff]) are filtered out of every list here so nothing
  /// downstream has to check it again.
  ({
    List<String> newDirs,
    List<String> newFiles,
    List<SyncMirrorEntry> changeCandidates,
    List<SyncMirrorEntry> missingFiles,
    List<SyncMirrorEntry> missingDirEntries,
    List<SyncMirrorEntry> topMostMissingDirs,
  }) _classify(
    String root,
    List<SyncMirrorEntry> mirrorEntries,
    ({Set<String> dirs, Set<String> files}) disk,
  ) {
    // F5: a tracked path the walk above would never surface on its own (OS
    // metadata, an Office lock file, a name this platform cannot hold) must
    // not be read as evidence of a delete — excluded from classification
    // entirely, not just from the disk-side walk.
    final mirrorFileEntries =
        mirrorEntries.where((e) => !e.isFolder && _isSyncablePath(root, e.localPath)).toList();
    final mirrorDirEntries =
        mirrorEntries.where((e) => e.isFolder && _isSyncablePath(root, e.localPath)).toList();
    final mirrorFilePaths = mirrorFileEntries.map((e) => e.localPath).toSet();
    final mirrorDirPaths = mirrorDirEntries.map((e) => e.localPath).toSet();

    // Shallowest first so a parent folder always exists in the mirror
    // before a child under it is processed (path length is a sufficient
    // depth ordering — same trick PullSyncService's folder delete uses).
    final newDirs = disk.dirs.where((d) => !mirrorDirPaths.contains(d)).toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    final newFiles = disk.files.where((f) => !mirrorFilePaths.contains(f)).toList();
    final changeCandidates = mirrorFileEntries.where((e) => disk.files.contains(e.localPath)).toList();
    // A path that flipped type (file <-> folder on disk since it was last
    // synced) falls out of both the file-present and dir-present checks
    // above for its old kind and into the new-dir/new-file checks for its
    // new kind — "missing" and "new" at once.
    var missingFiles = mirrorFileEntries.where((e) => !disk.files.contains(e.localPath)).toList();
    final missingDirEntries = mirrorDirEntries.where((e) => !disk.dirs.contains(e.localPath)).toList();

    newDirs.removeWhere(_isBackedOff);
    changeCandidates.removeWhere((e) => _isBackedOff(e.localPath));
    missingFiles = missingFiles.where((e) => !_isBackedOff(e.localPath)).toList();
    // Ancestor check runs against the full missing-dirs list (backoff must
    // not make a still-missing parent look top-most), then the result is
    // filtered by backoff.
    final topMostMissingDirs = missingDirEntries
        .where((d) => !missingDirEntries.any((other) => other != d && p.isWithin(other.localPath, d.localPath)))
        .where((d) => !_isBackedOff(d.localPath))
        .toList();

    return (
      newDirs: newDirs,
      newFiles: newFiles,
      changeCandidates: changeCandidates,
      missingFiles: missingFiles,
      missingDirEntries: missingDirEntries,
      topMostMissingDirs: topMostMissingDirs,
    );
  }

  /// Returns null if no case-only rename candidate was found (the rest of
  /// the scan proceeds normally); otherwise the scan ends immediately with
  /// this as its pushed count — 1 on success, 0 on failure (finding 4, PR
  /// #14 review round 2: a failure here must not throw out of [scanOnce],
  /// but it also did not push anything, so scanOnce's return value must
  /// say so accurately).
  Future<int?> _applyCaseRenameIfAny(
    List<String> newDirs,
    List<SyncMirrorEntry> missingDirEntries,
    Map<String, SyncMirrorEntry> mirrorByPath,
  ) async {
    if (!_isCaseInsensitive) return null;

    for (final newDir in newDirs) {
      for (final missingDir in missingDirEntries) {
        // missingDirEntries is intentionally the unfiltered list from
        // _classify (its ancestor check for topMostMissingDirs needs the
        // full picture) — so backoff has to be checked here instead,
        // otherwise a candidate whose rename just failed would be retried
        // again on the very next scan regardless (finding 4).
        if (_isBackedOff(missingDir.localPath)) continue;
        if (newDir != missingDir.localPath && newDir.toLowerCase() == missingDir.localPath.toLowerCase()) {
          try {
            await _renameFolderCase(missingDir, newDir, mirrorByPath);
            return 1;
          } catch (e, st) {
            // Finding 4: this step runs before every other step in
            // scanOnce with no try/catch of its own — an unhandled
            // failure here (e.g. renameFile 404s because the folder was
            // trashed from the web UI, which raises no sync event) used
            // to blow up the whole scan and silently stop every unrelated
            // upload/change/delete on every cycle after it. Back the path
            // off like every other write path does, and still end the
            // scan early — the disk snapshot this scan took may already
            // be half-invalidated by whichever part of the rename did
            // land, so the next scan should recompute it fresh either way.
            _recordFailure(missingDir.localPath, e, st);
            return 0;
          }
        }
      }
    }
    return null;
  }

  Future<void> _renameFolderCase(
    SyncMirrorEntry folder,
    String newPath,
    Map<String, SyncMirrorEntry> mirrorByPath,
  ) async {
    await _fileRepository.renameFile(folder.serverId, p.basename(newPath));
    await _push.reportChange(folder.serverId, SyncChangeType.rename);
    await _mirror.rePathChildren(folder.localPath, newPath);
    final updated = _mirrorRow(
      serverId: folder.serverId,
      localPath: newPath,
      isFolder: true,
      updatedAt: folder.updatedAt,
    );
    await _mirror.upsert(updated);
    mirrorByPath.remove(folder.localPath);
    mirrorByPath[newPath] = updated;
  }

  /// True if every segment of [entityPath] below [root] is safe to sync —
  /// the same rule pull enforces on a server-supplied name (isSyncableName),
  /// applied here to a local one so a name pull would refuse to create
  /// remotely is never even offered to push in the first place. Also skips
  /// Office lock/temp files (`~$Report.docx`): they come and go around a
  /// save and hold no user data of their own, so they are never uploaded
  /// and — since this same check now gates classification too, see F5 —
  /// never deleted either just because they briefly vanish from disk.
  bool _isSyncablePath(String root, String entityPath) {
    for (final segment in p.split(p.relative(entityPath, from: root))) {
      if (!isSyncableName(segment, isWindows: _isWindows)) return false;
      if (osMetadataFileNames.contains(segment)) return false;
      if (segment.startsWith(r'~$')) return false;
    }
    return true;
  }

  /// Resolves [itemPath]'s parent folder id from what this scan has
  /// reconciled so far: `null` (root) for a direct child of [root], the
  /// mirror's id for anything already tracked or created earlier in this
  /// same scan, or "not resolved" when the parent is itself new but has not
  /// (yet, or ever, this scan) been created — the caller skips the item
  /// rather than guessing; the next scan retries once the parent exists.
  ({bool resolved, String? parentId}) _resolveParent(
    String itemPath,
    String root,
    Map<String, SyncMirrorEntry> mirrorByPath,
  ) {
    final parentPath = p.dirname(itemPath);
    if (parentPath == root) return (resolved: true, parentId: null);
    final entry = mirrorByPath[parentPath];
    if (entry == null) return (resolved: false, parentId: null);
    return (resolved: true, parentId: entry.serverId);
  }

  Future<void> _createFolder(
    String dirPath,
    String root,
    Map<String, SyncMirrorEntry> mirrorByPath,
  ) async {
    final resolution = _resolveParent(dirPath, root, mirrorByPath);
    if (!resolution.resolved) return; // parent failed earlier in this same scan

    try {
      final folder = await _fileRepository.createFolder(resolution.parentId, p.basename(dirPath));
      final entry = _mirrorRow(
        serverId: folder.id,
        localPath: dirPath,
        isFolder: true,
        updatedAt: folder.updatedAt,
      );
      await _mirror.upsert(entry);
      mirrorByPath[dirPath] = entry; // so a child under it resolves within this same scan
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        // Exists server-side already but this device has not pulled it yet
        // (e.g. created on another device). Not a failure to back off —
        // the next pull reconciles it into the mirror normally, and the
        // next scan then finds children under it, if any.
        log('folder already exists server-side, waiting for pull: $dirPath', name: 'LocalChangeScanner');
        return;
      }
      _recordFailure(dirPath, e, StackTrace.current);
    } catch (e, st) {
      _recordFailure(dirPath, e, st);
    }
  }

  Future<Map<String, ({String hash, int size})>> _hashFiles(Iterable<String> paths) async {
    final result = <String, ({String hash, int size})>{};
    for (final path in paths) {
      try {
        final bytes = await File(path).readAsBytes();
        result[path] = (hash: sha256.convert(bytes).toString(), size: bytes.length);
      } catch (e, st) {
        _recordFailure(path, e, st);
      }
    }
    return result;
  }

  /// Step 2: matches each new file against the missing tracked files it
  /// could be a move/rename of, by content hash, and applies whichever
  /// matches turn out unambiguous. Also works out which missing files must
  /// not be deleted later in this same scan even though they still look
  /// "missing" here (PR #12 review, F2): an entry a move attempt claimed
  /// but failed to apply (it may have partially landed server-side already,
  /// so deleting its old record here could trash whatever it moved to), and
  /// any missing file whose size matches a new file this scan could not
  /// even hash yet (it might be the other half of a move nothing above
  /// could prove — or, if that new file's size itself is unknown, every
  /// missing file is left alone rather than risk the wrong one).
  Future<({
    int pushed,
    Map<String, ({String hash, int size})> hashes,
    List<String> remainingNewFiles,
    Set<SyncMirrorEntry> protectedMissingFiles,
  })> _applyMoves(
    List<String> newFiles,
    List<SyncMirrorEntry> missingFiles,
    String root,
    Map<String, SyncMirrorEntry> mirrorByPath,
  ) async {
    // Every new file's hash is needed for matching regardless of whether it
    // turns out to be a move, so this runs once up front and the result is
    // reused by the upload step below for whichever files aren't moves.
    final hashes = await _hashFiles(newFiles.where((f) => !_isBackedOff(f)));
    final protectedMissingFiles = <SyncMirrorEntry>{};
    final remainingNewFiles = <String>[];
    var pushed = 0;

    for (final filePath in hashes.keys) {
      final hs = hashes[filePath]!;
      // Empty files all hash the same — matching on that would pair up
      // unrelated empty files instead of detecting a real rename/move.
      if (hs.size > 0) {
        final candidates =
            missingFiles.where((m) => m.contentHash == hs.hash && m.sizeBytes == hs.size).toList();
        if (candidates.length == 1) {
          final missing = candidates.single;
          // Claimed either way: a failed move may still have partially
          // landed server-side, so this entry must not be treated as an
          // ordinary "missing" file by the delete step later in this scan.
          missingFiles.remove(missing);
          try {
            if (await _applyMove(filePath, missing, root, mirrorByPath, hs)) pushed++;
          } catch (e, st) {
            _recordFailure(filePath, e, st);
            protectedMissingFiles.add(missing);
          }
          continue;
        }
      }
      remainingNewFiles.add(filePath);
    }

    final unhashedNewFiles = newFiles.where((f) => !hashes.containsKey(f));
    final unhashedSizes = <int>{};
    // File.stat() never throws (finding 6, PR #14 review round 2) — a
    // vanished or unreadable file comes back as type == notFound with
    // size == -1, not an exception, so that is the condition to check for
    // instead of a try/catch that can never fire. A file that stays
    // unreadable keeps protecting every same-size missing file (and their
    // missing parent folders) on every scan until it can finally be read
    // — deliberate, this never guesses at a file's id from a size match
    // alone.
    var unknownSize = false;
    for (final f in unhashedNewFiles) {
      final size = _forcedUnknownSizePaths.contains(f) ? -1 : (await File(f).stat()).size;
      if (size < 0) {
        unknownSize = true;
      } else {
        unhashedSizes.add(size);
      }
    }
    if (unknownSize) {
      protectedMissingFiles.addAll(missingFiles);
    } else {
      protectedMissingFiles.addAll(missingFiles.where((e) => unhashedSizes.contains(e.sizeBytes)));
    }

    return (
      pushed: pushed,
      hashes: hashes,
      remainingNewFiles: remainingNewFiles,
      protectedMissingFiles: protectedMissingFiles,
    );
  }

  /// Applies one move/rename candidate matched by content hash in
  /// [_applyMoves]. Returns whether a report was actually sent this call
  /// (used only so the caller can count it toward [scanOnce]'s pushed
  /// total) — false covers two different "nothing to finish this call"
  /// cases: [missing] turned out not to be a move at all (finding 5 — a
  /// 404 from getFile means the server node is simply gone), and a report
  /// that had to be deferred rather than lost (finding 1 — see
  /// [_PendingReport]).
  Future<bool> _applyMove(
    String newPath,
    SyncMirrorEntry missing,
    String root,
    Map<String, SyncMirrorEntry> mirrorByPath,
    ({String hash, int size}) hashSize,
  ) async {
    final resolution = _resolveParent(newPath, root, mirrorByPath);
    if (!resolution.resolved) {
      throw StateError('destination folder not resolved this scan: ${p.dirname(newPath)}');
    }

    // What the local diff itself says happened — decided independently of
    // what getFile reports below, and used only to decide *whether to
    // report*. getFile still decides *whether to call the server*: a
    // previous attempt at this exact move may have partially landed
    // (moveFile succeeded, then renameFile or reportChange threw) and this
    // call is that retry. Reporting the local diff even when the server
    // call itself is skipped is what closes finding 1 (PR #14 review round
    // 2): the old code decided both from getFile, so a retry that found
    // the server already caught up silently skipped the report too, and
    // the event was never sent. A duplicate report is harmless — pull
    // reconciles through getFile either way.
    final movedParent = p.dirname(missing.localPath) != p.dirname(newPath);
    final renamedName = p.basename(missing.localPath) != p.basename(newPath);

    FileItem current;
    try {
      current = await _fileRepository.getFile(missing.serverId);
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      // Finding 5: the file is gone server-side (e.g. trashed from the web
      // UI, which raises no sync event) — not a move to retry. Drop the
      // stale record; the new local file is left for the next scan to
      // pick up as an ordinary new file, simpler than threading it back
      // into this scan's own upload step from here.
      await _mirror.deleteByServerId(missing.serverId);
      mirrorByPath.remove(missing.localPath);
      return false;
    }

    final pendingTypes = <SyncChangeType>[];

    if (movedParent) {
      if (current.parentId != resolution.parentId) {
        await _fileRepository.moveFile(missing.serverId, resolution.parentId);
      }
      if (!await _tryReport(missing.serverId, SyncChangeType.move)) {
        pendingTypes.add(SyncChangeType.move);
      }
    }

    final newName = p.basename(newPath);
    if (renamedName) {
      if (current.name != newName) {
        await _fileRepository.renameFile(missing.serverId, newName);
      }
      if (!await _tryReport(missing.serverId, SyncChangeType.rename)) {
        pendingTypes.add(SyncChangeType.rename);
      }
    }

    final updated = _mirrorRow(
      serverId: missing.serverId,
      localPath: newPath,
      isFolder: false,
      sizeBytes: hashSize.size,
      contentHash: hashSize.hash,
      updatedAt: missing.updatedAt,
    );

    if (pendingTypes.isNotEmpty) {
      // At least one report above failed even though its server write
      // already landed — remember it instead of losing it (finding 1) and
      // leave the mirror row exactly as it was; mirrorByPath.remove keeps
      // a child under the new path from resolving against it this same
      // scan (see _pendingReports' doc comment: this row is stale by
      // design until the flush applies it).
      _pendingReports[missing.serverId] = _PendingReport(pendingTypes, _MirrorEffect.upsert(updated));
      mirrorByPath.remove(missing.localPath);
      return false;
    }

    await _mirror.upsert(updated);
    mirrorByPath.remove(missing.localPath);
    mirrorByPath[newPath] = updated;
    return true;
  }

  Future<int> _uploadNewFiles(
    List<String> remainingNewFiles,
    Map<String, ({String hash, int size})> hashes,
    String root,
    Map<String, SyncMirrorEntry> mirrorByPath,
  ) async {
    var pushed = 0;
    for (final filePath in remainingNewFiles) {
      try {
        if (await _uploadNewFile(filePath, root, mirrorByPath, hashes[filePath]!)) pushed++;
      } catch (e, st) {
        _recordFailure(filePath, e, st);
      }
    }
    return pushed;
  }

  /// Returns whether this call fully completed (write and report both
  /// landed) — used only so the caller can count it toward [scanOnce]'s
  /// pushed total; see [_finishUpload].
  Future<bool> _uploadNewFile(
    String filePath,
    String root,
    Map<String, SyncMirrorEntry> mirrorByPath,
    ({String hash, int size}) hashSize,
  ) async {
    final resolution = _resolveParent(filePath, root, mirrorByPath);
    if (!resolution.resolved) return false; // parent folder failed earlier this scan

    final name = p.basename(filePath);
    final file = File(filePath);

    try {
      final id = await _fileRepository.uploadFile(
        resolution.parentId,
        name,
        file.openRead(),
        hashSize.size,
        null,
      );
      return await _finishUpload(id, filePath, hashSize, SyncChangeType.create, mirrorByPath);
    } on DioException catch (e) {
      if (e.response?.statusCode != 409) rethrow;
      // Last write wins: a file with this name already exists server-side
      // in this folder (created on another device, not yet pulled here) —
      // upload into it as a new version instead of failing.
      final existing = await _findExistingFileByName(resolution.parentId, name);
      if (existing == null) rethrow;
      await _fileRepository.uploadNewVersion(existing.id, name, file.openRead(), hashSize.size);
      return await _finishUpload(existing.id, filePath, hashSize, SyncChangeType.update, mirrorByPath);
    }
  }

  /// Shared tail of every "server write is done, now report + commit the
  /// mirror" path (PR #14 review round 2, findings 1-3): reports [type]
  /// for [serverId] and, only if that succeeds, upserts the mirror row —
  /// so a scan that dies right after the write always leaves a consistent
  /// trail: either both the report and the mirror commit landed, or
  /// neither did (the report is remembered instead, see [_PendingReport],
  /// so the very next scan retries just the report, not the write).
  Future<bool> _finishUpload(
    String serverId,
    String filePath,
    ({String hash, int size}) hashSize,
    SyncChangeType type,
    Map<String, SyncMirrorEntry> mirrorByPath,
  ) async {
    final entry = _mirrorRow(
      serverId: serverId,
      localPath: filePath,
      isFolder: false,
      sizeBytes: hashSize.size,
      contentHash: hashSize.hash,
      updatedAt: DateTime.now(),
    );
    if (await _tryReport(serverId, type)) {
      await _mirror.upsert(entry);
      mirrorByPath[filePath] = entry;
      return true;
    }
    _pendingReports[serverId] = _PendingReport([type], _MirrorEffect.upsert(entry));
    return false;
  }

  /// A non-folder child named [name] directly under [parentId], if one
  /// already exists — paginated, since a folder can hold more than one
  /// page. Mirrors FileRepositoryImpl._findExistingFile's shape.
  Future<FileItem?> _findExistingFileByName(String? parentId, String name) async {
    var page = 1;
    const pageSize = 200;
    while (true) {
      final result = await _fileRepository.listChildren(parentId, page: page, pageSize: pageSize);
      for (final item in result.items) {
        if (item.name == name && !item.isFolder) return item;
      }
      if (!result.hasMore) return null;
      page++;
    }
  }

  Future<int> _uploadChangedFiles(
    List<SyncMirrorEntry> changeCandidates,
    String root,
    Map<String, SyncMirrorEntry> mirrorByPath,
  ) async {
    var pushed = 0;
    for (final entry in changeCandidates) {
      try {
        if (await _uploadChangedFile(entry, root, mirrorByPath)) pushed++;
      } catch (e, st) {
        _recordFailure(entry.localPath, e, st);
      }
    }
    return pushed;
  }

  /// Returns whether a change was actually reported — false for the common
  /// case (untouched file) so the caller does not count it toward [scanOnce]'s
  /// returned total.
  Future<bool> _uploadChangedFile(
    SyncMirrorEntry entry,
    String root,
    Map<String, SyncMirrorEntry> mirrorByPath,
  ) async {
    final file = File(entry.localPath);
    final stat = await file.stat();
    // Cheap pre-filter so an untouched tree is not re-hashed on every poll —
    // behavioural correctness still comes from the hash compare below, this
    // just skips reaching for it when nothing plausibly changed.
    if (entry.sizeBytes == stat.size && !stat.modified.isAfter(entry.syncedAt)) {
      return false;
    }

    final bytes = await file.readAsBytes();
    final hash = sha256.convert(bytes).toString();
    if (hash == entry.contentHash) return false; // touched (e.g. re-saved), content unchanged

    try {
      await _fileRepository.uploadNewVersion(
        entry.serverId,
        p.basename(entry.localPath),
        file.openRead(),
        bytes.length,
      );
      return await _finishUpload(
        entry.serverId,
        entry.localPath,
        (hash: hash, size: bytes.length),
        SyncChangeType.update,
        mirrorByPath,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      // Last write wins: the file was deleted server-side (e.g. by another
      // device) while this one still had it. Re-create it as a new file
      // under the same local parent rather than losing the local edit.
      // The stale mirror row is cleared right away, independent of
      // whether the report below lands this call or is deferred (finding
      // 3, PR #14 review round 2) — if the app restarts before a deferred
      // report ever flushes, this path then looks like a brand new file
      // on the next scan and is uploaded again as one extra version
      // (known limit, see _pendingReports' doc comment).
      final resolution = _resolveParent(entry.localPath, root, mirrorByPath);
      final newId = await _fileRepository.uploadFile(
        resolution.resolved ? resolution.parentId : null,
        p.basename(entry.localPath),
        file.openRead(),
        bytes.length,
        null,
      );
      await _mirror.deleteByServerId(entry.serverId);
      return await _finishUpload(
        newId,
        entry.localPath,
        (hash: hash, size: bytes.length),
        SyncChangeType.create,
        mirrorByPath,
      );
    }
  }

  /// Steps 5 & 6: deletes whatever is still missing after everything above —
  /// files first, then top-most missing folders (which already take every
  /// ordinary file under them along, see the comment below). Anything
  /// [protectedMissingFiles] claims (F2) is left alone rather than deleted,
  /// and so is a folder that would take one of those protected files' old
  /// subtree with it — deleting the file's old server record was already
  /// ruled unsafe above; deleting the folder it used to live under does the
  /// same thing at one remove.
  Future<int> _deleteMissing(
    List<SyncMirrorEntry> missingFiles,
    List<SyncMirrorEntry> topMostMissingDirs,
    Set<SyncMirrorEntry> protectedMissingFiles,
  ) async {
    var pushed = 0;

    final dirsToDelete = topMostMissingDirs
        .where((d) => !protectedMissingFiles.any((f) => p.isWithin(d.localPath, f.localPath)))
        .toList();

    // A missing file that lives under a folder about to be deleted below is
    // left for that step instead: FileService's deleteFile on the folder
    // already trashes the whole subtree, so deleting the file here too
    // would be a redundant server call and a redundant push event — one
    // folder-delete event is enough for another device to reconcile the
    // whole subtree (see PullSyncService's own folder-delete, which walks
    // tracked children locally from a single event the same way).
    final missingFilesToDelete = missingFiles
        .where((e) => !protectedMissingFiles.contains(e))
        .where((e) => !dirsToDelete.any((d) => p.isWithin(d.localPath, e.localPath)))
        .toList();
    for (final entry in missingFilesToDelete) {
      try {
        if (await _deleteMissingFile(entry)) pushed++;
      } catch (e, st) {
        _recordFailure(entry.localPath, e, st);
      }
    }

    for (final dir in dirsToDelete) {
      try {
        if (await _deleteMissingFolder(dir)) pushed++;
      } catch (e, st) {
        _recordFailure(dir.localPath, e, st);
      }
    }

    return pushed;
  }

  /// Returns whether the file was actually deleted server-side by this
  /// call (used only so the delete step can count it toward [scanOnce]'s
  /// returned total) — false on a 404, since another device (or an
  /// earlier, only-partially-completed attempt of this same call) already
  /// deleted it and this device did not cause anything new. A report is
  /// sent either way (PR #12 review, F6): even on that 404, another device
  /// may not have learned about the delete yet if its own delete event
  /// never fired.
  Future<bool> _deleteMissingFile(SyncMirrorEntry entry) async {
    var actuallyDeleted = true;
    try {
      await _fileRepository.deleteFile(entry.serverId);
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      actuallyDeleted = false;
    }
    final reported = await _finishDelete(entry.serverId, entry.localPath, isFolder: false);
    return actuallyDeleted && reported;
  }

  /// Finding 2 (PR #14 review round 2): a retried deleteFile 404s once the
  /// server already trashed this folder on an earlier, only-partially-
  /// completed attempt — handled the same way [_deleteMissingFile] handles
  /// it for files, instead of having no 404 branch of its own and retrying
  /// forever. Same "counts toward pushed" contract as [_deleteMissingFile]:
  /// false on a 404, since this device did not cause anything new.
  Future<bool> _deleteMissingFolder(SyncMirrorEntry dir) async {
    var actuallyDeleted = true;
    try {
      await _fileRepository.deleteFile(dir.serverId); // FileService trashes the whole subtree
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      actuallyDeleted = false;
    }
    final reported = await _finishDelete(dir.serverId, dir.localPath, isFolder: true);
    return actuallyDeleted && reported;
  }

  /// Shared tail of a delete write (findings 1-3 pattern, applied to
  /// deletes): reports the delete and, only if that succeeds, clears the
  /// mirror row(s) at [localPath] via [_MirrorEffect.delete] — the entry
  /// itself, plus (if [isFolder]) everything still tracked under it. A
  /// failed report is deferred instead (see [_PendingReport]) so the very
  /// next scan's flush retries the *report*, not a server delete that
  /// already happened (and, for a folder, would just 404 again). Returns
  /// whether the report landed this call.
  Future<bool> _finishDelete(String serverId, String localPath, {required bool isFolder}) async {
    final effect = _MirrorEffect.delete(localPath, isFolder: isFolder);
    if (await _tryReport(serverId, SyncChangeType.delete)) {
      await effect.apply(_mirror, serverId);
      return true;
    }
    _pendingReports[serverId] = _PendingReport([SyncChangeType.delete], effect);
    return false;
  }

  /// Builds a mirror row stamped with the current time as [SyncMirrorEntry
  /// .syncedAt] — every call site below reaches this only right after its
  /// own write to the server succeeded, so "now" is accurate for all of
  /// them. One small helper instead of the same seven-field constructor
  /// repeated at every write site (PR #12 review, F9).
  SyncMirrorEntry _mirrorRow({
    required String serverId,
    required String localPath,
    required bool isFolder,
    int? sizeBytes,
    String? contentHash,
    required DateTime updatedAt,
  }) =>
      SyncMirrorEntry(
        serverId: serverId,
        localPath: localPath,
        isFolder: isFolder,
        sizeBytes: sizeBytes,
        contentHash: contentHash,
        updatedAt: updatedAt,
        syncedAt: DateTime.now(),
      );
}

/// The local mirror change to make once every report in a [_PendingReport]
/// has finally landed — either "upsert this row" (a create/update/move/
/// rename whose server write already succeeded) or "clear this row, plus
/// everything under it if it turns out to be a folder" (a delete whose
/// server write already succeeded). Exactly one of the two factories is
/// used at a time; see [LocalChangeScanner._pendingReports].
class _MirrorEffect {
  final SyncMirrorEntry? _upsertEntry;
  final String? _deleteLocalPath;
  final bool _deleteIsFolder;

  const _MirrorEffect.upsert(SyncMirrorEntry entry)
      : _upsertEntry = entry,
        _deleteLocalPath = null,
        _deleteIsFolder = false;

  // isFolder gates the getChildrenUnder lookup below: a file can never have
  // mirror rows under it, so skipping that call for a file delete is not
  // just an optimisation — a plain file's own path was never a valid
  // argument to getChildrenUnder in the first place (no other call site
  // ever queried one).
  const _MirrorEffect.delete(String localPath, {required bool isFolder})
      : _upsertEntry = null,
        _deleteLocalPath = localPath,
        _deleteIsFolder = isFolder;

  Future<void> apply(SyncMirrorRepository mirror, String serverId) async {
    if (_upsertEntry != null) {
      await mirror.upsert(_upsertEntry);
      return;
    }
    if (!_deleteIsFolder) {
      await mirror.deleteByServerId(serverId);
      return;
    }
    // Read the children before removing anything, so this still sees
    // every mirror row that lived under this folder (same ordering
    // _deleteMissingFolder always used).
    final children = await mirror.getChildrenUnder(_deleteLocalPath!);
    await mirror.deleteByServerId(serverId);
    for (final child in children) {
      await mirror.deleteByServerId(child.serverId);
    }
  }
}

/// One server write whose write already landed but whose
/// [PushSyncService.reportChange] call threw — kept only in memory (see
/// [LocalChangeScanner._pendingReports]) so the very next [LocalChangeScanner
/// .scanOnce] retries just the report, never the write (PR #14 review round
/// 2, findings 1-3).
class _PendingReport {
  final List<SyncChangeType> reports;
  final _MirrorEffect effect;
  const _PendingReport(this.reports, this.effect);
}

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

  /// Diffs [syncFolderPath] against the mirror and pushes whatever differs.
  /// Reads as the ordered list of steps below — each step's own doc comment
  /// explains why that order matters. Returns how many local changes were
  /// reported to the server (folder creation alone is not counted — it
  /// never calls [PushSyncService]: a pulling device fetches a file's
  /// parent folder directly by id rather than replaying a folder-create
  /// event, so pushing one would be dead weight).
  Future<int> scanOnce(String syncFolderPath) async {
    final root = syncFolderPath;

    final mirrorEntries = await _mirror.getChildrenUnder(root);
    final mirrorByPath = <String, SyncMirrorEntry>{
      for (final e in mirrorEntries) e.localPath: e,
    };
    final disk = await _walkDisk(root);
    final c = _classify(root, mirrorEntries, disk);

    // --- 0. Case-only folder rename (F4) ---
    // Must run before anything below creates or deletes a folder: on a
    // case-insensitive platform, a "new" directory that differs from a
    // missing tracked one only by case is that folder renamed in place, not
    // a fresh folder plus a delete of the old one (createFolder would 409
    // on the server's own case-insensitive name check, and the scanner has
    // nothing else that explains that 409). Ends the scan immediately on a
    // match: the snapshot above is now stale (the renamed folder and
    // everything under it moved), so the next scan recomputes cleanly
    // against the updated mirror instead of this one working off data that
    // no longer matches disk.
    if (await _applyCaseRenameIfAny(c.newDirs, c.missingDirEntries, mirrorByPath)) {
      return 1;
    }

    var pushed = 0;

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

  Future<bool> _applyCaseRenameIfAny(
    List<String> newDirs,
    List<SyncMirrorEntry> missingDirEntries,
    Map<String, SyncMirrorEntry> mirrorByPath,
  ) async {
    if (!_isCaseInsensitive) return false;

    for (final newDir in newDirs) {
      for (final missingDir in missingDirEntries) {
        if (newDir != missingDir.localPath && newDir.toLowerCase() == missingDir.localPath.toLowerCase()) {
          await _renameFolderCase(missingDir, newDir, mirrorByPath);
          return true;
        }
      }
    }
    return false;
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
            await _applyMove(filePath, missing, root, mirrorByPath, hs);
            pushed++;
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
    var unknownSize = false;
    for (final f in unhashedNewFiles) {
      try {
        unhashedSizes.add((await File(f).stat()).size);
      } catch (_) {
        unknownSize = true;
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

  Future<void> _applyMove(
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

    // Ask the server what this file's parent/name actually are right now,
    // instead of trusting this scan's own before/after path comparison — a
    // previous attempt at this exact move may have partially landed
    // (moveFile succeeded, then renameFile or reportChange threw) and this
    // call is that retry. Skipping whichever half already landed is what
    // keeps a retry idempotent instead of redoing (or double-reporting)
    // work that already happened (PR #12 review, F2).
    final current = await _fileRepository.getFile(missing.serverId);

    if (current.parentId != resolution.parentId) {
      await _fileRepository.moveFile(missing.serverId, resolution.parentId);
      await _push.reportChange(missing.serverId, SyncChangeType.move);
    }

    final newName = p.basename(newPath);
    if (current.name != newName) {
      await _fileRepository.renameFile(missing.serverId, newName);
      await _push.reportChange(missing.serverId, SyncChangeType.rename);
    }

    final updated = _mirrorRow(
      serverId: missing.serverId,
      localPath: newPath,
      isFolder: false,
      sizeBytes: hashSize.size,
      contentHash: hashSize.hash,
      updatedAt: missing.updatedAt,
    );
    await _mirror.upsert(updated);
    mirrorByPath.remove(missing.localPath);
    mirrorByPath[newPath] = updated;
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
        await _uploadNewFile(filePath, root, mirrorByPath, hashes[filePath]!);
        pushed++;
      } catch (e, st) {
        _recordFailure(filePath, e, st);
      }
    }
    return pushed;
  }

  Future<void> _uploadNewFile(
    String filePath,
    String root,
    Map<String, SyncMirrorEntry> mirrorByPath,
    ({String hash, int size}) hashSize,
  ) async {
    final resolution = _resolveParent(filePath, root, mirrorByPath);
    if (!resolution.resolved) return; // parent folder failed earlier this scan

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
      // Report before the mirror commit (PR #12 review, F6): if
      // reportChange throws, no mirror row is written for this file, so
      // the next scan still sees it as "new" and retries the whole upload
      // — which then 409s into the existing-file branch below and uploads
      // a duplicate version, harmless since the file is already there
      // either way. The same ordering is used by every write path below.
      await _push.reportChange(id, SyncChangeType.create);
      final entry = _mirrorRow(
        serverId: id,
        localPath: filePath,
        isFolder: false,
        sizeBytes: hashSize.size,
        contentHash: hashSize.hash,
        updatedAt: DateTime.now(),
      );
      await _mirror.upsert(entry);
      mirrorByPath[filePath] = entry;
    } on DioException catch (e) {
      if (e.response?.statusCode != 409) rethrow;
      // Last write wins: a file with this name already exists server-side
      // in this folder (created on another device, not yet pulled here) —
      // upload into it as a new version instead of failing.
      final existing = await _findExistingFileByName(resolution.parentId, name);
      if (existing == null) rethrow;
      await _fileRepository.uploadNewVersion(existing.id, name, file.openRead(), hashSize.size);
      await _push.reportChange(existing.id, SyncChangeType.update);
      final entry = _mirrorRow(
        serverId: existing.id,
        localPath: filePath,
        isFolder: false,
        sizeBytes: hashSize.size,
        contentHash: hashSize.hash,
        updatedAt: DateTime.now(),
      );
      await _mirror.upsert(entry);
      mirrorByPath[filePath] = entry;
    }
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
      await _push.reportChange(entry.serverId, SyncChangeType.update);
      final updated = _mirrorRow(
        serverId: entry.serverId,
        localPath: entry.localPath,
        isFolder: false,
        sizeBytes: bytes.length,
        contentHash: hash,
        updatedAt: DateTime.now(),
      );
      await _mirror.upsert(updated);
      mirrorByPath[entry.localPath] = updated;
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      // Last write wins: the file was deleted server-side (e.g. by another
      // device) while this one still had it. Re-create it as a new file
      // under the same local parent rather than losing the local edit.
      final resolution = _resolveParent(entry.localPath, root, mirrorByPath);
      final newId = await _fileRepository.uploadFile(
        resolution.resolved ? resolution.parentId : null,
        p.basename(entry.localPath),
        file.openRead(),
        bytes.length,
        null,
      );
      await _push.reportChange(newId, SyncChangeType.create);
      await _mirror.deleteByServerId(entry.serverId);
      final created = _mirrorRow(
        serverId: newId,
        localPath: entry.localPath,
        isFolder: false,
        sizeBytes: bytes.length,
        contentHash: hash,
        updatedAt: DateTime.now(),
      );
      await _mirror.upsert(created);
      mirrorByPath[entry.localPath] = created;
      return true;
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
        await _deleteMissingFolder(dir);
        pushed++;
      } catch (e, st) {
        _recordFailure(dir.localPath, e, st);
      }
    }

    return pushed;
  }

  /// Returns whether a delete was actually reported — used only so the
  /// delete step can count it toward [scanOnce]'s returned total. A report
  /// happens either way (PR #12 review, F6): even on a 404 (already gone
  /// server-side too) it is still sent, because another device may not
  /// have learned about the delete yet if its own delete event never fired.
  Future<bool> _deleteMissingFile(SyncMirrorEntry entry) async {
    try {
      await _fileRepository.deleteFile(entry.serverId);
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      await _push.reportChange(entry.serverId, SyncChangeType.delete);
      await _mirror.deleteByServerId(entry.serverId);
      return false;
    }
    // Report before the mirror commit (F6): if reportChange throws, the
    // mirror row is left in place, so the next scan finds the file
    // "missing" again and retries — deleteFile then 404s into the branch
    // above, which still reports, so the event is never lost either way.
    await _push.reportChange(entry.serverId, SyncChangeType.delete);
    await _mirror.deleteByServerId(entry.serverId);
    return true;
  }

  Future<void> _deleteMissingFolder(SyncMirrorEntry dir) async {
    await _fileRepository.deleteFile(dir.serverId); // FileService trashes the whole subtree
    // Read before removing anything so this still sees every mirror row
    // that lived under this folder.
    final children = await _mirror.getChildrenUnder(dir.localPath);
    // Report before the mirror commit (F6), same reasoning as
    // _deleteMissingFile above.
    await _push.reportChange(dir.serverId, SyncChangeType.delete);
    await _mirror.deleteByServerId(dir.serverId);
    for (final child in children) {
      await _mirror.deleteByServerId(child.serverId);
    }
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

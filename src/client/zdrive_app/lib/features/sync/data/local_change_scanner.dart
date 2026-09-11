import 'dart:developer';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
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

  LocalChangeScanner(
    this._mirror,
    this._fileRepository,
    this._push, {
    // Test seam only — GetIt has no `bool` to inject, so the generator must
    // leave this param out of the generated factory call; the default below
    // then reads the real platform.
    @ignoreParam bool? isWindows,
  }) : _isWindows = isWindows ?? Platform.isWindows;

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

  /// Diffs [syncFolderPath] against the mirror and pushes whatever differs.
  /// Returns how many local changes were reported to the server (folder
  /// creation alone is not counted — it never calls [PushSyncService], see
  /// the class doc comment on [_bootstrapFolder]-style resolution below: a
  /// pulling device fetches a file's parent folder directly by id rather
  /// than replaying a folder-create event, so pushing one would be dead
  /// weight).
  Future<int> scanOnce(String syncFolderPath) async {
    final root = syncFolderPath;
    var pushed = 0;

    final mirrorEntries = await _mirror.getChildrenUnder(root);
    final mirrorByPath = <String, SyncMirrorEntry>{
      for (final e in mirrorEntries) e.localPath: e,
    };

    final diskDirs = <String>{};
    final diskFiles = <String>{};
    await for (final entity in Directory(root).list(recursive: true, followLinks: false)) {
      if (entity is Link) continue; // never followed, never reported
      if (!_isSyncablePath(root, entity.path)) continue;
      if (entity is Directory) {
        diskDirs.add(entity.path);
      } else if (entity is File) {
        diskFiles.add(entity.path);
      }
    }

    final mirrorFileEntries = mirrorEntries.where((e) => !e.isFolder).toList();
    final mirrorDirEntries = mirrorEntries.where((e) => e.isFolder).toList();
    final mirrorFilePaths = mirrorFileEntries.map((e) => e.localPath).toSet();
    final mirrorDirPaths = mirrorDirEntries.map((e) => e.localPath).toSet();

    // Shallowest first so a parent folder always exists in the mirror
    // before a child under it is processed (path length is a sufficient
    // depth ordering — same trick PullSyncService's folder delete uses).
    final newDirs = diskDirs.where((d) => !mirrorDirPaths.contains(d)).toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    final newFiles = diskFiles.where((f) => !mirrorFilePaths.contains(f)).toList();
    final changeCandidates = mirrorFileEntries.where((e) => diskFiles.contains(e.localPath)).toList();
    // A path that flipped type (file <-> folder on disk since it was last
    // synced) falls out of both the file-present and dir-present checks
    // above for its old kind and into the new-dir/new-file checks for its
    // new kind — "missing" and "new" at once, exactly as the brief asks.
    var missingFiles = mirrorFileEntries.where((e) => !diskFiles.contains(e.localPath)).toList();
    final missingDirEntries = mirrorDirEntries.where((e) => !diskDirs.contains(e.localPath)).toList();

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

    // --- 1. Create folders ---
    for (final dir in newDirs) {
      await _createFolder(dir, root, mirrorByPath);
    }

    // --- 2. Moves/renames by content hash ---
    // Every new file's hash is needed for matching regardless of whether it
    // turns out to be a move, so this runs once up front and the result is
    // reused by the upload step below for whichever files aren't moves.
    final hashes = await _hashFiles(newFiles.where((f) => !_isBackedOff(f)));
    final remainingNewFiles = <String>[];
    for (final filePath in hashes.keys) {
      final hs = hashes[filePath]!;
      // Empty files all hash the same — matching on that would pair up
      // unrelated empty files instead of detecting a real rename/move.
      if (hs.size > 0) {
        final candidates = missingFiles
            .where((m) => m.contentHash == hs.hash && m.sizeBytes == hs.size)
            .toList();
        if (candidates.length == 1) {
          final missing = candidates.single;
          try {
            await _applyMove(filePath, missing, root, mirrorByPath, hs);
            missingFiles.remove(missing);
            pushed++;
          } catch (e, st) {
            _recordFailure(filePath, e, st);
          }
          continue;
        }
      }
      remainingNewFiles.add(filePath);
    }

    // --- 3. Upload new files ---
    for (final filePath in remainingNewFiles) {
      try {
        await _uploadNewFile(filePath, root, mirrorByPath, hashes[filePath]!);
        pushed++;
      } catch (e, st) {
        _recordFailure(filePath, e, st);
      }
    }

    // --- 4. Upload changed files ---
    for (final entry in changeCandidates) {
      try {
        if (await _uploadChangedFile(entry, root, mirrorByPath)) pushed++;
      } catch (e, st) {
        _recordFailure(entry.localPath, e, st);
      }
    }

    // --- 5. Delete missing files ---
    // A missing file that lives under a folder step 6 is about to delete is
    // left for step 6 instead: FileService's deleteFile on the folder
    // already trashes the whole subtree, so deleting the file here too
    // would be a redundant server call and a redundant push event — one
    // folder-delete event is enough for another device to reconcile the
    // whole subtree (see PullSyncService's own folder-delete, which walks
    // tracked children locally from a single event the same way).
    final missingFilesToDelete = missingFiles
        .where((e) => !topMostMissingDirs.any((d) => p.isWithin(d.localPath, e.localPath)))
        .toList();
    for (final entry in missingFilesToDelete) {
      try {
        if (await _deleteMissingFile(entry)) pushed++;
      } catch (e, st) {
        _recordFailure(entry.localPath, e, st);
      }
    }

    // --- 6. Delete missing folders (top-most only) ---
    for (final dir in topMostMissingDirs) {
      try {
        await _deleteMissingFolder(dir);
        pushed++;
      } catch (e, st) {
        _recordFailure(dir.localPath, e, st);
      }
    }

    return pushed;
  }

  /// True if every segment of [entityPath] below [root] is safe to sync —
  /// the same rule pull enforces on a server-supplied name (isSyncableName),
  /// applied here to a local one so a name pull would refuse to create
  /// remotely is never even offered to push in the first place.
  bool _isSyncablePath(String root, String entityPath) {
    for (final segment in p.split(p.relative(entityPath, from: root))) {
      if (!isSyncableName(segment, isWindows: _isWindows)) return false;
      if (osMetadataFileNames.contains(segment)) return false;
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
      final entry = SyncMirrorEntry(
        serverId: folder.id,
        localPath: dirPath,
        isFolder: true,
        updatedAt: folder.updatedAt,
        syncedAt: DateTime.now(),
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

  Future<void> _applyMove(
    String newPath,
    SyncMirrorEntry missing,
    String root,
    Map<String, SyncMirrorEntry> mirrorByPath,
    ({String hash, int size}) hashSize,
  ) async {
    final newParentPath = p.dirname(newPath);
    final oldParentPath = p.dirname(missing.localPath);
    if (newParentPath != oldParentPath) {
      final resolution = _resolveParent(newPath, root, mirrorByPath);
      if (!resolution.resolved) {
        throw StateError('destination folder not resolved this scan: $newParentPath');
      }
      await _fileRepository.moveFile(missing.serverId, resolution.parentId);
      await _push.reportChange(missing.serverId, SyncChangeType.move);
    }

    final newName = p.basename(newPath);
    final oldName = p.basename(missing.localPath);
    if (newName != oldName) {
      await _fileRepository.renameFile(missing.serverId, newName);
      await _push.reportChange(missing.serverId, SyncChangeType.rename);
    }

    final updated = SyncMirrorEntry(
      serverId: missing.serverId,
      localPath: newPath,
      isFolder: false,
      sizeBytes: hashSize.size,
      contentHash: hashSize.hash,
      updatedAt: missing.updatedAt,
      syncedAt: DateTime.now(),
    );
    await _mirror.upsert(updated);
    mirrorByPath.remove(missing.localPath);
    mirrorByPath[newPath] = updated;
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
      final entry = SyncMirrorEntry(
        serverId: id,
        localPath: filePath,
        isFolder: false,
        sizeBytes: hashSize.size,
        contentHash: hashSize.hash,
        updatedAt: DateTime.now(),
        syncedAt: DateTime.now(),
      );
      await _mirror.upsert(entry);
      mirrorByPath[filePath] = entry;
      await _push.reportChange(id, SyncChangeType.create);
    } on DioException catch (e) {
      if (e.response?.statusCode != 409) rethrow;
      // Last write wins: a file with this name already exists server-side
      // in this folder (created on another device, not yet pulled here) —
      // upload into it as a new version instead of failing.
      final existing = await _findExistingFileByName(resolution.parentId, name);
      if (existing == null) rethrow;
      await _fileRepository.uploadNewVersion(existing.id, name, file.openRead(), hashSize.size);
      final entry = SyncMirrorEntry(
        serverId: existing.id,
        localPath: filePath,
        isFolder: false,
        sizeBytes: hashSize.size,
        contentHash: hashSize.hash,
        updatedAt: DateTime.now(),
        syncedAt: DateTime.now(),
      );
      await _mirror.upsert(entry);
      mirrorByPath[filePath] = entry;
      await _push.reportChange(existing.id, SyncChangeType.update);
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
      final updated = SyncMirrorEntry(
        serverId: entry.serverId,
        localPath: entry.localPath,
        isFolder: false,
        sizeBytes: bytes.length,
        contentHash: hash,
        updatedAt: DateTime.now(),
        syncedAt: DateTime.now(),
      );
      await _mirror.upsert(updated);
      mirrorByPath[entry.localPath] = updated;
      await _push.reportChange(entry.serverId, SyncChangeType.update);
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
      await _mirror.deleteByServerId(entry.serverId);
      final created = SyncMirrorEntry(
        serverId: newId,
        localPath: entry.localPath,
        isFolder: false,
        sizeBytes: bytes.length,
        contentHash: hash,
        updatedAt: DateTime.now(),
        syncedAt: DateTime.now(),
      );
      await _mirror.upsert(created);
      mirrorByPath[entry.localPath] = created;
      await _push.reportChange(newId, SyncChangeType.create);
      return true;
    }
  }

  /// Returns whether a delete was actually reported — false when the file
  /// was already gone server-side too (404), since there is nothing new for
  /// another device to learn in that case.
  Future<bool> _deleteMissingFile(SyncMirrorEntry entry) async {
    try {
      await _fileRepository.deleteFile(entry.serverId);
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      await _mirror.deleteByServerId(entry.serverId);
      return false;
    }
    await _mirror.deleteByServerId(entry.serverId);
    await _push.reportChange(entry.serverId, SyncChangeType.delete);
    return true;
  }

  Future<void> _deleteMissingFolder(SyncMirrorEntry dir) async {
    await _fileRepository.deleteFile(dir.serverId); // FileService trashes the whole subtree
    // Read before removing anything so this still sees every mirror row
    // that lived under this folder.
    final children = await _mirror.getChildrenUnder(dir.localPath);
    await _mirror.deleteByServerId(dir.serverId);
    for (final child in children) {
      await _mirror.deleteByServerId(child.serverId);
    }
    await _push.reportChange(dir.serverId, SyncChangeType.delete);
  }
}

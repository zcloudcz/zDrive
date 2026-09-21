import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../files/domain/file_item.dart';
import '../../files/domain/file_repository.dart';
import '../domain/sync_mirror_entry.dart';
import '../domain/sync_mirror_repository.dart';
import '../domain/sync_progress.dart';
import 'device_registration_service.dart';
import 'file_hash.dart';
import 'sync_name_rules.dart';
import '../../../core/diagnostics/diagnostics.dart';

/// The one definition of "the same name" for sync: names are
/// case-insensitive end to end, so every comparison the scanner makes —
/// including [collidingKeys] — goes through this. Two copies of the rule
/// could drift apart and silently turn the collision check off (PR #14
/// review round 5).
String syncPathKey(String path) => p.normalize(path).toLowerCase();

/// The case-insensitive keys shared by two or more entries of [paths] — the
/// product rule that names are case-insensitive end to end means the server
/// (and every other device's disk) can represent only one entry per key, so
/// this is ambiguous input, not two distinct items. Only a case-sensitive
/// filesystem can produce it: `a.txt` and `A.txt` cannot coexist on NTFS or
/// default APFS. A free function, not a [LocalChangeScanner] method, so a
/// test can exercise the detection on every host without needing an actual
/// case-sensitive disk to create the collision on (PR #14 review round 4,
/// R4-4).
Set<String> collidingKeys(Iterable<String> paths) {
  final counts = <String, int>{};
  for (final path in paths) {
    final key = syncPathKey(path);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return {for (final entry in counts.entries) if (entry.value > 1) entry.key};
}

/// Finds local changes under the designated sync folder and pushes them to
/// FileService directly — the push half of sync. State-based, not
/// event-based: every call diffs the current disk contents against the
/// mirror ([SyncMirrorRepository], the same table [PullSyncService]
/// maintains), so there is no local change queue to lose — anything done
/// while offline is simply found by the next [scanOnce]. Every write this
/// scanner makes carries this device's id as `X-Device-Id` (see
/// [_originDeviceId]) so FileService's change feed excludes it from this
/// same device's own future pulls — a device never re-downloads a file it
/// just uploaded itself.
///
/// Conflicts are last-write-wins: a local edit is uploaded as the new
/// current version regardless of what else happened to the file server-side
/// (see [_uploadChangedFile]'s 404 handling and [_uploadNewFile]'s 409
/// handling for the two ways that surfaces).
///
/// Every server write below is committed to the mirror via
/// [SyncMirrorRepository.commit] — the mirror is correct the instant the
/// write lands, with no in-memory "still owed" state to lose on a crash or
/// restart. If the app dies between a server write completing and the
/// `commit` call that follows it, the mirror never learns the write
/// happened, so the next scan finds the same local change again and redoes
/// the write (landing as one extra version, or a second create that 409s
/// into an update) — at most once per restart.
@lazySingleton
class LocalChangeScanner {
  final SyncMirrorRepository _mirror;
  final FileRepository _fileRepository;
  final DeviceRegistrationService _deviceRegistration;

  // Same injected-platform pattern as PullSyncService: the scanner must skip
  // exactly what pull refuses to create (see isSyncableName), including its
  // Windows-only name rules, and tests need to exercise both branches
  // without depending on the host OS.
  final bool _isWindows;

  LocalChangeScanner(
    this._mirror,
    this._fileRepository,
    this._deviceRegistration, {
    // Test seam only — GetIt has no `bool` to inject, so the generator must
    // leave this param out of the generated factory call; the default below
    // then reads the real platform.
    @ignoreParam bool? isWindows,
  }) : _isWindows = isWindows ?? Platform.isWindows;

  /// A local path that failed during the last [scanOnce] that touched it,
  /// and when — keyed by [_key], the same case-insensitive normalization
  /// [_classify] uses, so a retry on the exact same item is recognised
  /// regardless of which case its name is spelled with this time. Kept only
  /// in memory — an app restart clears it and retries immediately, which is
  /// an accepted limit (see [_isBackedOff]) rather than a persisted retry
  /// queue nobody asked for.
  final Map<String, DateTime> _failedPaths = {};

  /// How long a just-failed path is left alone before being retried again —
  /// same rationale and duration as PullSyncService's quarantine backoff: a
  /// path that fails the exact same way every poll must not be retried on
  /// every single scan forever.
  static const _retryBackoff = Duration(minutes: 5);

  /// Case-insensitive normalized form of a local path — product rule: file
  /// names are case-insensitive end to end (FileService already rejects
  /// case-only sibling duplicates), so this is the key everything in this
  /// class diffs and backs off by. Two paths that normalize to the same key
  /// are the same item, whatever case either happens to be spelled in.
  String _key(String path) => syncPathKey(path);

  bool _isBackedOff(String path) {
    final failedAt = _failedPaths[_key(path)];
    return failedAt != null && DateTime.now().difference(failedAt) < _retryBackoff;
  }

  // A zone keeps callbacks scoped to this run, including its async workers.
  static final _progressZoneKey = Object();

  void _reportPendingFailure(String path) {
    final progress = Zone.current[_progressZoneKey] as SyncProgressTracker?;
    if (progress == null) return;
    if (!progress.snapshot.activeFiles.any((file) => file.key == path)) {
      progress.setTotalFiles(progress.snapshot.totalFiles + 1);
      progress.startFile(path, path);
    }
    progress.finishFile(path, failed: true);
  }

  void _recordFailure(String path, Object error, StackTrace stackTrace) {
    Diagnostics.error('sync.scan.file_failed', error, stackTrace);
    log('scan failed for $path', error: error, stackTrace: stackTrace, name: 'LocalChangeScanner');
    _failedPaths[_key(path)] = DateTime.now();
    _reportPendingFailure(path);
  }

  /// Clears every path's backoff — called by [SyncCoordinator.startSession]
  /// when this machine's synced state is being handed off to a different
  /// account: a path that failed for the previous owner (and is still
  /// within [_retryBackoff]) must not delay the new owner's first scan of
  /// that same path, which — from the new account's perspective — has
  /// never even been attempted yet (PR #16 review round 2, finding 8).
  void resetBackoff() => _failedPaths.clear();

  /// Test-only alias for [resetBackoff] (PR #12 review, F2 test b) — kept
  /// under its own name since every call site reads as "force a retry
  /// right now", not "a new owner took over this machine".
  @visibleForTesting
  void debugClearBackoff() => resetBackoff();

  /// Test-only seam for simulating a new file this scan could not hash (a
  /// locked file, antivirus holding it open) without depending on
  /// OS-specific file-locking behaviour (PR #12 review, F2 test c).
  @visibleForTesting
  void debugBackOff(String path) => _failedPaths[_key(path)] = DateTime.now();

  /// Paths this test run is forcing to behave as if `File.stat()` reported
  /// "size unknown" (type == notFound, size == -1) in the unhashed-new-file
  /// check inside [_applyMoves] — the real trigger (PR #14 review round 2,
  /// finding 6) needs a file to vanish or become unreadable in the narrow
  /// window between the disk walk and that later stat call, which a
  /// portable test cannot reliably race. Same rationale as [debugBackOff].
  final Set<String> _forcedUnknownSizePaths = {};

  @visibleForTesting
  void debugForceUnknownSize(String path) => _forcedUnknownSizePaths.add(path);

  /// Extra file paths added to this scan's disk walk result as if they had
  /// actually been found there — the only portable way to exercise the R4-4
  /// case-collision skip (see [collidingKeys]) in a test, since a genuinely
  /// colliding pair (e.g. `a.txt` and `A.txt` coexisting) needs a
  /// case-sensitive host filesystem this machine may not have. Same
  /// rationale as [debugBackOff]/[debugForceUnknownSize]: a test adds one
  /// real file plus one injected path here, and [_classify] runs
  /// [collidingKeys] over the combined set exactly as it would on a real
  /// case-sensitive walk (PR #14 review round 4, R4-4).
  final Set<String> _extraDiskFiles = {};

  @visibleForTesting
  void debugInjectExtraDiskFile(String path) => _extraDiskFiles.add(path);

  /// This device's id, tagged onto every FileService write this scanner
  /// makes (as `X-Device-Id`, via [FileRepository]'s `originDeviceId`
  /// parameter) so the change-feed row that write produces is excluded from
  /// this same device's own future pulls (see
  /// `FileRemoteDataSource.getChanges`'s doc comment) — otherwise a device
  /// would pull back and re-apply the very change it just made itself. Uses
  /// [DeviceRegistrationService.localDeviceId] (PR #14 review round 4), not
  /// [DeviceRegistrationService.ensureRegistered] — a local write must work
  /// offline, and the id is purely local, so no network call belongs here. A
  /// `null` id (no device registered yet) means the write is sent untagged,
  /// which is only a first-run edge case: pull has always registered the
  /// device before a scan runs.
  Future<String?> _originDeviceId() => _deviceRegistration.localDeviceId();

  /// Diffs [syncFolderPath] against the mirror and pushes whatever differs.
  /// Reads as the ordered list of steps below — each step's own doc comment
  /// explains why that order matters. Returns how many local changes were
  /// committed this scan (folder creation alone is not counted — a pulling
  /// device fetches a file's parent folder directly by id rather than
  /// reading it off the change feed, so counting one here would be
  /// meaningless).
  Future<int> scanOnce(String syncFolderPath, {SyncProgressTracker? progress}) => runZoned(
        () => _scanOnce(syncFolderPath, progress),
        zoneValues: {_progressZoneKey: progress},
      );

  Future<int> _scanOnce(String syncFolderPath, SyncProgressTracker? progress) async {
    progress?.beginPhase(SyncPhase.scanning, discovering: true);
    final root = syncFolderPath;
    for (final path in _failedPaths.keys.toList()) {
      if (p.isWithin(_key(root), path) && _isBackedOff(path)) _reportPendingFailure(path);
    }

    // Cloud-only rows are excluded up front: they have no file on disk by
    // design, so leaving them in would classify every one as "deleted
    // locally" and push a server-side delete — data loss. They also must not
    // be a rename/move target or parent lookup, since nothing exists there.
    final mirrorEntries = (await _mirror.getChildrenUnder(root)).where((e) => e.downloaded).toList();
    final mirrorByPath = <String, SyncMirrorEntry>{for (final e in mirrorEntries) e.localPath: e};
    final disk = await _walkDisk(root);
    final c = _classify(root, mirrorEntries, disk);

    // --- 0b. Case-only rename (decision 2) ---
    // Must run before anything below creates or deletes: on a match,
    // createFolder/uploadFile would just 409 on the server's own
    // case-insensitive name check, and the scanner has nothing else that
    // explains that 409. A *successful* rename ends the scan here (see
    // _applyCaseRenameIfAny's doc comment for why); a *failed* one does
    // not — _classify's key-based matching above already keeps the failed
    // candidate's whole subtree out of every new/missing list regardless
    // (round 3 residual B), so the rest of this scan is safe to run as
    // normal.
    final caseRenamePushed = await _applyCaseRenameIfAny(c.caseRenameDirs, c.caseRenameFiles, mirrorByPath);
    if (caseRenamePushed != null) return caseRenamePushed;

    var pushed = 0;

    // --- 1. Create folders ---
    for (final dir in c.newDirs) {
      await _createFolder(dir, root, mirrorByPath);
    }

    // --- 2. Moves/renames by content hash ---
    final moves = await _applyMoves(c.newFiles, c.missingFiles, root, mirrorByPath, progress);
    pushed += moves.pushed;

    final changedHashes = <String, ({String hash, int size})>{};
    progress?.beginPhase(SyncPhase.hashing, totalFiles: c.changeCandidates.length);
    for (final entry in c.changeCandidates) {
      final path = entry.localPath;
      progress?.startFile(path, path, totalBytes: entry.sizeBytes);
      try {
        final stat = await File(path).stat();
        if (entry.contentHash == null || entry.sizeBytes != stat.size || stat.modified.isAfter(entry.syncedAt)) {
          final checkedAt = DateTime.now().subtract(const Duration(seconds: 2));
          final hs = await hashFileInBackground(path);
          if (hs.hash != entry.contentHash) {
            changedHashes[path] = hs;
          } else {
            // Advance the check watermark so the precision overlap does not
            // force this unchanged file to be hashed on every future poll.
            final checked = _mirrorRow(
              serverId: entry.serverId,
              localPath: path,
              isFolder: false,
              sizeBytes: hs.size,
              contentHash: hs.hash,
              updatedAt: entry.updatedAt,
              syncedAt: checkedAt,
            );
            await _mirror.commit(upserts: [checked]);
            mirrorByPath[path] = checked;
          }
        }
        if (!changedHashes.containsKey(path)) _failedPaths.remove(_key(path));
        progress?.finishFile(path);
      } catch (e, st) {
        _recordFailure(path, e, st);
        progress?.finishFile(path, failed: true);
      }
    }
    final changedFiles = c.changeCandidates.where((e) => changedHashes.containsKey(e.localPath)).toList();
    progress?.beginPhase(
      SyncPhase.uploading,
      totalFiles: moves.remainingNewFiles.length + changedFiles.length,
    );

    // --- 3. Upload new files (whatever step 2 did not claim as a move) ---
    pushed += await _uploadNewFiles(moves.remainingNewFiles, root, mirrorByPath, progress);

    // --- 4. Upload changed files ---
    pushed += await _uploadChangedFiles(changedFiles, root, mirrorByPath, progress);

    // --- 5 & 6. Delete missing files, then missing folders (top-most only) ---
    pushed += await _deleteMissing(
      c.missingFiles,
      c.topMostMissingDirs,
      moves.protectedMissingFiles,
      progress,
    );

    return pushed;
  }

  /// Walks [root] once, collecting every syncable directory and file path —
  /// used as the "what is actually on disk right now" side of [_classify].
  Future<({Set<String> dirs, Set<String> files})> _walkDisk(String root) async {
    final dirs = <String>{};
    final files = <String>{..._extraDiskFiles}; // test seam, see debugInjectExtraDiskFile
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

  /// Diffs the mirror against [disk] into what each later step needs. Every
  /// comparison here is by [_key] (decision 2), not raw path equality: a
  /// disk entry and a mirror entry that normalize to the same key are the
  /// same item — never "missing" + "new" — regardless of whether their
  /// exact case matches. The ones whose case *doesn't* match come back
  /// separately as [caseRenameDirs]/[caseRenameFiles] rather than in
  /// new/missing at all; an item only in one of those two lists is
  /// specifically excluded from [changeCandidates] too (its disk path
  /// literally is not the tracked path, so there is nothing safe to stat
  /// there yet — that waits for the rename to land). Backed-off paths (see
  /// [_isBackedOff]) are filtered out of every list here so nothing
  /// downstream has to check it again.
  ({
    List<String> newDirs,
    List<String> newFiles,
    List<SyncMirrorEntry> changeCandidates,
    List<SyncMirrorEntry> missingFiles,
    List<SyncMirrorEntry> missingDirEntries,
    List<SyncMirrorEntry> topMostMissingDirs,
    List<({SyncMirrorEntry entry, String diskPath})> caseRenameDirs,
    List<({SyncMirrorEntry entry, String diskPath})> caseRenameFiles,
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

    // R4-4: two or more disk entries that fold to the same case-insensitive
    // key (`a.txt` and `A.txt`) are ambiguous — only a case-sensitive
    // filesystem can produce this (Windows and default macOS cannot), and
    // there is no locally-safe way to decide which one is "the" file at
    // that key. Every key this finds is excluded below from every list —
    // disk-side and mirror-side alike — so this scan does not touch any of
    // them or the mirror row at that key at all.
    final collidingFileKeys = collidingKeys(disk.files);
    final collidingDirKeys = collidingKeys(disk.dirs);
    for (final key in collidingFileKeys) {
      final paths = disk.files.where((f) => _key(f) == key).join(', ');
      log('case collision on disk, skipping this scan: $paths', name: 'LocalChangeScanner', level: 900);
    }
    for (final key in collidingDirKeys) {
      final paths = disk.dirs.where((d) => _key(d) == key).join(', ');
      log('case collision on disk, skipping this scan: $paths', name: 'LocalChangeScanner', level: 900);
    }

    final mirrorDirByKey = {
      for (final e in mirrorDirEntries)
        if (!collidingDirKeys.contains(_key(e.localPath))) _key(e.localPath): e,
    };
    final mirrorFileByKey = {
      for (final e in mirrorFileEntries)
        if (!collidingFileKeys.contains(_key(e.localPath))) _key(e.localPath): e,
    };
    final diskDirByKey = {
      for (final d in disk.dirs)
        if (!collidingDirKeys.contains(_key(d))) _key(d): d,
    };
    final diskFileByKey = {
      for (final f in disk.files)
        if (!collidingFileKeys.contains(_key(f))) _key(f): f,
    };

    // Shallowest first so a parent folder always exists in the mirror
    // before a child under it is processed (path length is a sufficient
    // depth ordering — same trick PullSyncService's folder delete uses).
    final newDirs = disk.dirs
        .where((d) => !collidingDirKeys.contains(_key(d)))
        .where((d) => !mirrorDirByKey.containsKey(_key(d)))
        .toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    final newFiles = disk.files
        .where((f) => !collidingFileKeys.contains(_key(f)))
        .where((f) => !mirrorFileByKey.containsKey(_key(f)))
        .toList();

    // Only the basename itself differing in case counts as a rename
    // candidate for *this* item — if some ancestor segment's case is what
    // actually differs (dirname mismatches too), that is a different, more
    // shallow folder's rename to make first; this item's own key already
    // matches once that lands, on a later scan. Without this check a file
    // under a case-mismatched folder would wrongly show up as its own
    // (no-op) rename candidate alongside the real one.
    final caseRenameDirs = <({SyncMirrorEntry entry, String diskPath})>[
      for (final e in mirrorDirEntries)
        if (diskDirByKey[_key(e.localPath)] case final diskPath?
            when diskPath != e.localPath && p.dirname(diskPath) == p.dirname(e.localPath))
          (entry: e, diskPath: diskPath),
    ]..sort((a, b) => a.entry.localPath.length.compareTo(b.entry.localPath.length));
    final caseRenameFiles = <({SyncMirrorEntry entry, String diskPath})>[
      for (final e in mirrorFileEntries)
        if (diskFileByKey[_key(e.localPath)] case final diskPath?
            when diskPath != e.localPath && p.dirname(diskPath) == p.dirname(e.localPath))
          (entry: e, diskPath: diskPath),
    ];

    final changeCandidates =
        mirrorFileEntries.where((e) => diskFileByKey[_key(e.localPath)] == e.localPath).toList();
    // A path that flipped type (file <-> folder on disk since it was last
    // synced) falls out of both the file-present and dir-present checks
    // above for its old kind and into the new-dir/new-file checks for its
    // new kind — "missing" and "new" at once.
    //
    // A mirror entry whose own key collides on disk is excluded here too
    // (R4-4, not just from diskFileByKey/diskDirByKey above): it is not
    // actually missing — it is one of the ambiguous disk entries — and
    // must not be deleted just because the collision hid it from the keyed
    // map.
    var missingFiles = mirrorFileEntries
        .where((e) => !collidingFileKeys.contains(_key(e.localPath)))
        .where((e) => !diskFileByKey.containsKey(_key(e.localPath)))
        .toList();
    final missingDirEntries = mirrorDirEntries
        .where((e) => !collidingDirKeys.contains(_key(e.localPath)))
        .where((e) => !diskDirByKey.containsKey(_key(e.localPath)))
        .toList();

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
      caseRenameDirs: caseRenameDirs,
      caseRenameFiles: caseRenameFiles,
    );
  }

  /// Applies at most one case-only rename this scan: folders first
  /// (shallowest first, so a parent's rename lands before a child's own
  /// candidacy is even evaluated on a later scan), then files. Returns the
  /// pushed count (always 1) and ends [scanOnce] early the moment one
  /// *succeeds* — simpler than re-validating the rest of this scan's
  /// already-stale disk snapshot against whatever the rename just changed,
  /// and cheap because the next scan recomputes everything fresh either
  /// way. A *failure* does not end the scan: nothing changed server- or
  /// disk-side, so [_classify]'s result (computed before this call) is
  /// still perfectly valid, and the backed-off key it leaves behind is what
  /// keeps this candidate's subtree safe for the rest of *this* scan too —
  /// not the early return (round 3 residual B: a scan that finds every
  /// candidate already backed off never even calls this loop's body, and
  /// still must not touch that subtree, which only [_classify]'s key
  /// matching can guarantee).
  Future<int?> _applyCaseRenameIfAny(
    List<({SyncMirrorEntry entry, String diskPath})> caseRenameDirs,
    List<({SyncMirrorEntry entry, String diskPath})> caseRenameFiles,
    Map<String, SyncMirrorEntry> mirrorByPath,
  ) async {
    for (final candidate in caseRenameDirs) {
      if (_isBackedOff(candidate.entry.localPath)) continue;
      try {
        await _renameFolderCase(candidate.entry, candidate.diskPath, mirrorByPath);
        _failedPaths.remove(_key(candidate.entry.localPath));
        return 1;
      } catch (e, st) {
        _recordFailure(candidate.entry.localPath, e, st);
      }
    }
    for (final candidate in caseRenameFiles) {
      if (_isBackedOff(candidate.entry.localPath)) continue;
      try {
        await _renameFileCase(candidate.entry, candidate.diskPath, mirrorByPath);
        _failedPaths.remove(_key(candidate.entry.localPath));
        return 1;
      } catch (e, st) {
        _recordFailure(candidate.entry.localPath, e, st);
      }
    }
    return null;
  }

  Future<void> _renameFolderCase(
    SyncMirrorEntry folder,
    String newPath,
    Map<String, SyncMirrorEntry> mirrorByPath,
  ) async {
    await _fileRepository.renameFile(
      folder.serverId,
      p.basename(newPath),
      originDeviceId: await _originDeviceId(),
    );
    final updated = _mirrorRow(
      serverId: folder.serverId,
      localPath: newPath,
      isFolder: true,
      updatedAt: folder.updatedAt,
    );
    await _mirror.commit(
      rePath: (from: folder.localPath, to: newPath),
      upserts: [updated],
    );
    mirrorByPath.remove(folder.localPath);
    mirrorByPath[newPath] = updated;
  }

  Future<void> _renameFileCase(
    SyncMirrorEntry file,
    String newPath,
    Map<String, SyncMirrorEntry> mirrorByPath,
  ) async {
    await _fileRepository.renameFile(
      file.serverId,
      p.basename(newPath),
      originDeviceId: await _originDeviceId(),
    );
    // A case-only rename changes localPath and nothing else — contentHash,
    // sizeBytes and syncedAt are carried over unchanged from the old row
    // (PR #14 review round 4, R4-2), not through _mirrorRow (which always
    // stamps syncedAt to now). An edit made to the file before the rename
    // was ever seen must still look like an edit to _uploadChangedFile's
    // change-detection pre-filter on the next scan; stamping syncedAt here
    // would tell that filter the file was just synced and silently drop
    // the edit.
    final updated = SyncMirrorEntry(
      serverId: file.serverId,
      localPath: newPath,
      isFolder: false,
      sizeBytes: file.sizeBytes,
      contentHash: file.contentHash,
      updatedAt: file.updatedAt,
      syncedAt: file.syncedAt,
    );
    await _mirror.commit(upserts: [updated]);
    mirrorByPath.remove(file.localPath);
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
      final folder = await _fileRepository.createFolder(
        resolution.parentId,
        p.basename(dirPath),
        originDeviceId: await _originDeviceId(),
      );
      final entry = _mirrorRow(
        serverId: folder.id,
        localPath: dirPath,
        isFolder: true,
        updatedAt: folder.updatedAt,
      );
      // Not reported (see scanOnce's doc comment) — a plain upsert, not
      // commit, is enough.
      await _mirror.upsert(entry);
      _failedPaths.remove(_key(dirPath));
      mirrorByPath[dirPath] = entry; // so a child under it resolves within this same scan
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        // Exists server-side already but this device has not pulled it yet
        // (e.g. created on another device). Adopted straight into the
        // mirror by name instead of waiting for the next pull — so children
        // under it can still be uploaded into it this same scan (the
        // resolveParent lookup above needs a mirror row to find).
        final existing =
            await _findExistingByName(resolution.parentId, p.basename(dirPath), isFolder: true);
        if (existing != null) {
          final entry = _mirrorRow(
            serverId: existing.id,
            localPath: dirPath,
            isFolder: true,
            updatedAt: existing.updatedAt,
          );
          await _mirror.upsert(entry);
          _failedPaths.remove(_key(dirPath));
          mirrorByPath[dirPath] = entry;
          return;
        }
        log('folder already exists server-side, waiting for pull: $dirPath', name: 'LocalChangeScanner');
        return;
      }
      _recordFailure(dirPath, e, StackTrace.current);
    } catch (e, st) {
      _recordFailure(dirPath, e, st);
    }
  }

  Future<Map<String, ({String hash, int size})>> _hashFiles(
    List<String> paths,
    SyncProgressTracker? progress,
  ) async {
    progress?.beginPhase(SyncPhase.hashing, totalFiles: paths.length);
    final result = <String, ({String hash, int size})>{};
    for (final path in paths) {
      progress?.startFile(path, path);
      try {
        result[path] = await hashFileInBackground(path);
        progress?.finishFile(path);
      } catch (e, st) {
        _recordFailure(path, e, st);
        progress?.finishFile(path, failed: true);
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
    SyncProgressTracker? progress,
  ) async {
    // Every new file's hash is needed for matching regardless of whether it
    // turns out to be a move, so this runs once up front and the result is
    // reused by the upload step below for whichever files aren't moves.
    final hashes = await _hashFiles(newFiles.where((f) => !_isBackedOff(f)).toList(), progress);
    final protectedMissingFiles = <SyncMirrorEntry>{};
    final remainingNewFiles = <String>[];
    var pushed = 0;

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
          // Claimed either way: a failed move may still have partially
          // landed server-side, so this entry must not be treated as an
          // ordinary "missing" file by the delete step later in this scan.
          missingFiles.remove(missing);
          try {
            if (await _applyMove(filePath, missing, root, mirrorByPath, hs)) pushed++;
            _failedPaths.remove(_key(filePath));
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
  /// [_applyMoves]. Returns whether this call committed something — false
  /// covers only "[missing] turned out not to be a move at all" (finding 5
  /// — a 404 from getFile means the server node is simply gone); every
  /// other path through here ends in a [SyncMirrorRepository.commit] call,
  /// so it always returns true.
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

    // What the local diff itself says happened — used to decide *whether to
    // call the server at all*. getFile below decides whether that call is
    // still needed: a previous attempt at this exact move may have
    // partially landed (moveFile succeeded, then renameFile threw, or the
    // app restarted before this call ever ran) and this call is that retry,
    // so only whatever getFile shows as not-yet-applied is actually sent.
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

    final originDeviceId = await _originDeviceId();

    if (movedParent && current.parentId != resolution.parentId) {
      await _fileRepository.moveFile(missing.serverId, resolution.parentId, originDeviceId: originDeviceId);
    }

    final newName = p.basename(newPath);
    if (renamedName && current.name != newName) {
      await _fileRepository.renameFile(missing.serverId, newName, originDeviceId: originDeviceId);
    }

    final updated = _mirrorRow(
      serverId: missing.serverId,
      localPath: newPath,
      isFolder: false,
      sizeBytes: hashSize.size,
      contentHash: hashSize.hash,
      updatedAt: missing.updatedAt,
    );
    await _mirror.commit(upserts: [updated]);
    mirrorByPath.remove(missing.localPath);
    mirrorByPath[newPath] = updated;
    return true;
  }

  // Each worker claims one item synchronously before awaiting. Future.wait
  // drains every worker even if one fails, before the delete phase can start.
  // At most three snapshots are active; cleanup is attempted after each upload.
  Future<int> _uploadInParallel<T>(
    List<T> items,
    String Function(T) pathOf,
    Future<bool> Function(T, File, ({String hash, int size}), DateTime, CancelToken) upload,
    String root,
    Map<String, SyncMirrorEntry> mirrorByPath,
    SyncProgressTracker? progress,
  ) async {
    var next = 0;
    var pushed = 0;
    Future<void> worker() async {
      while (next < items.length) {
        final item = items[next++];
        final path = pathOf(item);
        progress?.startFile(path, path);
        Diagnostics.event('sync.upload.start');
        Directory? staging;
        final cancellation = CancelToken();
        var checking = false;
        Future<void> checkDeleted() async {
          if (checking || cancellation.isCancelled) return;
          checking = true;
          try {
            // An unavailable sync drive is not a request to delete its cloud copy.
            if (await Directory(root).exists() && !await File(path).exists()) {
              cancellation.cancel('Local file removed during upload');
              Diagnostics.event('sync.upload.local_deleted');
            }
          } on FileSystemException {
            // Let normal filesystem handling report access errors.
          } finally {
            checking = false;
          }
        }
        StreamSubscription<FileSystemEvent>? watcher;
        try {
          watcher = Directory(root).watch(recursive: true).listen((event) {
            final changed = _key(event.path);
            if (changed == _key(path) || p.isWithin(changed, _key(path))) {
              unawaited(checkDeleted());
            }
          }, onError: (Object _) {});
        } on FileSystemException {
          // Polling below also supports filesystems without native watchers.
        }
        final timer = Timer.periodic(const Duration(milliseconds: 500), (_) => unawaited(checkDeleted()));
        Future<void> deleteRemovedUpload() async {
          if (!await Directory(root).exists() || await File(path).exists()) return;
          final entry = mirrorByPath[path];
          if (entry != null) {
            await _deleteMissingEntry(entry);
            mirrorByPath.remove(path);
            pushed++;
          }
        }
        try {
          staging = await Directory.systemTemp.createTemp('zdrive_sync_upload_');
          // Filesystems may round mtimes to two-second boundaries. Keeping
          // this small overlap makes edits within that boundary re-hash too.
          final snapshotStartedAt = DateTime.now().subtract(const Duration(seconds: 2));
          final snapshot = await File(path).copy(p.join(staging.path, 'content'));
          Diagnostics.event('sync.upload.snapshot_ready');
          await checkDeleted();
          if (cancellation.isCancelled) throw cancellation.cancelError!;
          final hashSize = await hashFileInBackground(snapshot.path);
          Diagnostics.event('sync.upload.hashed', {'sizeBytes': hashSize.size});
          // Hash and every retry read the same private snapshot. The live
          // file can continue changing without corrupting the mirror hash.
          await checkDeleted();
          if (cancellation.isCancelled) throw cancellation.cancelError!;
          final uploaded = await upload(item, snapshot, hashSize, snapshotStartedAt, cancellation);
          if (uploaded) {
            pushed++;
            _failedPaths.remove(_key(path));
          }
          await deleteRemovedUpload();
          Diagnostics.event('sync.upload.complete', {'uploaded': uploaded});
          progress?.finishFile(path, failed: !uploaded);
        } catch (e, st) {
          await checkDeleted();
          if (cancellation.isCancelled && await Directory(root).exists() && !await File(path).exists()) {
            try {
              await deleteRemovedUpload();
              Diagnostics.event('sync.upload.cancelled_cleaned');
              _failedPaths.remove(_key(path));
              progress?.finishFile(path);
            } catch (cleanupError, cleanupStack) {
              _recordFailure(path, cleanupError, cleanupStack);
              progress?.finishFile(path, failed: true);
            }
          } else {
            _recordFailure(path, e, st);
            progress?.finishFile(path, failed: true);
          }
        } finally {
          timer.cancel();
          await watcher?.cancel();
          if (staging != null) {
            try {
              await staging.delete(recursive: true);
            } on FileSystemException catch (e, st) {
              log('Could not remove upload snapshot',
                  error: e, stackTrace: st, name: 'LocalChangeScanner');
            }
          }
        }
      }
    }

    await Future.wait(List.generate(items.length < 3 ? items.length : 3, (_) => worker()));
    return pushed;
  }

  void Function(double)? _uploadProgress(SyncProgressTracker? progress, String path, int size) =>
      progress == null
      ? null
      : (fraction) => progress.updateFile(path, (fraction * size).round(), totalBytes: size);

  Future<int> _uploadNewFiles(
    List<String> remainingNewFiles,
    String root,
    Map<String, SyncMirrorEntry> mirrorByPath,
    SyncProgressTracker? progress,
  ) => _uploadInParallel(
    remainingNewFiles,
    (path) => path,
    (path, snapshot, hashSize, startedAt, cancellation) =>
        _uploadNewFile(path, root, mirrorByPath, snapshot, hashSize, startedAt, progress, cancellation),
    root,
    mirrorByPath,
    progress,
  );

  /// Returns whether this call resolved its parent and completed the
  /// upload — used only so the caller can count it toward [scanOnce]'s
  /// pushed total.
  Future<bool> _uploadNewFile(
    String filePath,
    String root,
    Map<String, SyncMirrorEntry> mirrorByPath,
    File file,
    ({String hash, int size}) hashSize,
    DateTime snapshotStartedAt,
    SyncProgressTracker? progress,
    CancelToken cancellation,
  ) async {
    final resolution = _resolveParent(filePath, root, mirrorByPath);
    if (!resolution.resolved) return false; // parent folder failed earlier this scan

    final name = p.basename(filePath);
    final originDeviceId = await _originDeviceId();

    try {
      final id = await _fileRepository.uploadFile(
        resolution.parentId,
        name,
        file.openRead(),
        hashSize.size,
        _uploadProgress(progress, filePath, hashSize.size),
        originDeviceId: originDeviceId,
        cancelToken: cancellation,
        onNodeCreated: (id) => _trackUpload(id, filePath, mirrorByPath),
      );
      await _finishUpload(id, filePath, hashSize, mirrorByPath, snapshotStartedAt);
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode != 409) rethrow;
      // Last write wins: a file with this name already exists server-side
      // in this folder (created on another device, not yet pulled here) —
      // upload into it as a new version instead of failing.
      final existing = await _findExistingByName(resolution.parentId, name, isFolder: false);
      if (existing == null) rethrow;
      await _trackUpload(existing.id, filePath, mirrorByPath);
      await _fileRepository.uploadNewVersion(
        existing.id,
        name,
        file.openRead(),
        hashSize.size,
        onProgress: _uploadProgress(progress, filePath, hashSize.size),
        originDeviceId: originDeviceId,
        cancelToken: cancellation,
      );
      await _finishUpload(existing.id, filePath, hashSize, mirrorByPath, snapshotStartedAt);
      return true;
    }
  }

  /// Shared tail of every "server write is done, now commit the mirror"
  /// path: builds the mirror row and commits it, so a scan that dies right
  /// after the write either leaves both the server write and the mirror row
  /// in place, or neither (see this class's own doc comment for the one
  /// exception).
  // Persist ownership before sending content. A null hash marks an unfinished
  // upload, so restart retries it even when size and mtime did not change.
  Future<void> _trackUpload(String id, String path, Map<String, SyncMirrorEntry> mirrorByPath) async {
    final entry = _mirrorRow(
      serverId: id, localPath: path, isFolder: false, updatedAt: DateTime.now(),
    );
    await _mirror.commit(upserts: [entry]);
    mirrorByPath[path] = entry;
  }

  Future<void> _finishUpload(
    String serverId,
    String filePath,
    ({String hash, int size}) hashSize,
    Map<String, SyncMirrorEntry> mirrorByPath,
    DateTime snapshotStartedAt,
  ) async {
    final entry = _mirrorRow(
      serverId: serverId,
      localPath: filePath,
      isFolder: false,
      sizeBytes: hashSize.size,
      contentHash: hashSize.hash,
      updatedAt: DateTime.now(),
      syncedAt: snapshotStartedAt,
    );
    await _mirror.commit(upserts: [entry]);
    mirrorByPath[filePath] = entry;
  }

  /// A non-folder child named [name] directly under [parentId], if one
  /// already exists — paginated, since a folder can hold more than one
  /// page. Mirrors FileRepositoryImpl._findExistingFile's shape.
  /// A child named [name] directly under [parentId] whose [FileItem.isFolder]
  /// matches [isFolder], if one already exists — used by [_createFolder]'s
  /// and the new-file upload path's 409 handling to adopt an item another
  /// device already created. Case-insensitive, like every other name
  /// comparison here: FileService rejects a sibling that differs only by
  /// case, so the 409 for `Photo.jpg` may be about an existing `photo.jpg`
  /// (and the same rule applies to folders). Paginated, since a folder can
  /// hold more than one page of children.
  Future<FileItem?> _findExistingByName(
    String? parentId,
    String name, {
    required bool isFolder,
  }) async {
    var page = 1;
    const pageSize = 200;
    while (true) {
      final result = await _fileRepository.listChildren(parentId, page: page, pageSize: pageSize);
      for (final item in result.items) {
        if (item.name.toLowerCase() == name.toLowerCase() && item.isFolder == isFolder) return item;
      }
      if (!result.hasMore) return null;
      page++;
    }
  }

  Future<int> _uploadChangedFiles(
    List<SyncMirrorEntry> changeCandidates,
    String root,
    Map<String, SyncMirrorEntry> mirrorByPath,
    SyncProgressTracker? progress,
  ) => _uploadInParallel(
    changeCandidates,
    (entry) => entry.localPath,
    (entry, snapshot, hashSize, startedAt, cancellation) =>
        _uploadChangedFile(entry, root, mirrorByPath, snapshot, hashSize, startedAt, progress, cancellation),
    root,
    mirrorByPath,
    progress,
  );

  /// Returns whether a change was actually committed — false for the
  /// common case (untouched file) so the caller does not count it toward
  /// [scanOnce]'s returned total.
  Future<bool> _uploadChangedFile(
    SyncMirrorEntry entry,
    String root,
    Map<String, SyncMirrorEntry> mirrorByPath,
    File file,
    ({String hash, int size}) hashSize,
    DateTime snapshotStartedAt,
    SyncProgressTracker? progress,
    CancelToken cancellation,
  ) async {
    final hash = hashSize.hash;
    final originDeviceId = await _originDeviceId();

    try {
      await _fileRepository.uploadNewVersion(
        entry.serverId,
        p.basename(entry.localPath),
        file.openRead(),
        hashSize.size,
        onProgress: _uploadProgress(progress, entry.localPath, hashSize.size),
        originDeviceId: originDeviceId,
        cancelToken: cancellation,
      );
      await _finishUpload(entry.serverId, entry.localPath, hashSize, mirrorByPath, snapshotStartedAt);
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      // Last write wins: the file was deleted server-side (e.g. by another
      // device) while this one still had it. Re-create it as a new file
      // under the same local parent rather than losing the local edit. The
      // old server record's delete and the new one's create commit
      // together in one transaction, so there is no window where the
      // mirror has neither row.
      final resolution = _resolveParent(entry.localPath, root, mirrorByPath);
      final newId = await _fileRepository.uploadFile(
        resolution.resolved ? resolution.parentId : null,
        p.basename(entry.localPath),
        file.openRead(),
        hashSize.size,
        _uploadProgress(progress, entry.localPath, hashSize.size),
        originDeviceId: originDeviceId,
        cancelToken: cancellation,
        onNodeCreated: (id) async {
          // Save the replacement before forgetting the deleted server node.
          await _trackUpload(id, entry.localPath, mirrorByPath);
          await _mirror.commit(deleteServerIds: [entry.serverId]);
        },
      );
      final newEntry = _mirrorRow(
        serverId: newId,
        localPath: entry.localPath,
        isFolder: false,
        sizeBytes: hashSize.size,
        contentHash: hash,
        updatedAt: DateTime.now(),
        syncedAt: snapshotStartedAt,
      );
      await _mirror.commit(deleteServerIds: [entry.serverId], upserts: [newEntry]);
      mirrorByPath[entry.localPath] = newEntry;
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
    SyncProgressTracker? progress,
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
    progress?.beginPhase(SyncPhase.deleting, totalFiles: missingFilesToDelete.length + dirsToDelete.length);
    for (final entry in missingFilesToDelete) {
      progress?.startFile(entry.localPath, entry.localPath);
      try {
        if (await _deleteMissingEntry(entry)) pushed++;
        progress?.finishFile(entry.localPath);
      } catch (e, st) {
        _recordFailure(entry.localPath, e, st);
        progress?.finishFile(entry.localPath, failed: true);
      }
    }

    for (final dir in dirsToDelete) {
      progress?.startFile(dir.localPath, dir.localPath);
      try {
        if (await _deleteMissingEntry(dir)) pushed++;
        progress?.finishFile(dir.localPath);
      } catch (e, st) {
        _recordFailure(dir.localPath, e, st);
        progress?.finishFile(dir.localPath, failed: true);
      }
    }

    return pushed;
  }

  /// Deletes [entry] server-side (for a folder, FileService trashes the
  /// whole subtree) and commits the matching mirror change — its own row,
  /// plus (for a folder) every row still tracked under it. Shared by the
  /// file and folder delete steps; the only difference between them is
  /// [SyncMirrorEntry.isFolder] deciding whether [SyncMirrorRepository
  /// .commit] also has to sweep children. Returns whether the file/folder
  /// was actually deleted server-side by this call — false on a 404, since
  /// another device (or an earlier, only-partially-completed attempt of
  /// this same call) already deleted it and this device did not cause
  /// anything new; the mirror is still cleared either way (PR #12 review,
  /// F6), since this device's own tracking of the item is stale regardless
  /// of who removed it.
  Future<bool> _deleteMissingEntry(SyncMirrorEntry entry) async {
    var actuallyDeleted = true;
    try {
      await _fileRepository.deleteFile(entry.serverId, originDeviceId: await _originDeviceId());
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      actuallyDeleted = false;
    }
    await _mirror.commit(
      deleteServerIds: [entry.serverId],
      deleteUnderPath: entry.isFolder ? entry.localPath : null,
    );
    _failedPaths.remove(_key(entry.localPath));
    if (entry.isFolder) {
      _failedPaths.removeWhere((path, _) => p.isWithin(_key(entry.localPath), path));
    }
    return actuallyDeleted;
  }

  /// Uploads use the snapshot start (with an mtime precision overlap), so
  /// edits during transfer remain candidates for the next scan. Other writes
  /// use the current time.
  SyncMirrorEntry _mirrorRow({
    required String serverId,
    required String localPath,
    required bool isFolder,
    int? sizeBytes,
    String? contentHash,
    required DateTime updatedAt,
    DateTime? syncedAt,
  }) =>
      SyncMirrorEntry(
        serverId: serverId,
        localPath: localPath,
        isFolder: isFolder,
        sizeBytes: sizeBytes,
        contentHash: contentHash,
        updatedAt: updatedAt,
        syncedAt: syncedAt ?? DateTime.now(),
      );
}

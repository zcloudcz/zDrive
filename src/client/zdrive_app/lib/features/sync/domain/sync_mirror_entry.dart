import 'package:equatable/equatable.dart';

/// One row of the local metadata mirror: what pull has already applied for
/// one remote file/folder, and where it landed on disk.
///
/// [contentHash] is the SHA-256 of the bytes pull wrote for this entry (null
/// for folders, which have no content). Pull itself now reads it to decide
/// whether a file at the target path is untracked or locally modified
/// (see PullSyncService's refuse-to-overwrite check) — and it still doubles
/// as what the file watcher the next task adds will use to tell "pull just
/// wrote this" apart from a genuine local edit.
///
/// [downloaded] is the cloud-only switch. `false` means the item is known
/// (metadata mirrored) but nothing was written to disk for it: [localPath] is
/// only where it *would* live, so children and renames can still be resolved
/// by path. A cloud-only file has a null [contentHash] — that is NOT the
/// "provisional upload" marker it is for a downloaded file, so always check
/// [downloaded] first. For a folder it means "no local directory created".
/// Rows written before cloud-only existed default to `true` (they were all
/// mirrored to disk), which is what keeps upgraded installs working.
class SyncMirrorEntry extends Equatable {
  final String serverId;
  final String localPath;
  final bool isFolder;
  final int? sizeBytes;
  final String? contentHash;
  final DateTime updatedAt;
  final DateTime syncedAt;
  final bool downloaded;

  const SyncMirrorEntry({
    required this.serverId,
    required this.localPath,
    required this.isFolder,
    this.sizeBytes,
    this.contentHash,
    required this.updatedAt,
    required this.syncedAt,
    this.downloaded = true,
  });

  @override
  List<Object?> get props =>
      [serverId, localPath, isFolder, sizeBytes, contentHash, updatedAt, syncedAt, downloaded];
}

/// What the file browser shows per item on desktop (OneDrive-style selective
/// sync). Derived from the mirror row plus pins, see
/// [SyncMirrorRepository.getOfflineStatuses].
enum OfflineStatus {
  /// Known to the mirror (or not even that) but nothing on disk.
  cloudOnly,

  /// Pinned (directly or through a folder) but not on disk yet: pending or
  /// the download failed.
  downloading,

  /// On disk, not pinned (e.g. an install from before cloud-only): kept in
  /// sync, but "Free up space" may remove it.
  available,

  /// Pinned itself and on disk.
  alwaysKeep,

  /// On disk because a folder above it is pinned. Unpinning must happen on
  /// that folder, so there is no per-item "free up".
  alwaysKeepViaFolder,
}

/// A pull event that could not be applied for a reason a retry will not fix
/// (an unsafe/unwritable name, or a local file pull refuses to overwrite —
/// see F1/F3/F5 in the PR #12 review). Recorded so one bad file quarantines
/// itself instead of blocking every event after it, and so the user can see
/// what did not sync instead of the app silently claiming to be up to date.
class SyncFailedEvent extends Equatable {
  final String fileId;
  final int eventId;
  final String reason;
  final DateTime failedAt;

  const SyncFailedEvent({
    required this.fileId,
    required this.eventId,
    required this.reason,
    required this.failedAt,
  });

  @override
  List<Object?> get props => [fileId, eventId, reason, failedAt];
}

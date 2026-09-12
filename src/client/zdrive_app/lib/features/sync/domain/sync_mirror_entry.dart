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
class SyncMirrorEntry extends Equatable {
  final String serverId;
  final String localPath;
  final bool isFolder;
  final int? sizeBytes;
  final String? contentHash;
  final DateTime updatedAt;
  final DateTime syncedAt;

  const SyncMirrorEntry({
    required this.serverId,
    required this.localPath,
    required this.isFolder,
    this.sizeBytes,
    this.contentHash,
    required this.updatedAt,
    required this.syncedAt,
  });

  @override
  List<Object?> get props =>
      [serverId, localPath, isFolder, sizeBytes, contentHash, updatedAt, syncedAt];
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

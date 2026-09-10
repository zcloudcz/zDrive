import 'package:equatable/equatable.dart';

/// One row of the local metadata mirror: what pull has already applied for
/// one remote file/folder, and where it landed on disk.
///
/// [contentHash] is the SHA-256 of the bytes pull wrote for this entry (null
/// for folders, which have no content). It exists for the file watcher the
/// next task adds: comparing a locally-observed change against this hash is
/// how that watcher will eventually tell "pull just wrote this" apart from a
/// genuine local edit. Nothing reads it yet.
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

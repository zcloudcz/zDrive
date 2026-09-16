import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'file_item.dart';
import 'file_version.dart';

abstract class FileRepository {
  Future<FileItem> getFile(String id);
  Future<PagedResult<FileItem>> listChildren(
    String? folderId, {
    int page = 1,
    int pageSize = 50,
  });
  // [originDeviceId], when given, is passed through to FileService as
  // X-Device-Id so the change-feed row this write produces is excluded from
  // this same device's future pulls — see FileRemoteDataSource.getChanges.
  // Only LocalChangeScanner's own writes pass it; the file browser's writes
  // leave it null, so pull applies them locally like a change made from any
  // other device.
  Future<FileItem> createFolder(String? parentId, String name, {String? originDeviceId});
  Future<FileItem> renameFile(String id, String newName, {String? originDeviceId});
  Future<FileItem> moveFile(String id, String? newParentId, {String? originDeviceId});
  Future<void> deleteFile(String id, {String? originDeviceId});
  Future<FileItem> restoreFile(String id);
  Future<PagedResult<FileItem>> listTrash({int page = 1, int pageSize = 50});
  Future<void> emptyTrash();
  Future<PagedResult<FileItem>> searchFiles(
    String query, {
    int page = 1,
    int pageSize = 50,
  });
  Future<ShareInfo> createShare(
    String fileId,
    SharePermission permission,
    DateTime? expiresAt,
  );
  Future<void> revokeShare(String id);

  /// Uploads [content] as a new file. [sizeBytes] must be the exact byte
  /// count [content] will produce — it drives the chunk count declared to
  /// StorageService before any bytes are sent. [content] is streamed rather
  /// than taking the whole file as one [Uint8List] so a multi-gigabyte
  /// upload never has to sit fully in memory.
  /// [onNodeCreated] is awaited before sending content, including when a node
  /// is reused. Node creation finishes even if [cancelToken] is cancelled so
  /// the caller can persist its id and reconcile a local deletion.
  Future<String> uploadFile(
    String? parentId,
    String fileName,
    Stream<List<int>> content,
    int sizeBytes,
    void Function(double progress)? onProgress, {
    String? originDeviceId,
    CancelToken? cancelToken,
    Future<void> Function(String fileId)? onNodeCreated,
  });

  /// Downloads and reassembles a file's complete content from its chunks —
  /// there is no assembled whole-file blob on the server.
  Future<Uint8List> downloadFile(String fileId);

  /// Streams verified chunks of the version committed in file metadata.
  /// Consumers must wait for successful stream completion before installing
  /// the content: total length is verified after the last chunk.
  Stream<Uint8List> downloadFileStream(String fileId);

  /// Uploads [content] as a new version of the already-existing file
  /// [fileId] — the second half of [uploadFile] only (chunk upload +
  /// version record), with no node creation. For sync's "last write wins"
  /// path: a local edit is pushed as a new version of the file that already
  /// has this id, not a new file.
  Future<void> uploadNewVersion(
    String fileId,
    String fileName,
    Stream<List<int>> content,
    int sizeBytes, {
    String? originDeviceId,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  });

  /// Lists recorded versions of a file, newest first.
  Future<List<FileVersion>> getVersions(String fileId);

  /// Restores an older version. Records the restore as a new version in
  /// FileService and flips the blob-side manifest in StorageService.
  Future<FileVersion> restoreVersion(String fileId, String versionId);
}

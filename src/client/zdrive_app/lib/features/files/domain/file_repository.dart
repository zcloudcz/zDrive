import 'dart:typed_data';

import 'file_item.dart';
import 'file_version.dart';

abstract class FileRepository {
  Future<FileItem> getFile(String id);
  Future<PagedResult<FileItem>> listChildren(
    String? folderId, {
    int page = 1,
    int pageSize = 50,
  });
  Future<FileItem> createFolder(String? parentId, String name);
  Future<FileItem> renameFile(String id, String newName);
  Future<FileItem> moveFile(String id, String? newParentId);
  Future<void> deleteFile(String id);
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
  Future<String> uploadFile(
    String? parentId,
    String fileName,
    Uint8List bytes,
    void Function(double progress)? onProgress,
  );

  /// Downloads and reassembles a file's complete content from its chunks —
  /// there is no assembled whole-file blob on the server.
  Future<Uint8List> downloadFile(String fileId);

  /// Lists recorded versions of a file, newest first.
  Future<List<FileVersion>> getVersions(String fileId);

  /// Restores an older version. Records the restore as a new version in
  /// FileService and flips the blob-side manifest in StorageService.
  Future<FileVersion> restoreVersion(String fileId, String versionId);
}

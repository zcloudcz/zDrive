import 'dart:typed_data';

import 'package:injectable/injectable.dart';

import '../domain/file_item.dart';
import '../domain/file_repository.dart';
import '../domain/file_version.dart';
import 'file_dtos.dart';
import 'file_remote_data_source.dart';
import 'file_upload_data_source.dart';

@LazySingleton(as: FileRepository)
class FileRepositoryImpl implements FileRepository {
  final FileRemoteDataSource _remoteDataSource;
  final FileUploadDataSource _uploadDataSource;

  FileRepositoryImpl(this._remoteDataSource, this._uploadDataSource);

  @override
  Future<FileItem> getFile(String id) async {
    final dto = await _remoteDataSource.getFile(id);
    return _mapDtoToFileItem(dto);
  }

  @override
  Future<PagedResult<FileItem>> listChildren(
    String? folderId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    final result = await _remoteDataSource.listChildren(
      folderId,
      page: page,
      pageSize: pageSize,
    );
    return _mapPagedResult(result);
  }

  @override
  Future<FileItem> createFolder(String? parentId, String name) async {
    final dto = await _remoteDataSource.createFolder(parentId, name);
    return _mapDtoToFileItem(dto);
  }

  @override
  Future<FileItem> renameFile(String id, String newName) async {
    final dto = await _remoteDataSource.renameFile(id, newName);
    return _mapDtoToFileItem(dto);
  }

  @override
  Future<FileItem> moveFile(String id, String? newParentId) async {
    final dto = await _remoteDataSource.moveFile(id, newParentId);
    return _mapDtoToFileItem(dto);
  }

  @override
  Future<void> deleteFile(String id) async {
    await _remoteDataSource.deleteFile(id);
  }

  @override
  Future<FileItem> restoreFile(String id) async {
    final dto = await _remoteDataSource.restoreFile(id);
    return _mapDtoToFileItem(dto);
  }

  @override
  Future<PagedResult<FileItem>> listTrash({
    int page = 1,
    int pageSize = 50,
  }) async {
    final result = await _remoteDataSource.listTrash(
      page: page,
      pageSize: pageSize,
    );
    return _mapPagedResult(result);
  }

  @override
  Future<void> emptyTrash() async {
    await _remoteDataSource.emptyTrash();
  }

  @override
  Future<PagedResult<FileItem>> searchFiles(
    String query, {
    int page = 1,
    int pageSize = 50,
  }) async {
    final result = await _remoteDataSource.searchFiles(
      query,
      page: page,
      pageSize: pageSize,
    );
    return _mapPagedResult(result);
  }

  @override
  Future<ShareInfo> createShare(
    String fileId,
    SharePermission permission,
    DateTime? expiresAt,
  ) async {
    final dto = await _remoteDataSource.createShare(
      fileId,
      permission.name,
      expiresAt,
    );
    return ShareInfo(
      id: dto.id,
      fileId: dto.fileId,
      permission:
          dto.permission == 'write' ? SharePermission.write : SharePermission.read,
      linkToken: dto.linkToken,
      expiresAt: dto.expiresAt,
    );
  }

  @override
  Future<void> revokeShare(String id) async {
    await _remoteDataSource.revokeShare(id);
  }

  @override
  Future<String> uploadFile(
    String? parentId,
    String fileName,
    Uint8List bytes,
    void Function(double progress)? onProgress,
  ) async {
    // MVP: single-chunk upload
    final session = await _uploadDataSource.initUpload(parentId, fileName, 1);
    await _uploadDataSource.uploadChunk(
      session.sessionId,
      0,
      bytes,
      onProgress: onProgress != null
          ? (sent, total) {
              if (total > 0) onProgress(sent / total);
            }
          : null,
    );
    final result = await _uploadDataSource.completeUpload(session.sessionId);
    return result.fileId;
  }

  @override
  Future<String> getDownloadUrl(String fileId) {
    return _uploadDataSource.getDownloadUrl(fileId);
  }

  @override
  Future<List<FileVersion>> getVersions(String fileId) async {
    final list = await _remoteDataSource.getFileVersions(fileId);
    return list.map(_mapVersion).toList();
  }

  @override
  Future<FileVersion> restoreVersion(String fileId, String versionId) async {
    // Metadata first: FileService validates ownership and records the restore
    // as a new version. Only then flip the blob-side manifest.
    final restored =
        _mapVersion(await _remoteDataSource.restoreFileVersion(fileId, versionId));
    await _remoteDataSource.restoreStorageManifest(fileId, restored.blobVersionId);
    return restored;
  }

  FileVersion _mapVersion(Map<String, dynamic> json) {
    return FileVersion(
      id: json['id'] as String,
      fileId: json['fileId'] as String,
      versionNumber: json['versionNumber'] as int,
      blobVersionId: json['blobVersionId'] as String,
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      manifestHash: json['manifestHash'] as String?,
      comment: json['comment'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  FileItem _mapDtoToFileItem(FileDto dto) {
    return FileItem(
      id: dto.id,
      name: dto.name,
      isFolder: dto.isFolder,
      sizeBytes: dto.sizeBytes,
      mimeType: dto.mimeType,
      parentId: dto.parentId,
      createdAt: dto.createdAt,
      updatedAt: dto.updatedAt,
      isDeleted: dto.isDeleted,
    );
  }

  PagedResult<FileItem> _mapPagedResult(PagedResultDto result) {
    final files = result.items
        .map((e) => _mapDtoToFileItem(
              FileDto.fromJson(e as Map<String, dynamic>),
            ))
        .toList();
    return PagedResult(
      items: files,
      totalCount: result.totalCount,
      page: result.page,
      pageSize: result.pageSize,
    );
  }
}

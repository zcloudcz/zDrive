import 'dart:typed_data';

import 'package:dio/dio.dart';
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
    Stream<List<int>> content,
    int sizeBytes,
    void Function(double progress)? onProgress,
  ) async {
    // Client-orchestrated upload across two services:
    //  1. FileService — create the file node (gives us the id), or reuse one
    //     an earlier attempt already created (see _createOrReuseNode below).
    //  2. StorageService — open a session, push chunks, complete (returns the
    //     manifest hash that identifies this content).
    //  3. FileService — record the version, binding the manifest to the file.
    final node = await _createOrReuseNode(parentId, fileName, sizeBytes);

    final complete = await _uploadDataSource.uploadFile(
      node.id,
      fileName,
      content,
      sizeBytes,
      onProgress: onProgress,
    );

    await _remoteDataSource.createFileVersion(
      node.id,
      blobVersionId: complete.manifestHash,
      sizeBytes: complete.totalSize,
      manifestHash: complete.manifestHash,
    );

    return node.id;
  }

  /// Creates the file node for [fileName], or — only when FileService
  /// rejects it as a duplicate (409, CreateFileCommandHandler.cs) — reuses
  /// the conflicting node, but only if it's an orphan from a previously
  /// failed upload: [FileDto.manifestHash] null means no upload ever
  /// completed for it (the chunk upload can die mid-transfer, e.g. the rate
  /// limiter in dio_client.dart, after createFile already succeeded). A
  /// conflicting node that already has a manifest is a genuine duplicate —
  /// the 409 is rethrown unchanged, so the user sees the same "already
  /// exists" failure as before this reuse logic existed, instead of a silent
  /// overwrite of someone else's file.
  ///
  /// Looking this up only after a 409 (instead of listing children before
  /// every upload) keeps the common case a single request and avoids a
  /// lookup-then-create race between two concurrent uploads of the same name.
  Future<FileDto> _createOrReuseNode(
    String? parentId,
    String fileName,
    int sizeBytes,
  ) async {
    try {
      return await _remoteDataSource.createFile(
        name: fileName,
        isFolder: false,
        parentId: parentId,
        sizeBytes: sizeBytes,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode != 409) rethrow;
      final conflicting = await _findExistingFile(parentId, fileName);
      if (conflicting == null || conflicting.manifestHash != null) rethrow;
      return conflicting;
    }
  }

  /// A non-folder child named [fileName] directly under [parentId], if one
  /// already exists — paginated, since a folder can hold more than one page.
  Future<FileDto?> _findExistingFile(String? parentId, String fileName) async {
    var page = 1;
    const pageSize = 200;
    while (true) {
      final result = await _remoteDataSource.listChildren(
        parentId,
        page: page,
        pageSize: pageSize,
      );
      for (final item in result.items) {
        final dto = FileDto.fromJson(item as Map<String, dynamic>);
        if (dto.name == fileName && !dto.isFolder) return dto;
      }
      if (result.items.isEmpty || page * pageSize >= result.totalCount) {
        return null;
      }
      page++;
    }
  }

  @override
  Future<Uint8List> downloadFile(String fileId) {
    return _uploadDataSource.downloadFile(fileId);
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

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../../../core/diagnostics/diagnostics.dart';

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

  /// Ids of nodes *this app instance* created via [_remoteDataSource.createFile]
  /// and then failed to finish uploading into (chunk upload, complete, or
  /// createFileVersion threw after the node existed). Used by
  /// [_createOrReuseNode] to decide whether a 409's conflicting node is safe
  /// to reuse: `manifestHash == null` alone is not enough, since it is also
  /// true while an upload into that node is still running right now, from
  /// this device or another (round-3 review finding 1 — reusing on
  /// `manifestHash == null` alone could silently merge two independent
  /// uploads). In-memory and per-instance (this class is a `@LazySingleton`)
  /// on purpose: an app restart clears it, so an orphan from a previous run
  /// gets the 409 instead of a silent reuse — loud over silent, the rule
  /// this repo has followed since PR #10.
  final Set<String> _failedUploadNodeIds = {};

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
  Future<FileItem> createFolder(String? parentId, String name, {String? originDeviceId}) async {
    final dto = await _remoteDataSource.createFolder(parentId, name, originDeviceId: originDeviceId);
    return _mapDtoToFileItem(dto);
  }

  @override
  Future<FileItem> renameFile(String id, String newName, {String? originDeviceId}) async {
    final dto = await _remoteDataSource.renameFile(id, newName, originDeviceId: originDeviceId);
    return _mapDtoToFileItem(dto);
  }

  @override
  Future<FileItem> moveFile(String id, String? newParentId, {String? originDeviceId}) async {
    final dto = await _remoteDataSource.moveFile(id, newParentId, originDeviceId: originDeviceId);
    return _mapDtoToFileItem(dto);
  }

  @override
  Future<void> deleteFile(String id, {String? originDeviceId}) async {
    final watch = Stopwatch()..start();
    Diagnostics.event(
      originDeviceId == null
          ? 'file.delete.browser_start'
          : 'file.delete.sync_start',
    );
    try {
      await _remoteDataSource.deleteFile(id, originDeviceId: originDeviceId);
      Diagnostics.event('file.delete.complete', {
        'durationMs': watch.elapsedMilliseconds,
      });
    } catch (error, stack) {
      Diagnostics.error('file.delete.failed', error, stack);
      rethrow;
    }
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
    void Function(double progress)? onProgress, {
    String? originDeviceId,
    CancelToken? cancelToken,
    Future<void> Function(String fileId)? onNodeCreated,
  }) async {
    // Client-orchestrated upload across two services:
    //  1. FileService — create the file node (gives us the id), or reuse one
    //     an earlier attempt already created (see _createOrReuseNode below).
    //  2. StorageService — open a session, push chunks, complete (returns the
    //     manifest hash that identifies this content).
    //  3. FileService — record the version, binding the manifest to the file.
    if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
    final node = await _createOrReuseNode(parentId, fileName, sizeBytes, originDeviceId);

    try {
      await onNodeCreated?.call(node.id);
      await _uploadIntoNode(node.id, fileName, content, sizeBytes, onProgress, originDeviceId, cancelToken);
      _failedUploadNodeIds.remove(node.id);
      return node.id;
    } catch (_) {
      // Record the node as ours-and-failed *before* rethrowing, so a
      // same-instance retry of the same name can recognise and reuse it on
      // the next 409 (see _createOrReuseNode).
      _failedUploadNodeIds.add(node.id);
      rethrow;
    }
  }

  @override
  Future<void> uploadNewVersion(
    String fileId,
    String fileName,
    Stream<List<int>> content,
    int sizeBytes, {
    String? originDeviceId,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) {
    // The second half of uploadFile only: no node creation, so this never
    // touches _createOrReuseNode or _failedUploadNodeIds — fileId is already
    // an existing node.
    return _uploadIntoNode(fileId, fileName, content, sizeBytes, onProgress, originDeviceId, cancelToken);
  }

  /// Chunk-uploads [content] into the already-existing node [nodeId] and
  /// records the resulting version — shared by [uploadFile] (after creating
  /// the node) and [uploadNewVersion] (which skips node creation entirely).
  /// [originDeviceId] only tags the FileService write below
  /// ([FileRemoteDataSource.createFileVersion]) — the StorageService chunk
  /// upload itself has no change-feed row of its own to exclude from.
  Future<void> _uploadIntoNode(
    String nodeId,
    String fileName,
    Stream<List<int>> content,
    int sizeBytes,
    void Function(double progress)? onProgress,
    String? originDeviceId,
    CancelToken? cancelToken,
  ) async {
    if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
    final complete = await _uploadDataSource.uploadFile(
      nodeId,
      fileName,
      content,
      sizeBytes,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );

    if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
    await _remoteDataSource.createFileVersion(
      nodeId,
      blobVersionId: complete.manifestHash,
      sizeBytes: complete.totalSize,
      manifestHash: complete.manifestHash,
      originDeviceId: originDeviceId,
      cancelToken: cancelToken,
    );
  }

  /// Creates the file node for [fileName], or — only when FileService
  /// rejects it as a duplicate (409, CreateFileCommandHandler.cs) — reuses
  /// the conflicting node, but only when both hold:
  ///  - [FileDto.manifestHash] is null (no upload has completed for it yet),
  ///    and
  ///  - its id is in [_failedUploadNodeIds] — this app instance is the one
  ///    that created it and then failed to finish uploading into it.
  /// The first check alone is not enough: it is also true while an upload
  /// into the node is still running right now, from this device or another,
  /// so reusing on it alone could silently merge two independent uploads
  /// (round-3 review finding 1). Anything that fails either check is treated
  /// as a genuine duplicate as far as this instance can tell — the 409 is
  /// rethrown unchanged, so the user sees the same "already exists" failure
  /// as before this reuse logic existed, instead of a silent overwrite of
  /// someone else's file.
  ///
  /// The id is *removed* from the set when it is reused, so each failed node
  /// is handed out at most once. Checking membership without removing left
  /// the node claimable for as long as the retry ran, and a third upload of
  /// the same name took it too (round-4 review). This holds for uploads from
  /// this app instance only: ZDrive.BackupCli reuses nodes by name on its own
  /// terms and is not bound by this set.
  ///
  /// Looking this up only after a 409 (instead of listing children before
  /// every upload) keeps the common case a single request and avoids a
  /// lookup-then-create race between two concurrent uploads of the same name.
  Future<FileDto> _createOrReuseNode(
    String? parentId,
    String fileName,
    int sizeBytes,
    String? originDeviceId,
  ) async {
    try {
      return await _remoteDataSource.createFile(
        name: fileName,
        isFolder: false,
        parentId: parentId,
        sizeBytes: sizeBytes,
        originDeviceId: originDeviceId,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode != 409) rethrow;
      final conflicting = await _findExistingFile(parentId, fileName);
      if (conflicting == null || conflicting.manifestHash != null) rethrow;
      if (!_failedUploadNodeIds.remove(conflicting.id)) rethrow;
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
  Future<Uint8List> downloadFile(String fileId) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in downloadFileStream(fileId)) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  @override
  Stream<Uint8List> downloadFileStream(String fileId) async* {
    final metadata = await _remoteDataSource.getFile(fileId);
    final manifestHash = metadata.manifestHash;
    if (manifestHash == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(manifestHash)) {
      throw StateError('File has no committed content manifest');
    }
    yield* _uploadDataSource.downloadFileStream(fileId, manifestHash: manifestHash);
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
      isContentReady: dto.isFolder || dto.manifestHash != null,
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

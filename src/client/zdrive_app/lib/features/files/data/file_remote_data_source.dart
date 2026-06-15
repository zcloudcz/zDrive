// ignore_for_file: use_null_aware_elements

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../../../core/network/api_constants.dart';
import '../../../core/network/api_envelope.dart';
import 'file_dtos.dart';

@lazySingleton
class FileRemoteDataSource {
  final Dio _dio;

  FileRemoteDataSource(this._dio);

  Future<FileDto> getFile(String id) async {
    final response = await _dio.get('${ApiConstants.files}/$id');
    return FileDto.fromJson(unwrapMap(response));
  }

  /// Lists children of [folderId], or the root when null.
  /// Root has a dedicated route because "{id}/children" cannot express null.
  Future<PagedResultDto> listChildren(
    String? folderId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    final path = folderId == null
        ? '${ApiConstants.files}/root/children'
        : '${ApiConstants.files}/$folderId/children';
    final response = await _dio.get(
      path,
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    return PagedResultDto.fromJson(unwrapMap(response));
  }

  /// Creates a file node. Used for folders (isFolder=true) and as the first
  /// step of an upload (isFolder=false), where the returned id is then used
  /// to initialise the blob upload session.
  Future<FileDto> createFile({
    required String name,
    required bool isFolder,
    String? parentId,
    int? sizeBytes,
    String? mimeType,
  }) async {
    final response = await _dio.post(
      ApiConstants.files,
      data: {
        'name': name,
        'isFolder': isFolder,
        if (parentId != null) 'parentId': parentId,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        if (mimeType != null) 'mimeType': mimeType,
      },
    );
    return FileDto.fromJson(unwrapMap(response));
  }

  Future<FileDto> createFolder(String? parentId, String name) {
    return createFile(name: name, isFolder: true, parentId: parentId);
  }

  Future<FileDto> renameFile(String id, String newName) async {
    final response = await _dio.put(
      '${ApiConstants.files}/$id/rename',
      data: {'newName': newName},
    );
    return FileDto.fromJson(unwrapMap(response));
  }

  Future<FileDto> moveFile(String id, String? newParentId) async {
    final response = await _dio.put(
      '${ApiConstants.files}/$id/move',
      data: {'newParentId': newParentId},
    );
    return FileDto.fromJson(unwrapMap(response));
  }

  Future<void> deleteFile(String id) async {
    final response = await _dio.delete('${ApiConstants.files}/$id');
    ensureSuccess(response);
  }

  Future<FileDto> restoreFile(String id) async {
    final response = await _dio.post('${ApiConstants.files}/$id/restore');
    return FileDto.fromJson(unwrapMap(response));
  }

  Future<PagedResultDto> listTrash({int page = 1, int pageSize = 50}) async {
    final response = await _dio.get(
      ApiConstants.trash,
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    return PagedResultDto.fromJson(unwrapMap(response));
  }

  Future<void> emptyTrash() async {
    final response = await _dio.delete(ApiConstants.trash);
    ensureSuccess(response);
  }

  Future<PagedResultDto> searchFiles(
    String query, {
    int page = 1,
    int pageSize = 50,
  }) async {
    final response = await _dio.get(
      ApiConstants.filesSearch,
      queryParameters: {'q': query, 'page': page, 'pageSize': pageSize},
    );
    return PagedResultDto.fromJson(unwrapMap(response));
  }

  Future<ShareDto> createShare(
    String fileId,
    String permission,
    DateTime? expiresAt,
  ) async {
    final response = await _dio.post(
      ApiConstants.shares,
      data: {
        'fileId': fileId,
        'permission': permission,
        if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
      },
    );
    return ShareDto.fromJson(unwrapMap(response));
  }

  Future<void> revokeShare(String id) async {
    final response = await _dio.delete('${ApiConstants.shares}/$id');
    ensureSuccess(response);
  }

  // --- Versions (FileService) ---

  Future<List<Map<String, dynamic>>> getFileVersions(String fileId) async {
    final response = await _dio.get('${ApiConstants.files}/$fileId/versions');
    return unwrapMapList(response);
  }

  /// Records a new version for [fileId] after a blob upload completes,
  /// binding the manifest hash (and size) to the file.
  Future<Map<String, dynamic>> createFileVersion(
    String fileId, {
    required String blobVersionId,
    required int sizeBytes,
    required String manifestHash,
    String? comment,
  }) async {
    final response = await _dio.post(
      '${ApiConstants.files}/$fileId/versions',
      data: {
        'blobVersionId': blobVersionId,
        'sizeBytes': sizeBytes,
        'manifestHash': manifestHash,
        if (comment != null) 'comment': comment,
      },
    );
    return unwrapMap(response);
  }

  Future<Map<String, dynamic>> restoreFileVersion(
    String fileId,
    String versionId,
  ) async {
    final response = await _dio.post(
      '${ApiConstants.files}/$fileId/versions/$versionId/restore',
    );
    return unwrapMap(response);
  }

  /// Flips the blob-side manifest to a snapshot (StorageService).
  Future<void> restoreStorageManifest(String fileId, String manifestHash) async {
    final response = await _dio.post(
      '${ApiConstants.storage}/files/$fileId/manifests/$manifestHash/restore',
    );
    ensureSuccess(response);
  }
}

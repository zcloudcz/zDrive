// ignore_for_file: use_null_aware_elements

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../../../core/network/api_constants.dart';
import 'file_dtos.dart';

@lazySingleton
class FileRemoteDataSource {
  final Dio _dio;

  FileRemoteDataSource(this._dio);

  Future<FileDto> getFile(String id) async {
    final response = await _dio.get('${ApiConstants.files}/$id');
    return FileDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PagedResultDto> listChildren(
    String? folderId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    final response = await _dio.get(
      ApiConstants.files,
      queryParameters: {
        if (folderId != null) 'parentId': folderId,
        'page': page,
        'pageSize': pageSize,
      },
    );
    return PagedResultDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<FileDto> createFolder(String? parentId, String name) async {
    final response = await _dio.post(
      ApiConstants.folders,
      data: {
        if (parentId != null) 'parentId': parentId,
        'name': name,
      },
    );
    return FileDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<FileDto> renameFile(String id, String newName) async {
    final response = await _dio.patch(
      '${ApiConstants.files}/$id',
      data: {'name': newName},
    );
    return FileDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<FileDto> moveFile(String id, String? newParentId) async {
    final response = await _dio.patch(
      '${ApiConstants.files}/$id/move',
      data: {'parentId': newParentId},
    );
    return FileDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteFile(String id) async {
    await _dio.delete('${ApiConstants.files}/$id');
  }

  Future<FileDto> restoreFile(String id) async {
    final response = await _dio.post('${ApiConstants.files}/$id/restore');
    return FileDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PagedResultDto> listTrash({int page = 1, int pageSize = 50}) async {
    final response = await _dio.get(
      ApiConstants.trash,
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    return PagedResultDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> emptyTrash() async {
    await _dio.delete(ApiConstants.trash);
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
    return PagedResultDto.fromJson(response.data as Map<String, dynamic>);
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
    return ShareDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> revokeShare(String id) async {
    await _dio.delete('${ApiConstants.shares}/$id');
  }

  /// Versions endpoints use the real backend envelope ({success, data, error});
  /// the payload lives under "data".
  Future<List<Map<String, dynamic>>> getFileVersions(String fileId) async {
    final response = await _dio.get('${ApiConstants.files}/$fileId/versions');
    final envelope = response.data as Map<String, dynamic>;
    return (envelope['data'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> restoreFileVersion(
    String fileId,
    String versionId,
  ) async {
    final response = await _dio.post(
      '${ApiConstants.files}/$fileId/versions/$versionId/restore',
    );
    final envelope = response.data as Map<String, dynamic>;
    return envelope['data'] as Map<String, dynamic>;
  }

  /// Flips the blob-side manifest to a snapshot (StorageService).
  Future<void> restoreStorageManifest(String fileId, String manifestHash) async {
    await _dio.post(
      '${ApiConstants.storage}/files/$fileId/manifests/$manifestHash/restore',
    );
  }
}

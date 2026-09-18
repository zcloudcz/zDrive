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

  /// Pulls the server's append-only change feed starting after [cursor].
  /// [deviceId], when given, is sent as `X-Device-Id` so FileService excludes
  /// rows this device's own writes produced (see [createFile] and the other
  /// write methods below, which tag their own writes with the same header).
  Future<ChangeFeedPageDto> getChanges(int cursor, {int limit = 500, String? deviceId}) async {
    final response = await _dio.get(
      '${ApiConstants.files}/changes',
      queryParameters: {'cursor': cursor, 'limit': limit},
      options: _deviceIdOptions(deviceId),
    );
    return ChangeFeedPageDto.fromJson(unwrapMap(response));
  }

  /// Builds the `X-Device-Id` header [Options] shared by every write method
  /// below, or null when [deviceId] is null — Dio treats a null [Options] the
  /// same as omitting the parameter entirely.
  Options? _deviceIdOptions(String? deviceId) =>
      deviceId == null ? null : Options(headers: {'X-Device-Id': deviceId});

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
    // Carried through to FileService as X-Device-Id — see [getChanges]'s doc
    // comment. Only the sync scanner's own writes pass this; the file
    // browser's writes leave it null, so pull applies them locally like any
    // other device's change (LocalChangeScanner tags its own writes; the
    // file browser never does).
    String? originDeviceId,
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
      options: _deviceIdOptions(originDeviceId),
    );
    return FileDto.fromJson(unwrapMap(response));
  }

  Future<FileDto> createFolder(String? parentId, String name, {String? originDeviceId}) {
    return createFile(
      name: name,
      isFolder: true,
      parentId: parentId,
      originDeviceId: originDeviceId,
    );
  }

  Future<FileDto> renameFile(String id, String newName, {String? originDeviceId}) async {
    final response = await _dio.put(
      '${ApiConstants.files}/$id/rename',
      data: {'newName': newName},
      options: _deviceIdOptions(originDeviceId),
    );
    return FileDto.fromJson(unwrapMap(response));
  }

  Future<FileDto> moveFile(String id, String? newParentId, {String? originDeviceId}) async {
    final response = await _dio.put(
      '${ApiConstants.files}/$id/move',
      data: {'newParentId': newParentId},
      options: _deviceIdOptions(originDeviceId),
    );
    return FileDto.fromJson(unwrapMap(response));
  }

  Future<void> deleteFile(String id, {String? originDeviceId}) async {
    final response =
        await _dio.delete('${ApiConstants.files}/$id', options: _deviceIdOptions(originDeviceId));
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
    String? originDeviceId,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.post(
      '${ApiConstants.files}/$fileId/versions',
      data: {
        'blobVersionId': blobVersionId,
        'sizeBytes': sizeBytes,
        'manifestHash': manifestHash,
        if (comment != null) 'comment': comment,
      },
      cancelToken: cancelToken,
      options: _deviceIdOptions(originDeviceId),
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
  ///
  /// First StorageService call of the restore flow — may hit a cold start.
  Future<void> restoreStorageManifest(String fileId, String manifestHash) async {
    final response = await _dio.post(
      '${ApiConstants.storage}/files/$fileId/manifests/$manifestHash/restore',
      options: Options(receiveTimeout: ApiConstants.storageColdStartTimeout),
    );
    ensureSuccess(response);
  }
}

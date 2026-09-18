import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import '../../../core/network/api_constants.dart';
import '../../../core/network/api_envelope.dart';
import '../../files/data/file_dtos.dart';
import '../../files/data/file_saver.dart';
import '../../files/data/file_upload_data_source.dart'
    show assembleVerifiedFileStream, chunkSha256Hash, runChunkedUpload;
import 'share_link_dtos.dart';

/// Header carrying the short-lived, single-file download grant issued by
/// [ShareLinkDataSource.requestDownloadGrant]. Anonymous visitors have no
/// JWT, so StorageService authorizes shared downloads through this instead.
const shareGrantHeader = 'X-Share-Grant';

/// Anonymous read access to a public share link: the shared file/folder
/// itself, its children, and downloads. Every call is unauthenticated — no
/// token is attached (see `AuthInterceptor`, which only adds a header when
/// one exists) — and the backend answers 404 for an unknown/expired/deleted
/// link and 403 for a password-protected one (not supported by this client
/// yet), which `ShareLinkCubit` turns into distinct states.
@lazySingleton
class ShareLinkDataSource {
  final Dio _dio;

  ShareLinkDataSource(this._dio);

  Future<({ShareDto share, FileDto file})> getShareLink(String token) async {
    // go_router hands path parameters over already URL-decoded, so a token
    // containing '/', '?', etc. (opaque server-issued ids, not guaranteed
    // URL-safe) must be re-encoded before it goes back into a path segment —
    // otherwise it would split the path or start a query string.
    final response = await _dio.get('${ApiConstants.shares}/link/${Uri.encodeComponent(token)}');
    final data = unwrapMap(response);
    return (
      share: ShareDto.fromJson(data['share'] as Map<String, dynamic>),
      file: FileDto.fromJson(data['file'] as Map<String, dynamic>),
    );
  }

  /// Lists the children of a folder inside the share. [folderId] omitted
  /// means the shared root itself.
  Future<List<FileDto>> getChildren(String token, {String? folderId}) async {
    final response = await _dio.get(
      '${ApiConstants.shares}/link/${Uri.encodeComponent(token)}/children',
      queryParameters: folderId == null ? null : {'folderId': folderId},
    );
    return unwrapMapList(response).map(FileDto.fromJson).toList();
  }

  Future<DownloadGrantDto> requestDownloadGrant(String token, String fileId) async {
    final response = await _dio.post(
      '${ApiConstants.shares}/link/${Uri.encodeComponent(token)}/download-grant',
      data: {'fileId': fileId},
    );
    return DownloadGrantDto.fromJson(unwrapMap(response));
  }

  /// The first storage call of the flow, so it may hit a cold StorageService
  /// instance — same reasoning as `initUpload`/the authenticated
  /// `getManifest` in `file_upload_data_source.dart`. Chunk requests don't
  /// carry it: only the very first request of a session pays the cold-start
  /// cost.
  Future<ManifestDto> getManifest(String grant) async {
    final response = await _dio.get(
      '${ApiConstants.storage}/shared/manifest',
      options: Options(
        headers: {shareGrantHeader: grant},
        receiveTimeout: ApiConstants.storageColdStartTimeout,
      ),
    );
    return ManifestDto.fromJson(unwrapMap(response));
  }

  Future<Uint8List> downloadChunkBytes(String grant, String chunkHash) async {
    final response = await _dio.get<List<int>>(
      '${ApiConstants.storage}/shared/chunk/$chunkHash/bytes',
      options: Options(responseType: ResponseType.bytes, headers: {shareGrantHeader: grant}),
    );
    return Uint8List.fromList(response.data!);
  }

  /// Downloads one shared file end to end: request a grant, reassemble its
  /// chunks with the same corruption checks the authenticated download path
  /// uses ([assembleVerifiedFileStream]), and hand the result to the same
  /// platform saver the file browser's download uses ([saveFileStream]).
  /// [onProgress] is fed 0..1 from the grant's declared [DownloadGrantDto.sizeBytes].
  ///
  /// The grant is a revocation window, not a download-completion budget — it
  /// lives 1 hour, but a slow/large download can still outlive it, at which
  /// point storage starts answering 404 to chunk requests carrying it. On
  /// exactly one such 404, a fresh grant is requested and that chunk is
  /// retried with it; a second 404 (grant re-minting didn't help, or the
  /// share was revoked meanwhile) fails the download instead of looping.
  Future<void> downloadFile(
    String token,
    String fileId, {
    void Function(double progress)? onProgress,
    Future<void> Function(String fileName, Stream<Uint8List> content) save = saveFileStream,
  }) async {
    var grantInfo = await requestDownloadGrant(token, fileId);
    var reMinted = false;
    var transferred = 0;
    final stream = assembleVerifiedFileStream(
      fetchManifest: () => getManifest(grantInfo.grant),
      fetchChunkBytes: (hash) async {
        try {
          return await downloadChunkBytes(grantInfo.grant, hash);
        } on DioException catch (e) {
          if (e.response?.statusCode != 404 || reMinted) rethrow;
          reMinted = true;
          grantInfo = await requestDownloadGrant(token, fileId);
          return await downloadChunkBytes(grantInfo.grant, hash);
        }
      },
      expectedManifestHash: grantInfo.manifestHash,
    ).map((chunk) {
      transferred += chunk.length;
      if (grantInfo.sizeBytes > 0) {
        onProgress?.call((transferred / grantInfo.sizeBytes).clamp(0.0, 1.0));
      }
      return chunk;
    });
    await save(grantInfo.fileName, stream);
  }

  /// What this link is allowed to do, and (for a Write link) the owner's
  /// quota. Fetched alongside the existing metadata load in
  /// `ShareLinkCubit.load` — a 404 here (an older backend without this
  /// endpoint) is the caller's cue to fall back to read-only.
  Future<ShareInfoDto> getInfo(String token) async {
    final response = await _dio.get('${ApiConstants.shares}/link/${Uri.encodeComponent(token)}/info');
    return ShareInfoDto.fromJson(unwrapMap(response));
  }

  /// Creates a folder inside the share. [parentId] omitted means the shared
  /// root. A name collision answers 409 — surfaced as-is, not retried here.
  Future<FileDto> createFolder(String token, {String? parentId, required String name}) async {
    final response = await _dio.post(
      '${ApiConstants.shares}/link/${Uri.encodeComponent(token)}/folders',
      data: {'parentId': parentId, 'name': name},
    );
    return FileDto.fromJson(unwrapMap(response));
  }

  Future<ShareUploadGrantDto> requestUploadGrant(
    String token, {
    String? parentId,
    String? fileName,
    required int sizeBytes,
    required bool overwrite,
  }) async {
    final response = await _dio.post(
      '${ApiConstants.shares}/link/${Uri.encodeComponent(token)}/upload-grant',
      data: {'parentId': parentId, 'fileName': fileName, 'sizeBytes': sizeBytes, 'overwrite': overwrite},
    );
    return ShareUploadGrantDto.fromJson(unwrapMap(response));
  }

  /// Records a completed upload against [fileId] — without this call the
  /// uploaded bytes stay invisible to the share (no version row).
  Future<FileDto> recordFileVersion(String token, String fileId, String receipt) async {
    final response = await _dio.post(
      '${ApiConstants.shares}/link/${Uri.encodeComponent(token)}/files/${Uri.encodeComponent(fileId)}/versions',
      data: {'receipt': receipt},
    );
    return FileDto.fromJson(unwrapMap(response));
  }

  /// Moves [id] to the owner's trash. The shared root itself cannot be
  /// deleted this way (backend answers 403).
  Future<void> deleteItem(String token, String id) async {
    final response = await _dio.delete(
      '${ApiConstants.shares}/link/${Uri.encodeComponent(token)}/items/${Uri.encodeComponent(id)}',
    );
    ensureSuccess(response);
  }

  Future<String> _initSharedUpload(String grant, String fileName, int totalChunks) async {
    // First StorageService call of the upload flow — may hit a cold start,
    // same reasoning as getManifest above.
    final response = await _dio.post(
      '${ApiConstants.storage}/shared/upload/init',
      data: {'fileName': fileName, 'totalChunks': totalChunks},
      options: Options(
        headers: {shareGrantHeader: grant},
        receiveTimeout: ApiConstants.storageColdStartTimeout,
      ),
    );
    return UploadSessionDto.fromJson(unwrapMap(response)).sessionId;
  }

  Future<void> _uploadSharedChunk(
    String grant,
    String sessionId,
    int index,
    Uint8List bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final chunkHash = await compute(chunkSha256Hash, bytes);
    final response = await _dio.put(
      '${ApiConstants.storage}/shared/upload/$sessionId/chunk/$index',
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {
          shareGrantHeader: grant,
          'X-Chunk-Hash': chunkHash,
          'Content-Type': 'application/octet-stream',
          Headers.contentLengthHeader: bytes.length,
        },
      ),
      onSendProgress: onProgress,
    );
    ensureSuccess(response);
  }

  Future<SharedUploadCompleteDto> _completeSharedUpload(String grant, String sessionId) async {
    final response = await _dio.post(
      '${ApiConstants.storage}/shared/upload/$sessionId/complete',
      options: Options(headers: {shareGrantHeader: grant}),
    );
    return SharedUploadCompleteDto.fromJson(unwrapMap(response));
  }

  Future<void> _abortSharedUpload(String grant, String sessionId) async {
    // Same best-effort-cleanup shape as FileUploadDataSource._abortUpload.
    final cleanupToken = CancelToken();
    final timeout = Timer(const Duration(seconds: 5), () {
      cleanupToken.cancel('Upload cleanup timed out');
    });
    try {
      await _dio.delete(
        '${ApiConstants.storage}/shared/upload/$sessionId',
        options: Options(headers: {shareGrantHeader: grant}),
        cancelToken: cleanupToken,
      );
    } catch (_) {
      // Best effort: preserve the original upload/cancellation failure.
    } finally {
      timeout.cancel();
    }
  }

  /// Uploads a file through the share: upload-grant → init → chunks →
  /// complete → record the version, reusing [runChunkedUpload] (the same
  /// init/uploadChunk/complete/abort loop the authenticated upload uses) for
  /// the chunking. [parentId] omitted means the shared root; for a share
  /// whose root is itself a single file, pass [parentId] null and
  /// [overwrite] true to replace that file directly (matches the
  /// upload-grant contract). On any failure after the grant's `init` call,
  /// the session is aborted.
  Future<FileDto> uploadFile(
    String token, {
    String? parentId,
    required String fileName,
    required Stream<List<int>> content,
    required int sizeBytes,
    bool overwrite = false,
    void Function(double progress)? onProgress,
  }) async {
    final grantInfo = await requestUploadGrant(
      token,
      parentId: parentId,
      fileName: fileName,
      sizeBytes: sizeBytes,
      overwrite: overwrite,
    );
    final completeInfo = await runChunkedUpload<SharedUploadCompleteDto>(
      init: (totalChunks) => _initSharedUpload(grantInfo.grant, grantInfo.fileName, totalChunks),
      uploadChunk: (sessionId, index, chunk, {onProgress}) =>
          _uploadSharedChunk(grantInfo.grant, sessionId, index, chunk, onProgress: onProgress),
      complete: (sessionId) => _completeSharedUpload(grantInfo.grant, sessionId),
      abort: (sessionId) => _abortSharedUpload(grantInfo.grant, sessionId),
      content: content,
      sizeBytes: sizeBytes,
      onProgress: onProgress,
    );
    return recordFileVersion(token, grantInfo.fileId, completeInfo.receipt);
  }
}

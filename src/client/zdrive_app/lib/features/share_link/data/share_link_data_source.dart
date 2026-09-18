import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../../../core/network/api_constants.dart';
import '../../../core/network/api_envelope.dart';
import '../../files/data/file_dtos.dart';
import '../../files/data/file_saver.dart';
import '../../files/data/file_upload_data_source.dart' show assembleVerifiedFileStream;
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
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../../../core/network/api_constants.dart';
import '../../../core/network/api_envelope.dart';
import 'file_dtos.dart';

/// Thrown when a downloaded chunk's content does not hash to the value
/// recorded for it in the manifest — corruption or tampering in transit.
class ChunkHashMismatchException implements Exception {
  final String chunkHash;
  final String actualHash;

  const ChunkHashMismatchException(this.chunkHash, this.actualHash);

  @override
  String toString() =>
      'ChunkHashMismatchException: expected $chunkHash, got $actualHash';
}

/// Thin transport over StorageService's chunked-upload API. Orchestration
/// (creating the file node, recording the version) lives in the repository.
@lazySingleton
class FileUploadDataSource {
  final Dio _dio;

  FileUploadDataSource(this._dio);

  /// Opens an upload session for an already-created file node.
  Future<UploadSessionDto> initUpload(
    String fileId,
    String fileName,
    int totalChunks,
  ) async {
    final response = await _dio.post(
      ApiConstants.uploadInit,
      data: {
        'fileId': fileId,
        'fileName': fileName,
        'totalChunks': totalChunks,
      },
    );
    return UploadSessionDto.fromJson(unwrapMap(response));
  }

  /// Uploads a single chunk as a raw octet stream. The server recomputes the
  /// content hash on completion; the X-Chunk-Hash header is advisory but
  /// required, so we send the real SHA-256 of the chunk.
  Future<void> uploadChunk(
    String sessionId,
    int chunkIndex,
    Uint8List bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final chunkHash = sha256.convert(bytes).toString();
    final response = await _dio.put(
      '${ApiConstants.storage}/upload/$sessionId/chunk/$chunkIndex',
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {
          'X-Chunk-Hash': chunkHash,
          'Content-Type': 'application/octet-stream',
          Headers.contentLengthHeader: bytes.length,
        },
      ),
      onSendProgress: onProgress,
    );
    ensureSuccess(response);
  }

  Future<UploadCompleteDto> completeUpload(String sessionId) async {
    final response = await _dio.post(
      '${ApiConstants.storage}/upload/$sessionId/complete',
    );
    return UploadCompleteDto.fromJson(unwrapMap(response));
  }

  Future<String> getDownloadUrl(String fileId) async {
    final response = await _dio.get(
      '${ApiConstants.storage}/download/$fileId',
    );
    return DownloadUrlDto.fromJson(unwrapMap(response)).sasUrl;
  }

  Future<String> getChunkDownloadUrl(String fileId, String chunkHash) async {
    final response = await _dio.get(
      '${ApiConstants.storage}/download/$fileId/chunk/$chunkHash',
    );
    return DownloadUrlDto.fromJson(unwrapMap(response)).sasUrl;
  }

  /// Downloads a file's complete content.
  ///
  /// There is no assembled whole-file blob on the server — StorageService
  /// only ever writes content-addressed chunks (`chunks/{hash}.blk`) plus a
  /// `manifest.json` listing them — so reassembly happens here: fetch the
  /// manifest, fetch each chunk in manifest order, verify its SHA-256
  /// against the hash the manifest recorded for it (chunks are content-
  /// addressed by that hash, so a mismatch means corruption or tampering in
  /// transit), and concatenate.
  ///
  /// [blobFetcher] performs the actual GET against a blob SAS URL. It must
  /// NOT be [_dio] — [_dio] carries this app's Authorization header via
  /// [AuthInterceptor], which must not be sent to Azure Blob Storage.
  /// Defaults to a bare [Dio]; overridden in tests.
  Future<Uint8List> downloadFile(String fileId, {Dio? blobFetcher}) async {
    final blob = blobFetcher ?? Dio();

    final manifestUrl = await getDownloadUrl(fileId);
    final manifestResponse = await blob.get<String>(
      manifestUrl,
      options: Options(responseType: ResponseType.plain),
    );
    final manifest = ManifestDto.fromJson(
      jsonDecode(manifestResponse.data!) as Map<String, dynamic>,
    );

    final chunks = [...manifest.chunks]
      ..sort((a, b) => a.index.compareTo(b.index));

    final builder = BytesBuilder(copy: false);
    for (final chunk in chunks) {
      final chunkUrl = await getChunkDownloadUrl(fileId, chunk.hash);
      final chunkResponse = await blob.get<List<int>>(
        chunkUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = Uint8List.fromList(chunkResponse.data!);

      final actualHash = sha256.convert(bytes).toString();
      if (actualHash != chunk.hash) {
        throw ChunkHashMismatchException(chunk.hash, actualHash);
      }
      builder.add(bytes);
    }
    return builder.toBytes();
  }
}

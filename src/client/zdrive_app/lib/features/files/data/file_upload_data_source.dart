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

/// Thrown when the reassembled file does not match the manifest's recorded
/// `totalSize`. Per-chunk SHA-256 only proves each chunk's own bytes are
/// intact; it cannot catch a chunk dropped server-side, an index sent twice,
/// or an empty chunk list — all of which change the assembled length.
class ManifestSizeMismatchException implements Exception {
  final int expectedSize;
  final int actualSize;

  const ManifestSizeMismatchException(this.expectedSize, this.actualSize);

  @override
  String toString() =>
      'ManifestSizeMismatchException: manifest declared $expectedSize bytes, got $actualSize';
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

  /// Fetches the chunk manifest for a file.
  Future<ManifestDto> getManifest(String fileId) async {
    final response = await _dio.get(
      '${ApiConstants.storage}/download/$fileId/manifest',
    );
    return ManifestDto.fromJson(unwrapMap(response));
  }

  /// Fetches one chunk's raw bytes.
  Future<Uint8List> downloadChunkBytes(String fileId, String chunkHash) async {
    final response = await _dio.get<List<int>>(
      '${ApiConstants.storage}/download/$fileId/chunk/$chunkHash/bytes',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }

  /// Downloads a file's complete content.
  ///
  /// There is no assembled whole-file blob on the server — StorageService
  /// only ever writes content-addressed chunks (`chunks/{hash}.blk`) plus a
  /// manifest listing them — so reassembly happens here: fetch the manifest,
  /// fetch each chunk in manifest order, verify its SHA-256 against the hash
  /// the manifest recorded for it (chunks are content-addressed by that
  /// hash, so a mismatch means corruption or tampering in transit), and
  /// concatenate.
  ///
  /// Manifest and chunks are fetched through this app's own API — StorageService
  /// proxies the blob bytes — rather than SAS URLs straight to Azure Blob
  /// Storage: a SAS token authorises the request but does not exempt it from
  /// CORS, and Blob Storage CORS is not configured (and Azurite does not
  /// support it locally either), so a browser client could never complete
  /// that cross-origin fetch. The gateway this app already talks to has CORS
  /// configured, so proxying works identically on every platform.
  Future<Uint8List> downloadFile(String fileId) async {
    final manifest = await getManifest(fileId);

    final chunks = [...manifest.chunks]
      ..sort((a, b) => a.index.compareTo(b.index));

    // ponytail: whole file is buffered in memory (this BytesBuilder plus the
    // copy toBytes() makes), peak ~2-3x file size. Pre-existing ceiling —
    // upload is already whole-file/single-chunk, so nothing this client
    // uploads is bigger than that today. Upgrade path if that changes:
    // stream to a temp file on native, File System Access API on web.
    final builder = BytesBuilder(copy: false);
    for (final chunk in chunks) {
      final bytes = await downloadChunkBytes(fileId, chunk.hash);

      final actualHash = sha256.convert(bytes).toString();
      if (actualHash != chunk.hash) {
        throw ChunkHashMismatchException(chunk.hash, actualHash);
      }
      builder.add(bytes);
    }

    final assembled = builder.toBytes();
    // Per-chunk hashing only proves each chunk's own bytes are intact — it
    // says nothing about whether the *set* of chunks is complete or correct
    // (a chunk dropped server-side, an index sent twice, an empty chunk
    // list). Comparing the assembled length against the manifest's recorded
    // total catches all of those; a separate index contiguity/uniqueness
    // check would only catch the same cases the length check already does,
    // so it is not added on top.
    if (assembled.length != manifest.totalSize) {
      throw ManifestSizeMismatchException(manifest.totalSize, assembled.length);
    }
    return assembled;
  }
}

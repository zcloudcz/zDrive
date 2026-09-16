import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import '../../../core/network/api_constants.dart';
import '../../../core/network/api_envelope.dart';
import 'file_dtos.dart';

String _chunkHash(Uint8List bytes) => sha256.convert(bytes).toString();

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

class ManifestChunkIndexException implements Exception {
  final int expectedIndex;
  final int actualIndex;

  const ManifestChunkIndexException(this.expectedIndex, this.actualIndex);

  @override
  String toString() =>
      'ManifestChunkIndexException: expected chunk index $expectedIndex, got $actualIndex';
}

/// Thrown when the stream handed to [FileUploadDataSource.uploadFile]
/// produced a different number of bytes than the caller declared as
/// [FileUploadDataSource.uploadFile]'s `sizeBytes`. StorageService only
/// checks chunk *count* and index completeness, never byte length (see the
/// doc comment on `uploadFile`), so a stream that changed size between being
/// picked and being read would otherwise complete as a corrupt upload with
/// no error anywhere — this is the client-side check that catches it.
class UploadSizeMismatchException implements Exception {
  final int expectedSize;
  final int actualSize;

  const UploadSizeMismatchException(this.expectedSize, this.actualSize);

  @override
  String toString() =>
      'UploadSizeMismatchException: declared $expectedSize bytes, stream produced $actualSize';
}

/// Thin transport over StorageService's chunked-upload API. Orchestration
/// (creating the file node, recording the version) lives in the repository.
@lazySingleton
class FileUploadDataSource {
  /// Matches `ZDrive.BackupCli/Backup/Chunking.cs`'s `ChunkSize` — not
  /// because the server enforces a particular chunk size (it doesn't; each
  /// chunk's actual byte count is recorded as uploaded), but so uploads from
  /// this client and from the backup CLI produce comparably-shaped manifests.
  static const chunkSize = 4 * 1024 * 1024;

  final Dio _dio;

  FileUploadDataSource(this._dio);

  /// Opens an upload session for an already-created file node.
  Future<UploadSessionDto> initUpload(
    String fileId,
    String fileName,
    int totalChunks, {
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.post(
      ApiConstants.uploadInit,
      cancelToken: cancelToken,
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
    CancelToken? cancelToken,
  }) async {
    final chunkHash = await compute(_chunkHash, bytes);
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
      cancelToken: cancelToken,
    );
    ensureSuccess(response);
  }

  Future<UploadCompleteDto> completeUpload(String sessionId, {CancelToken? cancelToken}) async {
    final response = await _dio.post(
      '${ApiConstants.storage}/upload/$sessionId/complete',
      cancelToken: cancelToken,
    );
    return UploadCompleteDto.fromJson(unwrapMap(response));
  }

  /// Uploads [content] for [fileId] as a real multi-chunk session: splits it
  /// into [chunkSize] windows and streams each one from [content] straight
  /// into a PUT, without ever holding more than one chunk in memory — the
  /// counterpart to [downloadFile] below, which reassembles the same shape
  /// back. [sizeBytes] must be the exact byte count [content] will produce;
  /// it is used both to compute totalChunks up front (required by
  /// [initUpload] before any chunk is sent) and, once the stream is fully
  /// read, to check against the actual byte count. That second check matters
  /// because StorageService only verifies chunk *count* and index
  /// completeness ([UploadChunkCommandHandler], [CompleteUploadCommandHandler])
  /// — never byte length — so a stream that turns out shorter or longer than
  /// [sizeBytes] but still produces the same number of chunks (e.g. the
  /// picked file changed size between pick and upload) would otherwise
  /// complete silently with mismatched metadata instead of failing loudly.
  Future<UploadCompleteDto> uploadFile(
    String fileId,
    String fileName,
    Stream<List<int>> content,
    int sizeBytes, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
    final totalChunks = sizeBytes == 0 ? 1 : (sizeBytes / chunkSize).ceil();
    final session = await initUpload(fileId, fileName, totalChunks, cancelToken: cancelToken);

    try {
      if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
      var index = 0;
      var uploadedBytes = 0;
      await for (final chunk in _splitIntoChunks(content)) {
        if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
        await uploadChunk(
          session.sessionId,
          index,
          chunk,
          cancelToken: cancelToken,
          onProgress: onProgress == null
              ? null
              : (sent, total) {
                  if (sizeBytes > 0) {
                    onProgress((uploadedBytes + sent) / sizeBytes);
                  }
                },
        );
        uploadedBytes += chunk.length;
        if (sizeBytes > 0) {
          onProgress?.call((uploadedBytes / sizeBytes).clamp(0.0, 1.0));
        }
        index++;
      }

      if (uploadedBytes != sizeBytes) {
        throw UploadSizeMismatchException(sizeBytes, uploadedBytes);
      }

      if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
      return await completeUpload(session.sessionId, cancelToken: cancelToken);
    } catch (_) {
      await _abortUpload(session.sessionId);
      rethrow;
    }
  }

  Future<void> _abortUpload(String sessionId) async {
    // Cleanup must outlive the upload token, but must not stall the sync queue.
    final cleanupToken = CancelToken();
    final timeout = Timer(const Duration(seconds: 5), () {
      cleanupToken.cancel('Upload cleanup timed out');
    });
    try {
      await _dio.delete(
        '${ApiConstants.storage}/upload/$sessionId',
        cancelToken: cleanupToken,
      );
    } catch (_) {
      // Best effort: preserve the original upload/cancellation failure.
    } finally {
      timeout.cancel();
    }
  }

  /// Buffers [source] into exactly [chunkSize]-byte windows (the last one
  /// may be shorter), regardless of how the underlying platform stream
  /// happens to deliver bytes — file_picker reads web files in 1 MB windows
  /// and native files via dart:io's own buffer size, neither of which lines
  /// up with chunkSize on its own. A source that yields nothing produces one
  /// empty chunk, matching Chunking.cs's handling of zero-byte files (a
  /// session needs totalChunks > 0).
  static Stream<Uint8List> _splitIntoChunks(Stream<List<int>> source) async* {
    var buffer = Uint8List(chunkSize);
    var buffered = 0;
    var yielded = false;

    await for (final piece in source) {
      var offset = 0;
      while (offset < piece.length) {
        final available = chunkSize - buffered;
        final remaining = piece.length - offset;
        final count = remaining < available ? remaining : available;
        buffer.setRange(buffered, buffered + count, piece, offset);
        buffered += count;
        offset += count;
        if (buffered == chunkSize) {
          yield buffer;
          yielded = true;
          buffer = Uint8List(chunkSize);
          buffered = 0;
        }
      }
    }

    if (buffered > 0 || !yielded) {
      yield Uint8List.sublistView(buffer, 0, buffered);
    }
  }

  /// Fetches the chunk manifest for a file.
  Future<ManifestDto> getManifest(String fileId, {String? manifestHash}) async {
    final response = await _dio.get(
      '${ApiConstants.storage}/download/$fileId/manifest',
      queryParameters: manifestHash == null ? null : {'manifestHash': manifestHash},
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
  Future<Uint8List> downloadFile(String fileId, {String? manifestHash}) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in downloadFileStream(fileId, manifestHash: manifestHash)) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// Each yielded chunk has a valid SHA-256. Successful stream completion
  /// additionally proves index completeness and total byte length.
  Stream<Uint8List> downloadFileStream(String fileId, {String? manifestHash}) async* {
    final manifest = await getManifest(fileId, manifestHash: manifestHash);
    if (manifestHash != null && manifest.manifestHash != manifestHash) {
      throw StateError('Storage did not confirm the requested immutable manifest');
    }

    final chunks = [...manifest.chunks]
      ..sort((a, b) => a.index.compareTo(b.index));

    // The length check further down does not subsume this. Chunks are a fixed
    // size, so a manifest repeating one index — [{0,A},{0,A}] — assembles to
    // A||A at exactly the size A||B would have been, and every individual
    // chunk still hashes correctly. Indices must therefore be exactly
    // 0..n-1: unique, contiguous, zero-based.
    for (var i = 0; i < chunks.length; i++) {
      if (chunks[i].index != i) {
        throw ManifestChunkIndexException(i, chunks[i].index);
      }
    }

    var receivedSize = 0;
    for (final chunk in chunks) {
      final bytes = await downloadChunkBytes(fileId, chunk.hash);

      final actualHash = await compute(_chunkHash, bytes);
      if (actualHash != chunk.hash) {
        throw ChunkHashMismatchException(chunk.hash, actualHash);
      }
      receivedSize += bytes.length;
      if (receivedSize > manifest.totalSize) {
        throw ManifestSizeMismatchException(manifest.totalSize, receivedSize);
      }
      yield bytes;
    }

    // Per-chunk hashing only proves each chunk's own bytes are intact — it
    // says nothing about whether the *set* of chunks is complete. Together
    // with the index check above (which catches duplicates and gaps at equal
    // total size), this catches a truncated manifest and an empty chunk list.
    if (receivedSize != manifest.totalSize) {
      throw ManifestSizeMismatchException(manifest.totalSize, receivedSize);
    }
  }
}

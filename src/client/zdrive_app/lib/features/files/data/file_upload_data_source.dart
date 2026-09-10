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

class ManifestChunkIndexException implements Exception {
  final int expectedIndex;
  final int actualIndex;

  const ManifestChunkIndexException(this.expectedIndex, this.actualIndex);

  @override
  String toString() =>
      'ManifestChunkIndexException: expected chunk index $expectedIndex, got $actualIndex';
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

  /// Uploads [content] for [fileId] as a real multi-chunk session: splits it
  /// into [chunkSize] windows and streams each one from [content] straight
  /// into a PUT, without ever holding more than one chunk in memory — the
  /// counterpart to [downloadFile] below, which reassembles the same shape
  /// back. [sizeBytes] must be the exact byte count [content] will produce;
  /// it is only used to compute totalChunks up front (required by
  /// [initUpload] before any chunk is sent) — if the stream turns out
  /// shorter or longer, the chunk-index/completeness checks StorageService
  /// already does ([UploadChunkCommandHandler], [CompleteUploadCommandHandler])
  /// fail the upload loudly rather than silently storing a truncated file.
  Future<UploadCompleteDto> uploadFile(
    String fileId,
    String fileName,
    Stream<List<int>> content,
    int sizeBytes, {
    void Function(double progress)? onProgress,
  }) async {
    final totalChunks = sizeBytes == 0 ? 1 : (sizeBytes / chunkSize).ceil();
    final session = await initUpload(fileId, fileName, totalChunks);

    var index = 0;
    var uploadedBytes = 0;
    await for (final chunk in splitIntoChunks(content)) {
      await uploadChunk(
        session.sessionId,
        index,
        chunk,
        onProgress: onProgress == null
            ? null
            : (sent, total) {
                if (sizeBytes > 0) {
                  onProgress((uploadedBytes + sent) / sizeBytes);
                }
              },
      );
      uploadedBytes += chunk.length;
      index++;
    }

    return completeUpload(session.sessionId);
  }

  /// Buffers [source] into exactly [chunkSize]-byte windows (the last one
  /// may be shorter), regardless of how the underlying platform stream
  /// happens to deliver bytes — file_picker reads web files in 1 MB windows
  /// and native files via dart:io's own buffer size, neither of which lines
  /// up with chunkSize on its own. A source that yields nothing produces one
  /// empty chunk, matching Chunking.cs's handling of zero-byte files (a
  /// session needs totalChunks > 0).
  ///
  /// Public (not just used by [uploadFile] above) so folder upload can hash
  /// a local file's chunks the same way, to compare against a remote
  /// manifest before deciding whether to skip re-uploading it.
  static Stream<Uint8List> splitIntoChunks(Stream<List<int>> source) async* {
    final buffer = BytesBuilder(copy: false);
    var yielded = false;

    await for (final piece in source) {
      buffer.add(piece);
      while (buffer.length >= chunkSize) {
        final bytes = buffer.toBytes();
        buffer.clear();
        yield Uint8List.sublistView(bytes, 0, chunkSize);
        yielded = true;
        if (bytes.length > chunkSize) {
          buffer.add(bytes.sublist(chunkSize));
        }
      }
    }

    if (buffer.isNotEmpty || !yielded) {
      yield buffer.toBytes();
    }
  }

  /// Fetches the chunk manifest for a file.
  Future<ManifestDto> getManifest(String fileId) async {
    final response = await _dio.get(
      '${ApiConstants.storage}/download/$fileId/manifest',
    );
    return ManifestDto.fromJson(unwrapMap(response));
  }

  /// Like [getManifest], but returns null instead of throwing when [fileId]
  /// has no manifest yet (a file node with no completed upload) — folder
  /// upload's "is this already uploaded?" check needs to tell that apart
  /// from a real error.
  Future<ManifestDto?> tryGetManifest(String fileId) async {
    try {
      return await getManifest(fileId);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
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
    // says nothing about whether the *set* of chunks is complete. Together
    // with the index check above (which catches duplicates and gaps at equal
    // total size), this catches a truncated manifest and an empty chunk list.
    if (assembled.length != manifest.totalSize) {
      throw ManifestSizeMismatchException(manifest.totalSize, assembled.length);
    }
    return assembled;
  }
}

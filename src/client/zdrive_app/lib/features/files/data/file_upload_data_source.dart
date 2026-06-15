import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../../../core/network/api_constants.dart';
import '../../../core/network/api_envelope.dart';
import 'file_dtos.dart';

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
}

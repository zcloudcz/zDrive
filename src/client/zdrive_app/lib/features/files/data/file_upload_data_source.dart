// ignore_for_file: use_null_aware_elements

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../../../core/network/api_constants.dart';
import 'file_dtos.dart';

@lazySingleton
class FileUploadDataSource {
  final Dio _dio;

  FileUploadDataSource(this._dio);

  Future<UploadSessionDto> initUpload(
    String? parentId,
    String fileName,
    int totalChunks,
  ) async {
    final response = await _dio.post(
      ApiConstants.uploads,
      data: {
        if (parentId != null) 'parentId': parentId,
        'fileName': fileName,
        'totalChunks': totalChunks,
      },
    );
    return UploadSessionDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> uploadChunk(
    String sessionId,
    int chunkIndex,
    Uint8List bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final formData = FormData.fromMap({
      'chunkIndex': chunkIndex,
      'file': MultipartFile.fromBytes(bytes, filename: 'chunk_$chunkIndex'),
    });
    await _dio.post(
      '${ApiConstants.uploads}/$sessionId/chunks',
      data: formData,
      options: Options(headers: {'Content-Type': 'multipart/form-data'}),
      onSendProgress: onProgress,
    );
  }

  Future<UploadCompleteDto> completeUpload(String sessionId) async {
    final response = await _dio.post(
      '${ApiConstants.uploads}/$sessionId/complete',
    );
    return UploadCompleteDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<String> getDownloadUrl(String fileId) async {
    final response = await _dio.get(
      '${ApiConstants.files}/$fileId/download',
    );
    return response.data['url'] as String;
  }
}

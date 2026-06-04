import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import 'photo_dtos.dart';

@lazySingleton
class PhotoRemoteDataSource {
  final Dio _dio;

  PhotoRemoteDataSource(this._dio);

  Future<TimelineResultDto> getTimeline({
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (from != null) params['from'] = from.toIso8601String();
    if (to != null) params['to'] = to.toIso8601String();
    final response = await _dio.get('/photos/timeline', queryParameters: params);
    return TimelineResultDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PhotoDto> getPhoto(String id) async {
    final response = await _dio.get('/photos/$id');
    return PhotoDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<PhotoDto>> searchPhotos(String query, {int page = 1, int pageSize = 20}) async {
    final response = await _dio.get('/photos/search', queryParameters: {
      'q': query,
      'page': page,
      'pageSize': pageSize,
    });
    final items = (response.data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return items.map(PhotoDto.fromJson).toList();
  }

  Future<List<AlbumDto>> getAlbums() async {
    final response = await _dio.get('/albums');
    final items = (response.data as List?)?.cast<Map<String, dynamic>>() ?? [];
    return items.map(AlbumDto.fromJson).toList();
  }

  Future<AlbumDto> createAlbum(String name) async {
    final response = await _dio.post('/albums', data: {'name': name});
    return AlbumDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteAlbum(String id) async {
    await _dio.delete('/albums/$id');
  }

  Future<List<PhotoDto>> getAlbumPhotos(String albumId, {int page = 1, int pageSize = 20}) async {
    final response = await _dio.get('/albums/$albumId/photos', queryParameters: {
      'page': page,
      'pageSize': pageSize,
    });
    final items = (response.data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return items.map(PhotoDto.fromJson).toList();
  }

  Future<void> addPhotosToAlbum(String albumId, List<String> photoIds) async {
    await _dio.post('/albums/$albumId/photos', data: {'photoIds': photoIds});
  }

  Future<void> removePhotoFromAlbum(String albumId, String photoId) async {
    await _dio.delete('/albums/$albumId/photos/$photoId');
  }

  Future<List<MemoryDto>> getMemories() async {
    final response = await _dio.get('/memories');
    final items = (response.data as List?)?.cast<Map<String, dynamic>>() ?? [];
    return items.map(MemoryDto.fromJson).toList();
  }

  Future<void> dismissMemory(String id) async {
    await _dio.post('/memories/$id/dismiss');
  }
}

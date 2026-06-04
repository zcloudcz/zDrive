import 'package:injectable/injectable.dart';

import '../domain/photo.dart';
import '../domain/photo_repository.dart';
import 'photo_dtos.dart';
import 'photo_remote_data_source.dart';

@LazySingleton(as: PhotoRepository)
class PhotoRepositoryImpl implements PhotoRepository {
  final PhotoRemoteDataSource _remote;

  PhotoRepositoryImpl(this._remote);

  Photo _mapPhoto(PhotoDto dto) => Photo(
        id: dto.id,
        fileId: dto.fileId,
        takenAt: dto.takenAt != null ? DateTime.tryParse(dto.takenAt!) : null,
        lat: dto.lat,
        lng: dto.lng,
        cameraMake: dto.cameraMake,
        cameraModel: dto.cameraModel,
        width: dto.width,
        height: dto.height,
        processingStatus: dto.processingStatus,
        tags: dto.tags ?? [],
      );

  Album _mapAlbum(AlbumDto dto) => Album(
        id: dto.id,
        name: dto.name,
        type: dto.type,
        coverPhotoId: dto.coverPhotoId,
        photoCount: dto.photoCount,
        createdAt: DateTime.parse(dto.createdAt),
      );

  Memory _mapMemory(MemoryDto dto) => Memory(
        id: dto.id,
        type: dto.type,
        title: dto.title,
        dateFrom: dto.dateFrom != null ? DateTime.tryParse(dto.dateFrom!) : null,
        dateTo: dto.dateTo != null ? DateTime.tryParse(dto.dateTo!) : null,
        photoIds: dto.photoIds,
        seen: dto.seen,
      );

  @override
  Future<TimelineResult> getTimeline({DateTime? from, DateTime? to, int limit = 50, int offset = 0}) async {
    final result = await _remote.getTimeline(from: from, to: to, limit: limit, offset: offset);
    return TimelineResult(
      photos: result.photos.map(_mapPhoto).toList(),
      totalCount: result.totalCount,
    );
  }

  @override
  Future<Photo> getPhoto(String id) async => _mapPhoto(await _remote.getPhoto(id));

  @override
  Future<List<Photo>> searchPhotos(String query, {int page = 1, int pageSize = 20}) async {
    final dtos = await _remote.searchPhotos(query, page: page, pageSize: pageSize);
    return dtos.map(_mapPhoto).toList();
  }

  @override
  Future<List<Album>> getAlbums() async {
    final dtos = await _remote.getAlbums();
    return dtos.map(_mapAlbum).toList();
  }

  @override
  Future<Album> createAlbum(String name) async => _mapAlbum(await _remote.createAlbum(name));

  @override
  Future<void> deleteAlbum(String id) => _remote.deleteAlbum(id);

  @override
  Future<List<Photo>> getAlbumPhotos(String albumId, {int page = 1, int pageSize = 20}) async {
    final dtos = await _remote.getAlbumPhotos(albumId, page: page, pageSize: pageSize);
    return dtos.map(_mapPhoto).toList();
  }

  @override
  Future<void> addPhotosToAlbum(String albumId, List<String> photoIds) =>
      _remote.addPhotosToAlbum(albumId, photoIds);

  @override
  Future<void> removePhotoFromAlbum(String albumId, String photoId) =>
      _remote.removePhotoFromAlbum(albumId, photoId);

  @override
  Future<List<Memory>> getMemories() async {
    final dtos = await _remote.getMemories();
    return dtos.map(_mapMemory).toList();
  }

  @override
  Future<void> dismissMemory(String id) => _remote.dismissMemory(id);
}

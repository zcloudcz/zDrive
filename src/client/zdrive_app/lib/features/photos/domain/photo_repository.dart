import 'photo.dart';

class TimelineResult {
  final List<Photo> photos;
  final int totalCount;

  const TimelineResult({required this.photos, required this.totalCount});
}

abstract class PhotoRepository {
  Future<TimelineResult> getTimeline({
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
  });
  Future<Photo> getPhoto(String id);
  Future<List<Photo>> searchPhotos(String query, {int page = 1, int pageSize = 20});
  Future<List<Album>> getAlbums();
  Future<Album> createAlbum(String name);
  Future<void> deleteAlbum(String id);
  Future<List<Photo>> getAlbumPhotos(String albumId, {int page = 1, int pageSize = 20});
  Future<void> addPhotosToAlbum(String albumId, List<String> photoIds);
  Future<void> removePhotoFromAlbum(String albumId, String photoId);
  Future<List<Memory>> getMemories();
  Future<void> dismissMemory(String id);
}

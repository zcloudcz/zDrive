import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/photo.dart';
import '../domain/photo_repository.dart';

// Events
sealed class PhotosEvent extends Equatable {
  const PhotosEvent();
  @override
  List<Object?> get props => [];
}

final class LoadTimeline extends PhotosEvent {
  const LoadTimeline();
}

final class LoadMoreTimeline extends PhotosEvent {
  const LoadMoreTimeline();
}

final class LoadAlbums extends PhotosEvent {
  const LoadAlbums();
}

final class CreateAlbumRequested extends PhotosEvent {
  final String name;
  const CreateAlbumRequested(this.name);
  @override
  List<Object?> get props => [name];
}

final class DeleteAlbumRequested extends PhotosEvent {
  final String id;
  const DeleteAlbumRequested(this.id);
  @override
  List<Object?> get props => [id];
}

final class LoadAlbumPhotos extends PhotosEvent {
  final String albumId;
  const LoadAlbumPhotos(this.albumId);
  @override
  List<Object?> get props => [albumId];
}

// States
sealed class PhotosState extends Equatable {
  const PhotosState();
  @override
  List<Object?> get props => [];
}

final class PhotosInitial extends PhotosState {
  const PhotosInitial();
}

final class PhotosLoading extends PhotosState {
  const PhotosLoading();
}

final class TimelineLoaded extends PhotosState {
  final List<Photo> photos;
  final int totalCount;
  final bool hasMore;

  const TimelineLoaded({required this.photos, required this.totalCount, required this.hasMore});

  @override
  List<Object?> get props => [photos, totalCount, hasMore];
}

final class AlbumsLoaded extends PhotosState {
  final List<Album> albums;
  const AlbumsLoaded(this.albums);
  @override
  List<Object?> get props => [albums];
}

final class AlbumPhotosLoaded extends PhotosState {
  final String albumId;
  final String albumName;
  final List<Photo> photos;
  const AlbumPhotosLoaded({required this.albumId, required this.albumName, required this.photos});
  @override
  List<Object?> get props => [albumId, photos];
}

final class PhotosError extends PhotosState {
  final String message;
  const PhotosError(this.message);
  @override
  List<Object?> get props => [message];
}

// Bloc
class PhotosBloc extends Bloc<PhotosEvent, PhotosState> {
  final PhotoRepository _repository;
  List<Photo> _timelinePhotos = [];

  PhotosBloc({required PhotoRepository repository})
      : _repository = repository,
        super(const PhotosInitial()) {
    on<LoadTimeline>(_onLoadTimeline);
    on<LoadMoreTimeline>(_onLoadMore);
    on<LoadAlbums>(_onLoadAlbums);
    on<CreateAlbumRequested>(_onCreateAlbum);
    on<DeleteAlbumRequested>(_onDeleteAlbum);
    on<LoadAlbumPhotos>(_onLoadAlbumPhotos);
  }

  Future<void> _onLoadTimeline(LoadTimeline event, Emitter<PhotosState> emit) async {
    emit(const PhotosLoading());
    try {
      final result = await _repository.getTimeline(limit: 50, offset: 0);
      _timelinePhotos = result.photos;
      emit(TimelineLoaded(
        photos: _timelinePhotos,
        totalCount: result.totalCount,
        hasMore: _timelinePhotos.length < result.totalCount,
      ));
    } catch (e) {
      emit(PhotosError(e.toString()));
    }
  }

  Future<void> _onLoadMore(LoadMoreTimeline event, Emitter<PhotosState> emit) async {
    try {
      final result = await _repository.getTimeline(
        limit: 50,
        offset: _timelinePhotos.length,
      );
      _timelinePhotos = [..._timelinePhotos, ...result.photos];
      emit(TimelineLoaded(
        photos: _timelinePhotos,
        totalCount: result.totalCount,
        hasMore: _timelinePhotos.length < result.totalCount,
      ));
    } catch (e) {
      emit(PhotosError(e.toString()));
    }
  }

  Future<void> _onLoadAlbums(LoadAlbums event, Emitter<PhotosState> emit) async {
    emit(const PhotosLoading());
    try {
      final albums = await _repository.getAlbums();
      emit(AlbumsLoaded(albums));
    } catch (e) {
      emit(PhotosError(e.toString()));
    }
  }

  Future<void> _onCreateAlbum(CreateAlbumRequested event, Emitter<PhotosState> emit) async {
    try {
      await _repository.createAlbum(event.name);
      add(const LoadAlbums());
    } catch (e) {
      emit(PhotosError(e.toString()));
    }
  }

  Future<void> _onDeleteAlbum(DeleteAlbumRequested event, Emitter<PhotosState> emit) async {
    try {
      await _repository.deleteAlbum(event.id);
      add(const LoadAlbums());
    } catch (e) {
      emit(PhotosError(e.toString()));
    }
  }

  Future<void> _onLoadAlbumPhotos(LoadAlbumPhotos event, Emitter<PhotosState> emit) async {
    emit(const PhotosLoading());
    try {
      final photos = await _repository.getAlbumPhotos(event.albumId);
      final albums = await _repository.getAlbums();
      final album = albums.firstWhere((a) => a.id == event.albumId);
      emit(AlbumPhotosLoaded(albumId: event.albumId, albumName: album.name, photos: photos));
    } catch (e) {
      emit(PhotosError(e.toString()));
    }
  }
}

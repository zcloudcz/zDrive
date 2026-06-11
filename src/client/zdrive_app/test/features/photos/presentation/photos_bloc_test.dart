import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/photos/domain/photo.dart';
import 'package:zdrive_app/features/photos/domain/photo_repository.dart';
import 'package:zdrive_app/features/photos/presentation/photos_bloc.dart';

class MockPhotoRepository extends Mock implements PhotoRepository {}

void main() {
  late MockPhotoRepository mockRepository;

  final takenAt = DateTime(2024, 6, 1);
  Photo photo(String id) => Photo(id: id, fileId: 'file-$id', takenAt: takenAt);

  final album = Album(
    id: 'album-1',
    name: 'Holidays',
    type: 'manual',
    photoCount: 2,
    createdAt: DateTime(2024, 5, 1),
  );

  setUp(() {
    mockRepository = MockPhotoRepository();
  });

  PhotosBloc buildBloc() => PhotosBloc(repository: mockRepository);

  group('LoadTimeline', () {
    blocTest<PhotosBloc, PhotosState>(
      'emits [PhotosLoading, TimelineLoaded] with hasMore=true when more photos exist',
      build: buildBloc,
      setUp: () {
        when(() => mockRepository.getTimeline(limit: 50, offset: 0)).thenAnswer(
          (_) async => TimelineResult(photos: [photo('1'), photo('2')], totalCount: 5),
        );
      },
      act: (bloc) => bloc.add(const LoadTimeline()),
      expect: () => [
        const PhotosLoading(),
        TimelineLoaded(photos: [photo('1'), photo('2')], totalCount: 5, hasMore: true),
      ],
    );

    blocTest<PhotosBloc, PhotosState>(
      'emits hasMore=false when all photos are loaded',
      build: buildBloc,
      setUp: () {
        when(() => mockRepository.getTimeline(limit: 50, offset: 0)).thenAnswer(
          (_) async => TimelineResult(photos: [photo('1')], totalCount: 1),
        );
      },
      act: (bloc) => bloc.add(const LoadTimeline()),
      expect: () => [
        const PhotosLoading(),
        TimelineLoaded(photos: [photo('1')], totalCount: 1, hasMore: false),
      ],
    );

    blocTest<PhotosBloc, PhotosState>(
      'emits [PhotosLoading, PhotosError] when repository throws',
      build: buildBloc,
      setUp: () {
        when(() => mockRepository.getTimeline(limit: 50, offset: 0))
            .thenThrow(Exception('network down'));
      },
      act: (bloc) => bloc.add(const LoadTimeline()),
      expect: () => [
        const PhotosLoading(),
        isA<PhotosError>(),
      ],
    );
  });

  group('LoadMoreTimeline', () {
    blocTest<PhotosBloc, PhotosState>(
      'appends next page to already loaded photos',
      build: buildBloc,
      setUp: () {
        when(() => mockRepository.getTimeline(limit: 50, offset: 0)).thenAnswer(
          (_) async => TimelineResult(photos: [photo('1')], totalCount: 2),
        );
        when(() => mockRepository.getTimeline(limit: 50, offset: 1)).thenAnswer(
          (_) async => TimelineResult(photos: [photo('2')], totalCount: 2),
        );
      },
      act: (bloc) async {
        bloc.add(const LoadTimeline());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const LoadMoreTimeline());
      },
      expect: () => [
        const PhotosLoading(),
        TimelineLoaded(photos: [photo('1')], totalCount: 2, hasMore: true),
        TimelineLoaded(photos: [photo('1'), photo('2')], totalCount: 2, hasMore: false),
      ],
    );

    blocTest<PhotosBloc, PhotosState>(
      'emits PhotosError when loading next page fails',
      build: buildBloc,
      setUp: () {
        when(() => mockRepository.getTimeline(limit: 50, offset: 0))
            .thenThrow(Exception('network down'));
      },
      act: (bloc) => bloc.add(const LoadMoreTimeline()),
      expect: () => [isA<PhotosError>()],
    );
  });

  group('LoadAlbums', () {
    blocTest<PhotosBloc, PhotosState>(
      'emits [PhotosLoading, AlbumsLoaded] on success',
      build: buildBloc,
      setUp: () {
        when(() => mockRepository.getAlbums()).thenAnswer((_) async => [album]);
      },
      act: (bloc) => bloc.add(const LoadAlbums()),
      expect: () => [
        const PhotosLoading(),
        AlbumsLoaded([album]),
      ],
    );

    blocTest<PhotosBloc, PhotosState>(
      'emits [PhotosLoading, PhotosError] when repository throws',
      build: buildBloc,
      setUp: () {
        when(() => mockRepository.getAlbums()).thenThrow(Exception('boom'));
      },
      act: (bloc) => bloc.add(const LoadAlbums()),
      expect: () => [
        const PhotosLoading(),
        isA<PhotosError>(),
      ],
    );
  });

  group('CreateAlbumRequested', () {
    blocTest<PhotosBloc, PhotosState>(
      'creates album and reloads album list',
      build: buildBloc,
      setUp: () {
        when(() => mockRepository.createAlbum('Holidays')).thenAnswer((_) async => album);
        when(() => mockRepository.getAlbums()).thenAnswer((_) async => [album]);
      },
      act: (bloc) => bloc.add(const CreateAlbumRequested('Holidays')),
      expect: () => [
        const PhotosLoading(),
        AlbumsLoaded([album]),
      ],
      verify: (_) {
        verify(() => mockRepository.createAlbum('Holidays')).called(1);
      },
    );

    blocTest<PhotosBloc, PhotosState>(
      'emits PhotosError when creation fails',
      build: buildBloc,
      setUp: () {
        when(() => mockRepository.createAlbum(any())).thenThrow(Exception('boom'));
      },
      act: (bloc) => bloc.add(const CreateAlbumRequested('Holidays')),
      expect: () => [isA<PhotosError>()],
    );
  });

  group('DeleteAlbumRequested', () {
    blocTest<PhotosBloc, PhotosState>(
      'deletes album and reloads album list',
      build: buildBloc,
      setUp: () {
        when(() => mockRepository.deleteAlbum('album-1')).thenAnswer((_) async {});
        when(() => mockRepository.getAlbums()).thenAnswer((_) async => []);
      },
      act: (bloc) => bloc.add(const DeleteAlbumRequested('album-1')),
      expect: () => [
        const PhotosLoading(),
        const AlbumsLoaded([]),
      ],
      verify: (_) {
        verify(() => mockRepository.deleteAlbum('album-1')).called(1);
      },
    );
  });

  group('LoadAlbumPhotos', () {
    blocTest<PhotosBloc, PhotosState>(
      'emits [PhotosLoading, AlbumPhotosLoaded] with the album name',
      build: buildBloc,
      setUp: () {
        when(() => mockRepository.getAlbumPhotos('album-1'))
            .thenAnswer((_) async => [photo('1'), photo('2')]);
        when(() => mockRepository.getAlbums()).thenAnswer((_) async => [album]);
      },
      act: (bloc) => bloc.add(const LoadAlbumPhotos('album-1')),
      expect: () => [
        const PhotosLoading(),
        AlbumPhotosLoaded(
          albumId: 'album-1',
          albumName: 'Holidays',
          photos: [photo('1'), photo('2')],
        ),
      ],
    );

    blocTest<PhotosBloc, PhotosState>(
      'emits PhotosError when album photos cannot be loaded',
      build: buildBloc,
      setUp: () {
        when(() => mockRepository.getAlbumPhotos(any())).thenThrow(Exception('boom'));
      },
      act: (bloc) => bloc.add(const LoadAlbumPhotos('album-1')),
      expect: () => [
        const PhotosLoading(),
        isA<PhotosError>(),
      ],
    );
  });
}

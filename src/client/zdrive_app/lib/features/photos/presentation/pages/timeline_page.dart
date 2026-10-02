import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zdrive_app/core/network/error_message.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../domain/photo.dart';
import '../photos_bloc.dart';

class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PhotosBloc, PhotosState>(
      builder: (context, state) {
        if (state is PhotosLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is PhotosError) {
          return Center(
            child: Text(describeError(state.error, AppLocalizations.of(context)!)),
          );
        }
        if (state is TimelineLoaded) {
          if (state.photos.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_library_outlined, size: 64,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(AppLocalizations.of(context)!.noPhotos,
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            );
          }
          return _TimelineGrid(photos: state.photos, hasMore: state.hasMore);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _TimelineGrid extends StatelessWidget {
  final List<Photo> photos;
  final bool hasMore;

  const _TimelineGrid({required this.photos, required this.hasMore});

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (hasMore &&
            notification is ScrollEndNotification &&
            notification.metrics.extentAfter < 200) {
          context.read<PhotosBloc>().add(const LoadMoreTimeline());
        }
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(2),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: photos.length,
        itemBuilder: (context, index) {
          final photo = photos[index];
          return _PhotoThumbnail(photo: photo);
        },
      ),
    );
  }
}

class _PhotoThumbnail extends StatelessWidget {
  final Photo photo;

  const _PhotoThumbnail({required this.photo});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Photo detail view — Phase 6
      },
      // No thumbnail is rendered here yet on purpose. The backend now generates
      // 256/1024 WebP thumbnails (ingest worker) and serves them, authorized,
      // from GET /api/v1/photos/{id}/thumbnail/{size}, but that needs the JWT
      // header, so a plain Image.network will not do and loading full-resolution
      // originals into a scrolling grid is a performance anti-pattern. Wire this
      // up with an authenticated image provider once the ingest PR (#81) is deployed.
      child: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.image,
            size: 32,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

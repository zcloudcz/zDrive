import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../../../core/di/injection.dart';
import '../../domain/photo_repository.dart';
import '../photos_bloc.dart';
import 'timeline_page.dart';

class PhotosTab extends StatelessWidget {
  const PhotosTab({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return BlocProvider(
      create: (_) => PhotosBloc(repository: getIt<PhotoRepository>())..add(const LoadTimeline()),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(l10n.photos),
            actions: [
              IconButton(
                icon: const Icon(Icons.photo_album_outlined),
                tooltip: l10n.albums,
                onPressed: () => context.go('/home/photos/albums'),
              ),
            ],
          ),
          body: const TimelinePage(),
        ),
      ),
    );
  }
}

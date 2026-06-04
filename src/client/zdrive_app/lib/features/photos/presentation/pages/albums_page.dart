import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../photos_bloc.dart';

class AlbumsPage extends StatelessWidget {
  const AlbumsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.albums)),
      body: BlocBuilder<PhotosBloc, PhotosState>(
        builder: (context, state) {
          if (state is PhotosLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is AlbumsLoaded) {
            if (state.albums.isEmpty) {
              return Center(child: Text(l10n.noAlbums));
            }
            return ListView.builder(
              itemCount: state.albums.length,
              itemBuilder: (context, index) {
                final album = state.albums[index];
                return ListTile(
                  leading: const Icon(Icons.photo_album),
                  title: Text(album.name),
                  subtitle: Text('${album.photoCount} ${l10n.photos.toLowerCase()}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      context.read<PhotosBloc>().add(DeleteAlbumRequested(album.id));
                    },
                  ),
                  onTap: () {
                    context.read<PhotosBloc>().add(LoadAlbumPhotos(album.id));
                  },
                );
              },
            );
          }
          return const SizedBox.shrink();
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateAlbumDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showCreateAlbumDialog(BuildContext context) {
    final controller = TextEditingController();
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.newAlbum),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: l10n.albumName),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                context.read<PhotosBloc>().add(CreateAlbumRequested(controller.text.trim()));
                Navigator.pop(ctx);
              }
            },
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }
}

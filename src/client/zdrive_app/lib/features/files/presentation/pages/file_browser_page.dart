import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/events/remote_file_change_notifier.dart';
import '../../../../core/network/error_message.dart';
import '../../data/file_saver.dart';
import '../../domain/file_item.dart';
import '../../domain/file_repository.dart';
import '../../domain/use_cases/create_folder_use_case.dart';
import '../../domain/use_cases/delete_file_use_case.dart';
import '../../domain/use_cases/list_files_use_case.dart';
import '../../domain/use_cases/search_files_use_case.dart';
import '../../domain/use_cases/upload_file_use_case.dart';
import '../file_browser_bloc.dart';
import '../widgets/create_folder_dialog.dart';
import '../widgets/file_grid_item.dart';
import '../widgets/file_list_item.dart';
import '../widgets/rename_dialog.dart';
import '../widgets/share_dialog.dart';
import '../widgets/version_history_dialog.dart';

class FileBrowserPage extends StatelessWidget {
  final String? folderId;

  const FileBrowserPage({super.key, this.folderId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => FileBrowserBloc(
        listFiles: getIt<ListFilesUseCase>(),
        createFolder: getIt<CreateFolderUseCase>(),
        deleteFile: getIt<DeleteFileUseCase>(),
        searchFiles: getIt<SearchFilesUseCase>(),
        fileRepository: getIt<FileRepository>(),
        remoteChangeNotifier: getIt<RemoteFileChangeNotifier>(),
      )..add(LoadFolder(folderId: folderId)),
      child: const _FileBrowserView(),
    );
  }
}

class _FileBrowserView extends StatelessWidget {
  const _FileBrowserView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return BlocConsumer<FileBrowserBloc, FileBrowserState>(
      listener: (context, state) {
        if (state is FileBrowserError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: _buildAppBar(context, state, l10n),
          body: _buildBody(context, state, l10n),
          floatingActionButton: _buildFab(context, l10n),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    FileBrowserState state,
    AppLocalizations l10n,
  ) {
    final breadcrumbs = state is FileBrowserLoaded ? state.breadcrumbs : null;
    final viewMode = state is FileBrowserLoaded ? state.viewMode : null;

    return AppBar(
      title: breadcrumbs != null
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < breadcrumbs.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.chevron_right, size: 18),
                      ),
                    InkWell(
                      onTap: () {
                        final item = breadcrumbs[i];
                        if (item.id == null) {
                          context.go('/home/files');
                        } else {
                          context.go('/home/files/folder/${item.id}');
                        }
                      },
                      child: Text(
                        breadcrumbs[i].name,
                        style: i == breadcrumbs.length - 1
                            ? Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)
                            : Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ],
              ),
            )
          : Text(l10n.files),
      actions: [
        // Pull-to-refresh (RefreshIndicator, below) is not discoverable with
        // a mouse — this gives desktop users an equally-obvious manual
        // refresh, reusing the same RefreshFiles event.
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: l10n.refresh,
          onPressed: () => context.read<FileBrowserBloc>().add(const RefreshFiles()),
        ),
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: l10n.search,
          onPressed: () => context.go('/home/files/search'),
        ),
        if (viewMode != null)
          IconButton(
            icon: Icon(
              viewMode == FileViewMode.list
                  ? Icons.grid_view
                  : Icons.view_list,
            ),
            onPressed: () {
              context.read<FileBrowserBloc>().add(const ToggleViewMode());
            },
          ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: l10n.trash,
          onPressed: () => context.go('/home/files/trash'),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    FileBrowserState state,
    AppLocalizations l10n,
  ) {
    if (state is FileBrowserLoading || state is FileBrowserInitial) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is FileBrowserLoaded) {
      if (state.files.isEmpty) {
        return _buildEmptyState(context, l10n);
      }

      return RefreshIndicator(
        onRefresh: () async {
          context.read<FileBrowserBloc>().add(const RefreshFiles());
        },
        child: state.viewMode == FileViewMode.list
            ? _buildListView(context, state)
            : _buildGridView(context, state),
      );
    }

    if (state is FileBrowserError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.message),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                context.read<FileBrowserBloc>().add(const RefreshFiles());
              },
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(l10n.noFiles, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _buildListView(BuildContext context, FileBrowserLoaded state) {
    return ListView.builder(
      itemCount: state.files.length,
      itemBuilder: (context, index) {
        final file = state.files[index];
        return FileListItem(
          file: file,
          onTap: () => _onFileTap(context, file),
          onRename: () => _showRenameDialog(context, file),
          onDelete: () => _showDeleteConfirm(context, file),
          onShare: () => _showShareDialog(context, file),
          onVersions: () => _showVersionHistoryDialog(context, file),
        );
      },
    );
  }

  Widget _buildGridView(BuildContext context, FileBrowserLoaded state) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: state.files.length,
      itemBuilder: (context, index) {
        final file = state.files[index];
        return FileGridItem(
          file: file,
          onTap: () => _onFileTap(context, file),
          onRename: () => _showRenameDialog(context, file),
          onDelete: () => _showDeleteConfirm(context, file),
          onShare: () => _showShareDialog(context, file),
          onVersions: () => _showVersionHistoryDialog(context, file),
        );
      },
    );
  }

  Widget _buildFab(BuildContext context, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.small(
          heroTag: 'upload',
          onPressed: () => _pickAndUploadFile(context),
          child: const Icon(Icons.upload_file),
        ),
        const SizedBox(height: 8),
        FloatingActionButton(
          heroTag: 'newFolder',
          onPressed: () => _showCreateFolderDialog(context),
          child: const Icon(Icons.create_new_folder),
        ),
      ],
    );
  }

  void _onFileTap(BuildContext context, FileItem file) {
    if (file.isFolder) {
      context.go('/home/files/folder/${file.id}');
      return;
    }
    _downloadFile(context, file);
  }

  Future<void> _downloadFile(BuildContext context, FileItem file) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final l10n = AppLocalizations.of(context)!;
    final progressRoute = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(l10n.downloadProgress),
          content: Row(
            children: [
              CircularProgressIndicator(semanticsLabel: l10n.downloadProgress),
              const SizedBox(width: 24),
              Expanded(child: Text(file.name)),
            ],
          ),
        ),
      ),
    );
    navigator.push(progressRoute);
    try {
      // Paint feedback before opening the native save dialog or starting I/O.
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted || !progressRoute.isActive) return;
      await downloadFile(file, getIt<FileRepository>());
    } catch (e) {
      if (context.mounted && messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(describeError(e, l10n))));
      }
    } finally {
      if (navigator.mounted && progressRoute.isActive) {
        navigator.removeRoute(progressRoute);
      }
    }
  }

  Future<void> _showCreateFolderDialog(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const CreateFolderDialog(),
    );
    if (name != null && context.mounted) {
      context.read<FileBrowserBloc>().add(CreateFolder(name));
    }
  }

  Future<void> _showRenameDialog(BuildContext context, FileItem file) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => RenameDialog(currentName: file.name),
    );
    if (newName != null && newName != file.name && context.mounted) {
      context.read<FileBrowserBloc>().add(RenameFile(file.id, newName));
    }
  }

  Future<void> _showDeleteConfirm(BuildContext context, FileItem file) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.confirmDelete),
        content: Text(file.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<FileBrowserBloc>().add(DeleteFile(file.id));
    }
  }

  void _showShareDialog(BuildContext context, FileItem file) {
    final repo = getIt<FileRepository>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ShareDialog(
        fileId: file.id,
        onShare: repo.createShare,
      ),
    );
  }

  void _showVersionHistoryDialog(BuildContext context, FileItem file) {
    final repo = getIt<FileRepository>();
    showDialog(
      context: context,
      builder: (_) => VersionHistoryDialog(
        fileId: file.id,
        fileName: file.name,
        onLoadVersions: repo.getVersions,
        onRestore: repo.restoreVersion,
      ),
    );
  }

  Future<void> _pickAndUploadFile(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    // withData: false + withReadStream: true streams the file from disk (or,
    // on web, from the browser's File object in 1 MB windows) instead of
    // loading it whole into memory — verified against file_picker 8.3.7's
    // source for every platform this app targets (Windows/macOS/Linux via
    // dart:io File.openRead(), web via FileReader + Blob.slice()); the
    // package docs don't spell this out.
    final result = await FilePicker.platform.pickFiles(
      withData: false,
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) return;

    final pickedFile = result.files.first;
    final stream = pickedFile.readStream;
    if (stream == null) return;

    if (!context.mounted) return;

    final bloc = context.read<FileBrowserBloc>();
    final currentState = bloc.state;
    final parentId =
        currentState is FileBrowserLoaded ? currentState.currentFolderId : null;

    final uploadUseCase = getIt<UploadFileUseCase>();

    // Show upload progress snackbar
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(l10n.uploadProgress),
          ],
        ),
        duration: const Duration(minutes: 5),
      ),
    );

    try {
      await uploadUseCase(
        parentId,
        pickedFile.name,
        stream,
        pickedFile.size,
      );
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.uploadComplete)),
      );
      if (context.mounted) {
        bloc.add(const RefreshFiles());
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }
}

/// Hands [file]'s lazy verified stream to the platform saver. Desktop can
/// cancel its save dialog without subscribing or starting network requests;
/// mobile and web savers collect bytes as required by their platform APIs.
///
/// A top-level function (rather than inlined in [_FileBrowserView]) so it
/// can be unit tested without a full widget/DI/router harness; [save]
/// defaults to the real platform saver and is overridden in tests.
@visibleForTesting
Future<void> downloadFile(
  FileItem file,
  FileRepository repository, {
  Future<void> Function(String fileName, Stream<Uint8List> content) save = saveFileStream,
}) async {
  await save(file.name, repository.downloadFileStream(file.id));
}

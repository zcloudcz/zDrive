import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/diagnostics/diagnostics.dart';
import '../../../../core/events/remote_file_change_notifier.dart';
import '../../../../core/network/error_message.dart';
import '../../../sync/domain/sync_mirror_repository.dart';
import '../../../sync/presentation/offline_status_cubit.dart';
import '../../../sync/presentation/sync_bloc.dart';
import '../../data/file_saver.dart';
import '../../../sync/domain/sync_mirror_entry.dart';
import '../../domain/file_item.dart';
import '../../domain/file_repository.dart';
import '../../domain/use_cases/create_folder_use_case.dart';
import '../../domain/use_cases/delete_file_use_case.dart';
import '../../domain/use_cases/list_files_use_case.dart';
import '../../domain/use_cases/search_files_use_case.dart';
import '../../domain/use_cases/upload_file_use_case.dart';
import '../file_browser_bloc.dart';
import '../widgets/create_folder_dialog.dart';
import '../widgets/file_actions_toolbar.dart';
import '../widgets/file_grid_item.dart';
import '../widgets/file_list_item.dart';
import '../widgets/rename_dialog.dart';
import '../widgets/share_dialog.dart';
import '../widgets/version_history_dialog.dart';
import 'file_preview_page.dart';

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
      // The per-item "on this device" state exists only where the desktop sync
      // engine does — the app shell provides a SyncBloc only there (see
      // buildSyncShellProvider); elsewhere the view finds no cubit and shows
      // none.
      child: _maybeRead<SyncBloc>(context) != null
          ? BlocProvider(
              create: (_) => OfflineStatusCubit(getIt<SyncMirrorRepository>()),
              child: const FileBrowserView(),
            )
          : const FileBrowserView(),
    );
  }
}

/// The desktop-only providers may be absent (web, mobile, most widget tests);
/// same ProviderNotFoundException pattern as sync_page.dart.
T? _maybeRead<T extends Object>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}

/// Public only so a widget test can pump the real view under a MockBloc,
/// without the page's get_it wiring.
@visibleForTesting
class FileBrowserView extends StatefulWidget {
  const FileBrowserView({super.key});

  @override
  State<FileBrowserView> createState() => _FileBrowserViewState();
}

class _FileBrowserViewState extends State<FileBrowserView> {
  // FileBrowserLoading/Initial carry no view mode of their own, so the
  // loading skeleton would otherwise always fall back to the list shape even
  // when the user was last looking at the grid — remember the last loaded
  // mode instead (spec 4.5: "list- or grid-shaped according to the last
  // known view mode if available else list").
  FileViewMode _lastViewMode = FileViewMode.list;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final offline = _maybeRead<OfflineStatusCubit>(context);
    // Subscribes this view to status changes; _offlineArgs then just reads.
    if (offline != null) context.watch<OfflineStatusCubit>();

    final browser = BlocConsumer<FileBrowserBloc, FileBrowserState>(
      listener: (context, state) {
        if (state is FileBrowserError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
        if (state is FileBrowserLoaded) {
          _lastViewMode = state.viewMode;
          offline?.load(state.files, parentId: state.currentFolderId);
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: _buildAppBar(context, state, l10n),
          body: _buildBody(context, state, l10n),
        );
      },
    );
    final syncBloc = _maybeRead<SyncBloc>(context);
    if (offline == null || syncBloc == null) return browser;

    // A keep/free-up action finished: re-read the markers, and tell the user
    // about files free-up had to leave alone.
    return BlocListener<SyncBloc, SyncState>(
      listenWhen: (previous, current) =>
          previous is SyncLoaded &&
          current is SyncLoaded &&
          previous.offlineRevision != current.offlineRevision,
      listener: (context, state) {
        offline.refresh();
        final skipped = state is SyncLoaded ? state.freeUpSkipped : 0;
        final keptPinned = state is SyncLoaded ? state.freeUpKeptPinned : 0;
        if (skipped > 0 || keptPinned > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text([
                if (skipped > 0) l10n.freeUpSkippedUnsynced(skipped),
                if (keptPinned > 0) l10n.freeUpKeptPinned(keptPinned),
              ].join('\n')),
            ),
          );
        }
      },
      child: browser,
    );
  }

  /// Marker and menu actions for [file]; all null unless both the desktop
  /// sync bloc and the status cubit are provided (web/mobile: nothing shown).
  ({OfflineStatus? status, VoidCallback? keep, VoidCallback? freeUp}) _offlineArgs(
    BuildContext context,
    FileItem file,
  ) {
    final offline = _maybeRead<OfflineStatusCubit>(context);
    final syncBloc = _maybeRead<SyncBloc>(context);
    if (offline == null || syncBloc == null) return (status: null, keep: null, freeUp: null);
    return (
      // A row the cubit has not answered for yet (first frame of a listing)
      // shows no marker instead of a wrong "cloud only".
      status: offline.state[file.id],
      keep: () => syncBloc.add(KeepOnDeviceRequested(file.id)),
      freeUp: () => syncBloc.add(FreeUpSpaceRequested(file.id)),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    FileBrowserState state,
    AppLocalizations l10n,
  ) {
    final breadcrumbs = state is FileBrowserLoaded ? state.breadcrumbs : null;

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
                        // Current segment stands out at full onSurface weight;
                        // parents are subdued onSurfaceVariant (spec 4.5).
                        style: i == breadcrumbs.length - 1
                            ? Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)
                            : Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                      ),
                    ),
                  ],
                ],
              ),
            )
          : Text(l10n.files),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: l10n.search,
          onPressed: () => context.go('/home/files/search'),
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
    return Column(
      children: [
        FileActionsToolbar(
          viewMode: state is FileBrowserLoaded ? state.viewMode : null,
          onUploadFile: () => _pickAndUploadFile(context),
          onCreateFolder: () => _showCreateFolderDialog(context),
        ),
        Expanded(child: _buildContent(context, state, l10n)),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    FileBrowserState state,
    AppLocalizations l10n,
  ) {
    if (state is FileBrowserLoading || state is FileBrowserInitial) {
      return _buildLoadingSkeleton(context, _lastViewMode);
    }

    if (state is FileBrowserLoaded) {
      // RefreshIndicator wraps both branches, not just the non-empty one, so
      // pull-to-refresh still works on an empty folder (spec 4.5/PR5).
      return RefreshIndicator(
        onRefresh: () async {
          context.read<FileBrowserBloc>().add(const RefreshFiles());
        },
        child: state.files.isEmpty
            ? _buildEmptyState(context, l10n)
            : state.viewMode == FileViewMode.list
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
    final colorScheme = Theme.of(context).colorScheme;
    // A plain Center would give RefreshIndicator nothing scrollable to pull
    // against, so pull-to-refresh works on an empty folder too — a
    // ListView with AlwaysScrollableScrollPhysics, sized to fill the
    // viewport, gives it that without changing how it looks.
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: colorScheme.primaryContainer,
                      child: Icon(
                        Icons.folder_open,
                        size: 44,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.noFiles,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.noFilesBody,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // Same "+ New" menu as the toolbar — the empty state
                    // repeats the primary action, it doesn't invent a new one.
                    NewItemMenuButton(
                      onUploadFile: () => _pickAndUploadFile(context),
                      onCreateFolder: () => _showCreateFolderDialog(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Shared by the real grid and its loading skeleton so the two can never
  // drift into different tile layouts (review round 2, finding 4).
  static const _gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 180,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    childAspectRatio: 0.85,
  );

  /// Skeleton rows/tiles shown instead of a spinner while the folder loads
  /// (spec 4.5). Plain themed containers, no shimmer package; nothing here
  /// animates, so there is nothing to guard behind
  /// `MediaQuery.disableAnimations`.
  Widget _buildLoadingSkeleton(BuildContext context, FileViewMode viewMode) {
    return ExcludeSemantics(
      child: viewMode == FileViewMode.list
          ? ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 6,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, _) => _skeletonRow(context),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: _gridDelegate,
              itemCount: 6,
              itemBuilder: (context, _) => _skeletonTile(context),
            ),
    );
  }

  Widget _skeletonRow(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHigh;
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.6,
                    child: Container(height: 16, color: color),
                  ),
                  const SizedBox(height: 8),
                  FractionallySizedBox(
                    widthFactor: 0.4,
                    child: Container(height: 12, color: color),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skeletonTile(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHigh;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(child: Container(color: color)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.6,
                child: Container(height: 12, color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListView(BuildContext context, FileBrowserLoaded state) {
    return ListView.separated(
      // A short listing (fewer rows than the viewport) is otherwise
      // non-scrollable, and RefreshIndicator needs an overscroll gesture to
      // fire — without this, pull-to-refresh silently does nothing on a
      // folder with only a couple of files (review round 2, finding 1).
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: state.files.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final file = state.files[index];
        final offline = _offlineArgs(context, file);
        return FileListItem(
          file: file,
          offlineStatus: offline.status,
          onKeepOnDevice: offline.keep,
          onFreeUp: offline.freeUp,
          onTap: () => _onFileTap(context, file),
          onDownload: () => _downloadFile(context, file),
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
      // Same reasoning as _buildListView above — a short grid must still be
      // pull-to-refreshable.
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: _gridDelegate,
      itemCount: state.files.length,
      itemBuilder: (context, index) {
        final file = state.files[index];
        final offline = _offlineArgs(context, file);
        return FileGridItem(
          file: file,
          offlineStatus: offline.status,
          onKeepOnDevice: offline.keep,
          onFreeUp: offline.freeUp,
          onTap: () => _onFileTap(context, file),
          onDownload: () => _downloadFile(context, file),
          onRename: () => _showRenameDialog(context, file),
          onDelete: () => _showDeleteConfirm(context, file),
          onShare: () => _showShareDialog(context, file),
          onVersions: () => _showVersionHistoryDialog(context, file),
        );
      },
    );
  }

  void _onFileTap(BuildContext context, FileItem file) {
    if (file.isFolder) {
      context.go('/home/files/folder/${file.id}');
      return;
    }
    FilePreviewPage.show(
      context,
      fileName: file.name,
      mimeType: file.mimeType,
      sizeBytes: file.sizeBytes,
      openContent: () => getIt<FileRepository>().downloadFileStream(file.id),
      onDownload: (previewContext, loadedBytes) =>
          _downloadFile(previewContext, file, loadedBytes: loadedBytes),
      onShare: (previewContext) => _showShareDialog(previewContext, file),
    );
  }

  Future<void> _downloadFile(
    BuildContext context,
    FileItem file, {
    Uint8List? loadedBytes,
  }) async {
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
      await downloadFile(file, getIt<FileRepository>(), loadedBytes: loadedBytes);
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
    Diagnostics.event('file.delete.dialog_opened');
    final l10n = AppLocalizations.of(context)!;
    var dialogClosed = false;
    void closeDialog(BuildContext dialogContext, bool confirmed) {
      if (dialogClosed) return;
      dialogClosed = true;
      Navigator.of(dialogContext).pop(confirmed);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.confirmDelete),
        content: Text(file.name),
        actions: [
          TextButton(
            onPressed: () => closeDialog(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => closeDialog(dialogContext, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    Diagnostics.event(
      confirmed == true
          ? 'file.delete.dialog_confirmed'
          : 'file.delete.dialog_cancelled',
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
  Uint8List? loadedBytes,
}) async {
  // Bytes already loaded (and verified) by the preview are saved as they are
  // instead of downloading the file a second time.
  await save(
    file.name,
    loadedBytes != null ? Stream.value(loadedBytes) : repository.downloadFileStream(file.id),
  );
}

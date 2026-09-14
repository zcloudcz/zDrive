import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/events/remote_file_change_notifier.dart';
import '../domain/file_item.dart';
import '../domain/use_cases/create_folder_use_case.dart';
import '../domain/use_cases/delete_file_use_case.dart';
import '../domain/use_cases/list_files_use_case.dart';
import '../domain/use_cases/search_files_use_case.dart';
import '../domain/file_repository.dart';

// --- Events ---

sealed class FileBrowserEvent extends Equatable {
  const FileBrowserEvent();

  @override
  List<Object?> get props => [];
}

final class LoadFolder extends FileBrowserEvent {
  final String? folderId;

  const LoadFolder({this.folderId});

  @override
  List<Object?> get props => [folderId];
}

final class CreateFolder extends FileBrowserEvent {
  final String name;

  const CreateFolder(this.name);

  @override
  List<Object?> get props => [name];
}

final class DeleteFile extends FileBrowserEvent {
  final String id;

  const DeleteFile(this.id);

  @override
  List<Object?> get props => [id];
}

final class RenameFile extends FileBrowserEvent {
  final String id;
  final String newName;

  const RenameFile(this.id, this.newName);

  @override
  List<Object?> get props => [id, newName];
}

final class ToggleViewMode extends FileBrowserEvent {
  const ToggleViewMode();
}

final class RefreshFiles extends FileBrowserEvent {
  const RefreshFiles();
}

final class SearchFiles extends FileBrowserEvent {
  final String query;

  const SearchFiles(this.query);

  @override
  List<Object?> get props => [query];
}

// --- View Mode ---

enum FileViewMode { list, grid }

// --- Breadcrumb ---

class BreadcrumbItem extends Equatable {
  final String? id;
  final String name;

  const BreadcrumbItem({this.id, required this.name});

  @override
  List<Object?> get props => [id, name];
}

// --- States ---

sealed class FileBrowserState extends Equatable {
  const FileBrowserState();

  @override
  List<Object?> get props => [];
}

final class FileBrowserInitial extends FileBrowserState {
  const FileBrowserInitial();
}

final class FileBrowserLoading extends FileBrowserState {
  const FileBrowserLoading();
}

final class FileBrowserLoaded extends FileBrowserState {
  final List<FileItem> files;
  final String? currentFolderId;
  final List<BreadcrumbItem> breadcrumbs;
  final FileViewMode viewMode;

  const FileBrowserLoaded({
    required this.files,
    this.currentFolderId,
    required this.breadcrumbs,
    this.viewMode = FileViewMode.list,
  });

  FileBrowserLoaded copyWith({
    List<FileItem>? files,
    String? Function()? currentFolderId,
    List<BreadcrumbItem>? breadcrumbs,
    FileViewMode? viewMode,
  }) {
    return FileBrowserLoaded(
      files: files ?? this.files,
      currentFolderId:
          currentFolderId != null ? currentFolderId() : this.currentFolderId,
      breadcrumbs: breadcrumbs ?? this.breadcrumbs,
      viewMode: viewMode ?? this.viewMode,
    );
  }

  @override
  List<Object?> get props => [files, currentFolderId, breadcrumbs, viewMode];
}

final class FileBrowserError extends FileBrowserState {
  final String message;

  const FileBrowserError(this.message);

  @override
  List<Object?> get props => [message];
}

// --- Bloc ---

class FileBrowserBloc extends Bloc<FileBrowserEvent, FileBrowserState> {
  final ListFilesUseCase _listFiles;
  final CreateFolderUseCase _createFolder;
  final DeleteFileUseCase _deleteFile;
  final SearchFilesUseCase _searchFiles;
  final FileRepository _fileRepository;
  StreamSubscription<void>? _remoteChangeSubscription;

  FileViewMode _viewMode = FileViewMode.list;
  String? _currentFolderId;
  List<BreadcrumbItem> _breadcrumbs = [const BreadcrumbItem(name: 'Home')];

  FileBrowserBloc({
    required ListFilesUseCase listFiles,
    required CreateFolderUseCase createFolder,
    required DeleteFileUseCase deleteFile,
    required SearchFilesUseCase searchFiles,
    required FileRepository fileRepository,
    required RemoteFileChangeNotifier remoteChangeNotifier,
  })  : _listFiles = listFiles,
        _createFolder = createFolder,
        _deleteFile = deleteFile,
        _searchFiles = searchFiles,
        _fileRepository = fileRepository,
        super(const FileBrowserInitial()) {
    on<LoadFolder>(_onLoadFolder);
    on<CreateFolder>(_onCreateFolder);
    on<DeleteFile>(_onDeleteFile);
    on<RenameFile>(_onRenameFile);
    on<ToggleViewMode>(_onToggleViewMode);
    on<RefreshFiles>(_onRefreshFiles);
    on<SearchFiles>(_onSearchFiles);
    // Only while a folder is actually loaded (not mid-load/error) — a change
    // signal arriving during an in-flight load would otherwise pile a second,
    // overlapping LoadFolder on top of it.
    _remoteChangeSubscription = remoteChangeNotifier.changes.listen((_) {
      if (state is FileBrowserLoaded) add(const RefreshFiles());
    });
  }

  Future<void> _onLoadFolder(
    LoadFolder event,
    Emitter<FileBrowserState> emit,
  ) async {
    // Only blank the list when there is nothing useful on screen to keep, or
    // when the folder actually changes. Reloading the folder already shown —
    // which a remote change signal now does on its own, every time sync pulls
    // something (2s after a watch event, or on the 30s poll) — must not swap
    // the list for a spinner: that rebuild drops the ListView and its
    // ScrollPosition with it, so a user reading item 40 of 200 would get
    // yanked back to the top by a background refresh they did not ask for.
    final current = state;
    final reloadingSameFolder =
        current is FileBrowserLoaded && current.currentFolderId == event.folderId;
    if (!reloadingSameFolder) {
      emit(const FileBrowserLoading());
    }
    try {
      _currentFolderId = event.folderId;

      if (event.folderId != null) {
        // Build breadcrumbs by fetching folder info
        final folder = await _fileRepository.getFile(event.folderId!);
        _updateBreadcrumbs(folder);
      } else {
        _breadcrumbs = [const BreadcrumbItem(name: 'Home')];
      }

      final result = await _listFiles(event.folderId);
      emit(FileBrowserLoaded(
        files: result.items,
        currentFolderId: _currentFolderId,
        breadcrumbs: _breadcrumbs,
        viewMode: _viewMode,
      ));
    } catch (e) {
      emit(FileBrowserError(e.toString()));
    }
  }

  Future<void> _onCreateFolder(
    CreateFolder event,
    Emitter<FileBrowserState> emit,
  ) async {
    try {
      await _createFolder(_currentFolderId, event.name);
      add(LoadFolder(folderId: _currentFolderId));
    } catch (e) {
      emit(FileBrowserError(e.toString()));
    }
  }

  Future<void> _onDeleteFile(
    DeleteFile event,
    Emitter<FileBrowserState> emit,
  ) async {
    try {
      await _deleteFile(event.id);
      add(LoadFolder(folderId: _currentFolderId));
    } catch (e) {
      emit(FileBrowserError(e.toString()));
    }
  }

  Future<void> _onRenameFile(
    RenameFile event,
    Emitter<FileBrowserState> emit,
  ) async {
    try {
      await _fileRepository.renameFile(event.id, event.newName);
      add(LoadFolder(folderId: _currentFolderId));
    } catch (e) {
      emit(FileBrowserError(e.toString()));
    }
  }

  void _onToggleViewMode(
    ToggleViewMode event,
    Emitter<FileBrowserState> emit,
  ) {
    _viewMode = _viewMode == FileViewMode.list
        ? FileViewMode.grid
        : FileViewMode.list;
    final currentState = state;
    if (currentState is FileBrowserLoaded) {
      emit(currentState.copyWith(viewMode: _viewMode));
    }
  }

  Future<void> _onRefreshFiles(
    RefreshFiles event,
    Emitter<FileBrowserState> emit,
  ) async {
    add(LoadFolder(folderId: _currentFolderId));
  }

  Future<void> _onSearchFiles(
    SearchFiles event,
    Emitter<FileBrowserState> emit,
  ) async {
    emit(const FileBrowserLoading());
    try {
      final result = await _searchFiles(event.query);
      emit(FileBrowserLoaded(
        files: result.items,
        currentFolderId: _currentFolderId,
        breadcrumbs: _breadcrumbs,
        viewMode: _viewMode,
      ));
    } catch (e) {
      emit(FileBrowserError(e.toString()));
    }
  }

  @override
  Future<void> close() {
    _remoteChangeSubscription?.cancel();
    return super.close();
  }

  void _updateBreadcrumbs(FileItem folder) {
    // Simple approach: add the current folder to breadcrumbs.
    // If navigating back via breadcrumb, the LoadFolder with null folderId
    // resets to root. For subfolders, we append.
    final existingIndex = _breadcrumbs.indexWhere((b) => b.id == folder.id);
    if (existingIndex >= 0) {
      // Navigating back to existing breadcrumb — truncate
      _breadcrumbs = _breadcrumbs.sublist(0, existingIndex + 1);
    } else {
      _breadcrumbs = [
        ..._breadcrumbs,
        BreadcrumbItem(id: folder.id, name: folder.name),
      ];
    }
  }
}

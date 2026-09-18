import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../files/data/file_dtos.dart';
import '../data/share_link_data_source.dart';

// --- States ---

sealed class ShareLinkState extends Equatable {
  const ShareLinkState();

  @override
  List<Object?> get props => [];
}

final class ShareLinkLoading extends ShareLinkState {
  const ShareLinkLoading();
}

/// Link unknown, expired, or deleted — the backend does not distinguish
/// these cases (all answer 404), so neither does this state.
final class ShareLinkNotFound extends ShareLinkState {
  const ShareLinkNotFound();
}

/// The link is password-protected. Not supported by this client yet — the
/// backend answers 403 rather than prompting for a password.
final class ShareLinkPasswordProtected extends ShareLinkState {
  const ShareLinkPasswordProtected();
}

/// [error] is the raw caught object, not a message: per `error_message.dart`,
/// turning it into user-facing text is the page's job (it has the
/// [AppLocalizations] this needs), not the cubit's.
final class ShareLinkFailure extends ShareLinkState {
  final Object error;

  const ShareLinkFailure(this.error);

  @override
  List<Object?> get props => [error];
}

/// The shared file or folder, plus wherever the visitor has navigated to
/// inside it. [path] holds the folders entered so far (breadcrumbs, shared
/// root excluded); [children] is the listing of [current] when it is a
/// folder, and null for a single shared file. Per-file download state is
/// keyed by file id so multiple rows can download independently.
final class ShareLinkLoaded extends ShareLinkState {
  final FileDto root;
  final List<FileDto> path;
  final List<FileDto>? children;
  final Map<String, double> downloadProgress;
  final Map<String, Object> downloadErrors;

  const ShareLinkLoaded({
    required this.root,
    required this.path,
    required this.children,
    this.downloadProgress = const {},
    this.downloadErrors = const {},
  });

  FileDto get current => path.isEmpty ? root : path.last;

  ShareLinkLoaded copyWith({
    List<FileDto>? path,
    List<FileDto>? children,
    Map<String, double>? downloadProgress,
    Map<String, Object>? downloadErrors,
  }) {
    return ShareLinkLoaded(
      root: root,
      path: path ?? this.path,
      children: children ?? this.children,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadErrors: downloadErrors ?? this.downloadErrors,
    );
  }

  @override
  List<Object?> get props => [root, path, children, downloadProgress, downloadErrors];
}

// --- Cubit ---

class ShareLinkCubit extends Cubit<ShareLinkState> {
  final ShareLinkDataSource _dataSource;
  final String token;

  // Does not call load() itself — the caller does (see ShareLinkPage), the
  // same way SyncBloc's creation site adds LoadSyncStatus rather than the
  // bloc loading in its own constructor. A constructor-time emit runs
  // synchronously before any listener (including bloc_test's) can attach.
  ShareLinkCubit(this._dataSource, this.token) : super(const ShareLinkLoading());

  Future<void> load() async {
    emit(const ShareLinkLoading());
    try {
      final result = await _dataSource.getShareLink(token);
      final children =
          result.file.isFolder ? await _dataSource.getChildren(token) : null;
      emit(ShareLinkLoaded(root: result.file, path: const [], children: children));
    } catch (e) {
      _emitError(e);
    }
  }

  Future<void> openFolder(FileDto folder) async {
    final current = state;
    if (current is! ShareLinkLoaded) return;
    try {
      final children = await _dataSource.getChildren(token, folderId: folder.id);
      emit(current.copyWith(path: [...current.path, folder], children: children));
    } catch (e) {
      _emitError(e);
    }
  }

  /// Jumps back to breadcrumb [index] in [ShareLinkLoaded.path] (never above
  /// the shared root). `-1` means the shared root itself.
  Future<void> goToBreadcrumb(int index) async {
    final current = state;
    if (current is! ShareLinkLoaded) return;
    final newPath = index < 0 ? const <FileDto>[] : current.path.sublist(0, index + 1);
    final folderId = newPath.isEmpty ? null : newPath.last.id;
    try {
      final children = await _dataSource.getChildren(token, folderId: folderId);
      emit(current.copyWith(path: newPath, children: children));
    } catch (e) {
      _emitError(e);
    }
  }

  Future<void> download(FileDto file) async {
    final current = state;
    if (current is! ShareLinkLoaded) return;
    emit(current.copyWith(
      downloadProgress: {...current.downloadProgress, file.id: 0},
      downloadErrors: {...current.downloadErrors}..remove(file.id),
    ));
    try {
      await _dataSource.downloadFile(
        token,
        file.id,
        onProgress: (progress) {
          final latest = state;
          if (latest is ShareLinkLoaded) {
            emit(latest.copyWith(
              downloadProgress: {...latest.downloadProgress, file.id: progress},
            ));
          }
        },
      );
      _clearDownloadProgress(file.id);
    } catch (e) {
      final latest = state;
      if (latest is ShareLinkLoaded) {
        final progress = {...latest.downloadProgress}..remove(file.id);
        emit(latest.copyWith(
          downloadProgress: progress,
          downloadErrors: {...latest.downloadErrors, file.id: e},
        ));
      }
    }
  }

  void _clearDownloadProgress(String fileId) {
    final latest = state;
    if (latest is ShareLinkLoaded) {
      final progress = {...latest.downloadProgress}..remove(fileId);
      emit(latest.copyWith(downloadProgress: progress));
    }
  }

  void _emitError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 404) return emit(const ShareLinkNotFound());
      if (status == 403) return emit(const ShareLinkPasswordProtected());
    }
    emit(ShareLinkFailure(error));
  }
}

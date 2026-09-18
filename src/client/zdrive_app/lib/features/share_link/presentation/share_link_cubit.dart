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
/// [navigationError] is a transient error from a failed `openFolder`/
/// `goToBreadcrumb` — unlike a failed initial [ShareLinkCubit.load], it does
/// not replace the page (the visitor stays on the folder they were on); the
/// page shows it once (e.g. a SnackBar) and it is cleared on the next
/// successful navigation.
final class ShareLinkLoaded extends ShareLinkState {
  final FileDto root;
  final List<FileDto> path;
  final List<FileDto>? children;
  final Map<String, double> downloadProgress;
  final Map<String, Object> downloadErrors;
  final Object? navigationError;
  // From ShareDto.expiresAt, fetched alongside `root` in ShareLinkCubit.load
  // but not otherwise carried by FileDto — null means the link never
  // expires. Shown on the share page as "Available until ...".
  final DateTime? expiresAt;

  const ShareLinkLoaded({
    required this.root,
    required this.path,
    required this.children,
    this.downloadProgress = const {},
    this.downloadErrors = const {},
    this.navigationError,
    this.expiresAt,
  });

  FileDto get current => path.isEmpty ? root : path.last;

  // navigationError takes a value-returning closure, not a plain nullable
  // param, so copyWith can tell "clear it" (pass `() => null`) apart from
  // "leave it as-is" (omit it) — the same pattern file_browser_bloc.dart
  // uses for FileBrowserLoaded.currentFolderId.
  ShareLinkLoaded copyWith({
    List<FileDto>? path,
    List<FileDto>? children,
    Map<String, double>? downloadProgress,
    Map<String, Object>? downloadErrors,
    Object? Function()? navigationError,
  }) {
    return ShareLinkLoaded(
      root: root,
      path: path ?? this.path,
      children: children ?? this.children,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadErrors: downloadErrors ?? this.downloadErrors,
      navigationError:
          navigationError != null ? navigationError() : this.navigationError,
      expiresAt: expiresAt,
    );
  }

  @override
  List<Object?> get props => [
        root,
        path,
        children,
        downloadProgress,
        downloadErrors,
        navigationError,
        expiresAt,
      ];
}

// --- Cubit ---

class ShareLinkCubit extends Cubit<ShareLinkState> {
  final ShareLinkDataSource _dataSource;
  final String token;

  // Bumped by every openFolder/goToBreadcrumb call, and captured locally
  // before each one's await. If a later navigation started (and possibly
  // already finished) while an earlier one was still in flight, the earlier
  // one's response arriving after is stale and must not overwrite what the
  // visitor is looking at now.
  int _navId = 0;

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
      if (isClosed) return;
      emit(ShareLinkLoaded(
        root: result.file,
        path: const [],
        children: children,
        expiresAt: result.share.expiresAt,
      ));
    } catch (e) {
      if (isClosed) return;
      // Only the initial load maps 404/403 to the full-page states —
      // openFolder/goToBreadcrumb use _applyNavigationResult instead, which
      // keeps the visitor on the folder they were on.
      _emitInitialLoadError(e);
    }
  }

  Future<void> openFolder(FileDto folder) async {
    final current = state;
    if (current is! ShareLinkLoaded) return;
    final requestId = ++_navId;
    await _applyNavigationResult(
      requestId,
      () => _dataSource.getChildren(token, folderId: folder.id),
      newPath: [...current.path, folder],
    );
  }

  /// Jumps back to breadcrumb [index] in [ShareLinkLoaded.path] (never above
  /// the shared root). `-1` means the shared root itself.
  Future<void> goToBreadcrumb(int index) async {
    final current = state;
    if (current is! ShareLinkLoaded) return;
    final newPath = index < 0 ? const <FileDto>[] : current.path.sublist(0, index + 1);
    final requestId = ++_navId;
    await _applyNavigationResult(
      requestId,
      () => _dataSource.getChildren(token, folderId: newPath.isEmpty ? null : newPath.last.id),
      newPath: newPath,
    );
  }

  /// Runs a children fetch and applies its result, guarding against both a
  /// closed cubit and a stale response (an earlier navigation that resolves
  /// after a newer one already landed — see [_navId]). Builds the emitted
  /// state from `state` as read AFTER the await, not a pre-await snapshot,
  /// so download progress/errors that arrived while this was in flight are
  /// not clobbered.
  Future<void> _applyNavigationResult(
    int requestId,
    Future<List<FileDto>> Function() fetchChildren, {
    required List<FileDto> newPath,
  }) async {
    try {
      final children = await fetchChildren();
      if (isClosed || requestId != _navId) return;
      final latest = state;
      if (latest is! ShareLinkLoaded) return;
      emit(latest.copyWith(path: newPath, children: children, navigationError: () => null));
    } catch (e) {
      if (isClosed || requestId != _navId) return;
      final latest = state;
      if (latest is ShareLinkLoaded) {
        emit(latest.copyWith(navigationError: () => e));
      }
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
          if (isClosed) return;
          final latest = state;
          if (latest is ShareLinkLoaded) {
            emit(latest.copyWith(
              downloadProgress: {...latest.downloadProgress, file.id: progress},
            ));
          }
        },
      );
      if (isClosed) return;
      _clearDownloadProgress(file.id);
    } catch (e) {
      if (isClosed) return;
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

  void _emitInitialLoadError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 404) return emit(const ShareLinkNotFound());
      if (status == 403) return emit(const ShareLinkPasswordProtected());
    }
    emit(ShareLinkFailure(error));
  }
}

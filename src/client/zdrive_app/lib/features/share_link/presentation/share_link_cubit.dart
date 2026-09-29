import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../files/data/file_dtos.dart';
import '../../files/data/file_saver.dart';
import '../data/share_link_data_source.dart';
import '../data/share_link_dtos.dart';

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
  // From ShareInfoDto (GET .../info), fetched alongside `root` in
  // ShareLinkCubit.load. Both default to false — an older backend that
  // predates that endpoint (404) falls back to read-only rather than
  // breaking the page.
  final bool canWrite;
  final bool canDelete;
  // Keyed by the uploaded file's name, mirroring downloadProgress/
  // downloadErrors above — an upload in this share has no file id yet
  // until it completes.
  final Map<String, double> uploadProgress;
  final Map<String, Object> uploadErrors;

  const ShareLinkLoaded({
    required this.root,
    required this.path,
    required this.children,
    this.downloadProgress = const {},
    this.downloadErrors = const {},
    this.navigationError,
    this.expiresAt,
    this.canWrite = false,
    this.canDelete = false,
    this.uploadProgress = const {},
    this.uploadErrors = const {},
  });

  FileDto get current => path.isEmpty ? root : path.last;

  // navigationError takes a value-returning closure, not a plain nullable
  // param, so copyWith can tell "clear it" (pass `() => null`) apart from
  // "leave it as-is" (omit it) — the same pattern file_browser_bloc.dart
  // uses for FileBrowserLoaded.currentFolderId.
  ShareLinkLoaded copyWith({
    FileDto? root,
    List<FileDto>? path,
    List<FileDto>? children,
    Map<String, double>? downloadProgress,
    Map<String, Object>? downloadErrors,
    Object? Function()? navigationError,
    Map<String, double>? uploadProgress,
    Map<String, Object>? uploadErrors,
  }) {
    return ShareLinkLoaded(
      root: root ?? this.root,
      path: path ?? this.path,
      children: children ?? this.children,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadErrors: downloadErrors ?? this.downloadErrors,
      navigationError:
          navigationError != null ? navigationError() : this.navigationError,
      expiresAt: expiresAt,
      canWrite: canWrite,
      canDelete: canDelete,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      uploadErrors: uploadErrors ?? this.uploadErrors,
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
        canWrite,
        canDelete,
        uploadProgress,
        uploadErrors,
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
  /// The platform saver — only used to save bytes the preview already loaded.
  final Future<void> Function(String fileName, Stream<Uint8List> content) _save;

  ShareLinkCubit(
    this._dataSource,
    this.token, {
    Future<void> Function(String fileName, Stream<Uint8List> content) save = saveFileStream,
  })  : _save = save,
        super(const ShareLinkLoading());

  Future<void> load() async {
    emit(const ShareLinkLoading());
    try {
      final result = await _dataSource.getShareLink(token);
      final children =
          result.file.isFolder ? await _dataSource.getChildren(token) : null;
      final info = await _loadInfoOrNull();
      if (isClosed) return;
      emit(ShareLinkLoaded(
        root: result.file,
        path: const [],
        children: children,
        expiresAt: result.share.expiresAt,
        canWrite: info?.canWrite ?? false,
        canDelete: info?.allowDelete ?? false,
      ));
    } catch (e) {
      if (isClosed) return;
      // Only the initial load maps 404/403 to the full-page states —
      // openFolder/goToBreadcrumb use _applyNavigationResult instead, which
      // keeps the visitor on the folder they were on.
      _emitInitialLoadError(e);
    }
  }

  /// A failed info call (404 on an older backend without the endpoint, or
  /// any other hiccup) must not break the rest of `load()` — it only costs
  /// the write/delete controls, which is exactly the read-only fallback.
  Future<ShareInfoDto?> _loadInfoOrNull() async {
    try {
      return await _dataSource.getInfo(token);
    } catch (_) {
      return null;
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

  /// Lazy verified byte stream of [file] for the in-app preview — the same
  /// grant-authenticated path as [download], read into memory instead of saved.
  Stream<Uint8List> openPreviewStream(FileDto file) async* {
    final download = await _dataSource.openDownload(token, file.id);
    yield* download.content;
  }

  /// [loadedBytes] are content the preview already downloaded and verified:
  /// they are saved as they are, without asking for a new grant. A download of
  /// the same file that is still running makes this a no-op.
  Future<void> download(FileDto file, {Uint8List? loadedBytes}) async {
    final current = state;
    if (current is! ShareLinkLoaded) return;
    if (current.downloadProgress.containsKey(file.id)) return;
    emit(current.copyWith(
      downloadProgress: {...current.downloadProgress, file.id: 0},
      downloadErrors: {...current.downloadErrors}..remove(file.id),
    ));
    try {
      if (loadedBytes != null) {
        await _save(file.name, Stream.value(loadedBytes));
      } else {
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
      }
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

  /// The folder id write/delete/upload actions below operate on — the
  /// folder currently being viewed, or null for the shared root.
  String? get _currentFolderId {
    final current = state;
    if (current is! ShareLinkLoaded || current.path.isEmpty) return null;
    return current.path.last.id;
  }

  /// Creates a folder in the folder currently being viewed. On success,
  /// refreshes the listing (see [_refreshChildren]); on failure, surfaces
  /// the error the same way a failed navigation does (a transient SnackBar,
  /// not a full-page error) — a 409 there just means "pick another name".
  Future<void> createFolder(String name) async {
    final current = state;
    if (current is! ShareLinkLoaded || current.children == null) return;
    final navId = _navId;
    try {
      await _dataSource.createFolder(token, parentId: _currentFolderId, name: name);
      if (isClosed || navId != _navId) return;
      await _refreshAfterWrite(navId);
    } catch (e) {
      if (isClosed || navId != _navId) return;
      final latest = state;
      if (latest is ShareLinkLoaded) emit(latest.copyWith(navigationError: () => e));
    }
  }

  /// Uploads [name] into the folder currently being viewed — or, for a
  /// share whose root is a single file, replaces that file directly (see
  /// `ShareLinkDataSource.uploadFile`). Progress/errors are keyed by [name]
  /// in [ShareLinkLoaded.uploadProgress]/[ShareLinkLoaded.uploadErrors], the
  /// same way [download] keys by file id — an upload has no file id yet
  /// until it completes, and re-running the same upload with `overwrite:
  /// true` after a 409 reuses the same key.
  Future<void> uploadFile(
    String name,
    Stream<List<int>> content,
    int sizeBytes, {
    bool overwrite = false,
  }) async {
    final current = state;
    if (current is! ShareLinkLoaded) return;
    final navId = _navId;
    final isSingleFileShare = current.children == null;
    emit(current.copyWith(
      uploadProgress: {...current.uploadProgress, name: 0},
      uploadErrors: {...current.uploadErrors}..remove(name),
    ));
    try {
      final updated = await _dataSource.uploadFile(
        token,
        parentId: isSingleFileShare ? null : _currentFolderId,
        fileName: name,
        content: content,
        sizeBytes: sizeBytes,
        overwrite: overwrite,
        onProgress: (progress) {
          if (isClosed) return;
          final latest = state;
          if (latest is ShareLinkLoaded) {
            emit(latest.copyWith(uploadProgress: {...latest.uploadProgress, name: progress}));
          }
        },
      );
      if (isClosed) return;
      // Clear the progress row BEFORE the navigation guard: the upload is
      // over whether or not the visitor has since opened another folder,
      // and a row left behind would sit frozen at its last percentage in
      // every folder until reload.
      _clearUploadProgress(name);
      if (navId != _navId) return;
      if (isSingleFileShare) {
        final latest = state;
        if (latest is ShareLinkLoaded) emit(latest.copyWith(root: updated));
      } else {
        await _refreshAfterWrite(navId);
      }
    } catch (e) {
      // Same reasoning as above: report the failure even after a navigation
      // — upload errors/progress are page-wide, not per folder.
      if (isClosed) return;
      final latest = state;
      if (latest is ShareLinkLoaded) {
        final progress = {...latest.uploadProgress}..remove(name);
        emit(latest.copyWith(uploadProgress: progress, uploadErrors: {...latest.uploadErrors, name: e}));
      }
    }
  }

  /// Moves [id] to the owner's trash and refreshes the listing.
  Future<void> deleteItem(String id) async {
    final current = state;
    if (current is! ShareLinkLoaded) return;
    final navId = _navId;
    try {
      await _dataSource.deleteItem(token, id);
      if (isClosed || navId != _navId) return;
      await _refreshAfterWrite(navId);
    } catch (e) {
      if (isClosed || navId != _navId) return;
      final latest = state;
      if (latest is ShareLinkLoaded) emit(latest.copyWith(navigationError: () => e));
    }
  }

  /// Refreshes the listing after a write that already SUCCEEDED. A failing
  /// refresh must not be reported as a failed write: the visitor would
  /// retry, hit a 409 and be asked to overwrite the file they just uploaded.
  /// The stale listing corrects itself on the next navigation.
  Future<void> _refreshAfterWrite(int navId) async {
    try {
      await _refreshChildren(navId);
    } catch (_) {
      // Best effort by design — see above.
    }
  }

  void _clearUploadProgress(String name) {
    final latest = state;
    if (latest is ShareLinkLoaded) {
      final progress = {...latest.uploadProgress}..remove(name);
      emit(latest.copyWith(uploadProgress: progress));
    }
  }

  /// Re-fetches the folder currently being viewed, WITHOUT going through
  /// [ShareLinkLoading] — createFolder/uploadFile/deleteItem must not
  /// replace the whole page with a loading state (the visitor keeps their
  /// scroll position and breadcrumbs). Guarded by [navId] the same way
  /// [_applyNavigationResult] guards a navigation: if the visitor moved to a
  /// different folder while the write was in flight, this refresh is for a
  /// folder they've since left and must not overwrite what they're looking
  /// at now. A single-file share has no listing to refresh.
  Future<void> _refreshChildren(int navId) async {
    final latest = state;
    if (latest is! ShareLinkLoaded || latest.children == null) return;
    final folderId = latest.path.isEmpty ? null : latest.path.last.id;
    final children = await _dataSource.getChildren(token, folderId: folderId);
    if (isClosed || navId != _navId) return;
    final refreshed = state;
    if (refreshed is! ShareLinkLoaded) return;
    emit(refreshed.copyWith(children: children));
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

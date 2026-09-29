import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/file_preview_type.dart';

// --- States ---

sealed class FilePreviewState extends Equatable {
  const FilePreviewState();

  @override
  List<Object?> get props => [];
}

/// [progress] is 0..1, or null when the total size is unknown.
final class FilePreviewLoading extends FilePreviewState {
  final double? progress;

  const FilePreviewLoading({this.progress});

  @override
  List<Object?> get props => [progress];
}

final class FilePreviewLoaded extends FilePreviewState {
  final PreviewKind kind;
  final Uint8List bytes;

  const FilePreviewLoaded({required this.kind, required this.bytes});

  @override
  List<Object?> get props => [kind, bytes];
}

/// [error] is the raw caught object — turning it into text is the page's job
/// (it has the localizations), see `error_message.dart`.
final class FilePreviewError extends FilePreviewState {
  final Object error;

  const FilePreviewError(this.error);

  @override
  List<Object?> get props => [error];
}

final class FilePreviewTooLarge extends FilePreviewState {
  const FilePreviewTooLarge();
}

final class FilePreviewUnsupported extends FilePreviewState {
  const FilePreviewUnsupported();
}

// --- Cubit ---

/// Loads a file's bytes for the in-app preview. It knows nothing about where
/// the bytes come from: [openContent] is the file browser's verified download
/// stream, or the share page's grant-authenticated one.
class FilePreviewCubit extends Cubit<FilePreviewState> {
  final String fileName;
  final String? mimeType;
  final int? sizeBytes;
  final Stream<Uint8List> Function() openContent;

  /// Unique per opened preview. Handed to the PDF viewer as (part of) its
  /// document name, because pdfrx caches documents globally by that name and
  /// two different files with the same name must not collide.
  final String documentKey = '${DateTime.now().microsecondsSinceEpoch}';

  StreamSubscription<Uint8List>? _subscription;
  Completer<void>? _pending;

  FilePreviewCubit({
    required this.fileName,
    required this.openContent,
    this.mimeType,
    this.sizeBytes,
  }) : super(const FilePreviewLoading());

  Future<void> load() async {
    final kind = detectPreviewKind(mimeType: mimeType, fileName: fileName);
    if (kind == PreviewKind.unsupported) {
      emit(const FilePreviewUnsupported());
      return;
    }
    final limit = kind == PreviewKind.text ? previewTextMaxBytes : previewMaxBytes;
    final declaredSize = sizeBytes;
    if (declaredSize != null && declaredSize > limit) {
      emit(const FilePreviewTooLarge());
      return;
    }

    await _stop();
    final knownSize = declaredSize != null && declaredSize > 0;
    // Without a usable declared size the progress is indeterminate (null).
    emit(FilePreviewLoading(progress: knownSize ? 0 : null));

    final builder = BytesBuilder(copy: false);
    final pending = _pending = Completer<void>();
    void finish() {
      if (!pending.isCompleted) pending.complete();
    }

    try {
      _subscription = openContent().listen(
        (chunk) {
          builder.add(chunk);
          // Size metadata can be null or stale; the bytes actually received win.
          if (builder.length > limit) {
            emit(const FilePreviewTooLarge());
            _subscription?.cancel();
            _subscription = null;
            finish();
          } else if (knownSize) {
            emit(FilePreviewLoading(progress: (builder.length / declaredSize).clamp(0.0, 1.0)));
          }
        },
        onError: (Object e) {
          // cancelOnError already cancelled the subscription.
          _subscription = null;
          if (!isClosed) emit(FilePreviewError(e));
          finish();
        },
        onDone: () {
          _subscription = null;
          if (!isClosed) emit(FilePreviewLoaded(kind: kind, bytes: builder.takeBytes()));
          finish();
        },
        cancelOnError: true,
      );
    } catch (e) {
      emit(FilePreviewError(e));
      finish();
    }
    await pending.future;
  }

  Future<void> retry() => load();

  Future<void> _stop() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  /// Closing the preview stops the transfer.
  @override
  Future<void> close() async {
    await _stop();
    return super.close();
  }
}

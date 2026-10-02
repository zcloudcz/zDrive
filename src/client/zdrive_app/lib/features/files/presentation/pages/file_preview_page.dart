import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../../../core/network/error_message.dart';
import '../../domain/file_preview_type.dart';
import '../file_preview_cubit.dart';
import '../widgets/file_icon_data.dart';
import '../widgets/file_size_format.dart';

/// Full-screen preview of one file. Shared by the file browser and the public
/// share page: it only needs a name, optional metadata, and a way to open the
/// content stream ([openContent]) — where the bytes come from, and what
/// "download" and "share" do, is up to the caller.
class FilePreviewPage extends StatelessWidget {
  final String fileName;
  final String? mimeType;
  final int? sizeBytes;
  final Stream<Uint8List> Function() openContent;

  /// Called with this page's context, so anything it shows opens above the
  /// preview rather than beneath it. [loadedBytes] is the already downloaded
  /// and verified content when the preview has finished loading — the caller
  /// should save those instead of downloading the file again.
  final void Function(BuildContext context, Uint8List? loadedBytes) onDownload;
  final void Function(BuildContext context)? onShare;

  const FilePreviewPage({
    super.key,
    required this.fileName,
    required this.openContent,
    required this.onDownload,
    this.mimeType,
    this.sizeBytes,
    this.onShare,
  });

  /// Pushes the preview on the root navigator, above any shell.
  static Future<void> show(
    BuildContext context, {
    required String fileName,
    required Stream<Uint8List> Function() openContent,
    required void Function(BuildContext context, Uint8List? loadedBytes) onDownload,
    String? mimeType,
    int? sizeBytes,
    void Function(BuildContext context)? onShare,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => FilePreviewPage(
          fileName: fileName,
          openContent: openContent,
          onDownload: onDownload,
          mimeType: mimeType,
          sizeBytes: sizeBytes,
          onShare: onShare,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocProvider(
      create: (_) => FilePreviewCubit(
        fileName: fileName,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        openContent: openContent,
      )..load(),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.close,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: l10n.download,
                    onPressed: () => _download(context),
                  ),
                ),
                if (onShare != null)
                  Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.share),
                      tooltip: l10n.share,
                      onPressed: () => onShare!(context),
                    ),
                  ),
              ],
            ),
            body: BlocBuilder<FilePreviewCubit, FilePreviewState>(
              builder: (context, state) => switch (state) {
                FilePreviewLoading(:final progress) => Center(
                    child: CircularProgressIndicator(
                      value: progress,
                      semanticsLabel: l10n.downloadProgress,
                    ),
                  ),
                FilePreviewLoaded(:final kind, :final bytes) => _buildContent(context, kind, bytes),
                FilePreviewError(:final error) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(describeError(error, l10n), textAlign: TextAlign.center),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => context.read<FilePreviewCubit>().retry(),
                          child: Text(l10n.retry),
                        ),
                      ],
                    ),
                  ),
                FilePreviewTooLarge() => _notice(context, l10n.previewTooLarge),
                FilePreviewUnsupported() => _notice(context, l10n.previewUnsupported),
              },
            ),
          ),
        ),
      ),
    );
  }

  void _download(BuildContext context) {
    final state = context.read<FilePreviewCubit>().state;
    onDownload(context, state is FilePreviewLoaded ? state.bytes : null);
  }

  Widget _notice(BuildContext context, String message) {
    return _PreviewNotice(
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      message: message,
      onDownload: () => _download(context),
    );
  }

  Widget _buildContent(BuildContext context, PreviewKind kind, Uint8List bytes) {
    switch (kind) {
      case PreviewKind.image:
        return InteractiveViewer(
          maxScale: 8,
          child: Center(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              // Decode no wider than the screen needs: a full-resolution
              // 48 MP photo would exhaust memory on mobile.
              cacheWidth: (MediaQuery.sizeOf(context).width *
                      MediaQuery.devicePixelRatioOf(context))
                  .round()
                  .clamp(1, 4096),
              // Decoding is up to the platform codec (HEIC in particular), so
              // a failure here means "unavailable", not "broken file".
              errorBuilder: (context, _, _) => _notice(
                context,
                AppLocalizations.of(context)!.previewImageFailed,
              ),
            ),
          ),
        );
      case PreviewKind.text:
        return _TextPreview(bytes: bytes);
      case PreviewKind.pdf:
        return PdfViewer.data(
          bytes,
          // pdfrx caches documents globally by this name.
          sourceName: '${context.read<FilePreviewCubit>().documentKey}/$fileName',
        );
      case PreviewKind.unsupported:
        return _notice(context, AppLocalizations.of(context)!.previewUnsupported);
    }
  }
}

class _TextPreview extends StatefulWidget {
  final Uint8List bytes;

  const _TextPreview({required this.bytes});

  @override
  State<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<_TextPreview> {
  late final String _text = utf8.decode(widget.bytes, allowMalformed: true);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: SelectableText(
          _text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      ),
    );
  }
}

/// Shown instead of a preview: icon, name, size and a Download button.
class _PreviewNotice extends StatelessWidget {
  final String? mimeType;
  final int? sizeBytes;
  final String message;
  final VoidCallback onDownload;

  const _PreviewNotice({
    required this.mimeType,
    required this.sizeBytes,
    required this.message,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              iconForFile(isFolder: false, mimeType: mimeType),
              size: 64,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.previewNotAvailable,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (sizeBytes != null) ...[
              const SizedBox(height: 4),
              Text(
                formatFileSize(sizeBytes),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download),
              label: Text(l10n.download),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/error_message.dart';
import '../../../../shared/l10n/app_localizations.dart';
import '../../../../shared/l10n/relative_time.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/brand_lockup.dart';
import '../../../files/data/file_dtos.dart';
import '../../../files/presentation/widgets/create_folder_dialog.dart';
import '../../../files/presentation/widgets/file_icon_data.dart';
import '../../../files/presentation/widgets/file_size_format.dart';
import '../../data/share_link_data_source.dart';
import '../share_link_cubit.dart';

/// `ShareDto.expiresAt` is a UTC instant (the wire format's trailing `Z`) —
/// formatting it directly would print UTC calendar fields, which is the
/// wrong day for any visitor east/west of Greenwich. `.toLocal()` first.
/// Top-level (not private) so a unit test can call it directly instead of
/// only exercising it through the widget tree.
String formatShareExpiryDate(DateTime expiresAt, String locale) =>
    DateFormat.yMMMd(locale).format(expiresAt.toLocal());

/// Maps a write/delete/upload error from the share write API to user-facing
/// text — the status codes the backend contract documents for those calls,
/// on top of [describeError]'s generic connection/5xx handling.
String describeShareError(Object error, AppLocalizations l10n) {
  if (error is DioException) {
    switch (error.response?.statusCode) {
      case 403:
        return l10n.shareErrorNotAllowed;
      case 409:
        return l10n.shareErrorNameExists;
      case 413:
        return l10n.shareErrorQuotaExceeded;
      case 429:
        return l10n.shareErrorTooManyUploads;
    }
  }
  return describeError(error, l10n);
}

/// Picks a file (same package/options as the authenticated file browser's
/// upload — `file_browser_page.dart`'s `_pickAndUploadFile`) and uploads it
/// through [ShareLinkCubit.uploadFile]. [replaceFileName] set means "replace
/// this exact file" (the single-file-share card's Replace button) — always
/// `overwrite: true`, no name to pick since the target is fixed. Left null
/// (the folder actions row's Upload button), the picked file's own name is
/// used and a 409 (name already exists) prompts to confirm before retrying
/// with `overwrite: true` — this app never silently overwrites.
Future<void> pickAndUploadShareFile(BuildContext context, {String? replaceFileName}) async {
  final result = await FilePicker.platform.pickFiles(withData: false, withReadStream: true);
  if (result == null || result.files.isEmpty) return;
  final picked = result.files.first;
  final stream = picked.readStream;
  if (stream == null) return;
  if (!context.mounted) return;

  await _uploadShareFile(
    context,
    replaceFileName ?? picked.name,
    stream,
    picked.size,
    overwrite: replaceFileName != null,
  );
}

/// Runs one upload attempt and, only for a fresh (non-overwrite) attempt
/// that came back with a 409, asks to confirm replacing it. Safe to retry
/// [content] as-is: a 409 comes from the upload-grant request, which
/// `ShareLinkDataSource.uploadFile` sends before the content stream is ever
/// read, so nothing has been consumed from it yet.
Future<void> _uploadShareFile(
  BuildContext context,
  String name,
  Stream<List<int>> content,
  int sizeBytes, {
  required bool overwrite,
}) async {
  final cubit = context.read<ShareLinkCubit>();
  await cubit.uploadFile(name, content, sizeBytes, overwrite: overwrite);
  if (!context.mounted || overwrite) return;

  final state = cubit.state;
  final error = state is ShareLinkLoaded ? state.uploadErrors[name] : null;
  if (error is! DioException || error.response?.statusCode != 409) return;

  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.shareOverwriteTitle),
      content: Text(l10n.shareOverwriteMessage(name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.shareReplaceConfirm),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    await _uploadShareFile(context, name, content, sizeBytes, overwrite: true);
  }
}

Future<void> _showShareCreateFolderDialog(BuildContext context) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => const CreateFolderDialog(),
  );
  if (name != null && context.mounted) {
    context.read<ShareLinkCubit>().createFolder(name);
  }
}

Future<void> _showShareDeleteConfirm(BuildContext context, FileDto file) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.confirmDelete),
      content: Text('${file.name}\n\n${l10n.shareDeleteConfirmMessage}'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    context.read<ShareLinkCubit>().deleteItem(file.id);
  }
}

/// Public, unauthenticated page behind `/s/:token` — shows the file or
/// folder a share link points at and lets a visitor without an account
/// download it. Reachable while logged in too (the router does not gate
/// this route), in which case it renders identically.
class ShareLinkPage extends StatelessWidget {
  final String token;

  const ShareLinkPage({super.key, required this.token});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ShareLinkCubit(getIt<ShareLinkDataSource>(), token)..load(),
      child: const ShareLinkView(),
    );
  }
}

/// The page's body, split out from [ShareLinkPage] so a widget test can pump
/// it directly with a mocked [ShareLinkCubit] (see `file_browser_page.dart`'s
/// `FileBrowserView` for the same pattern).
class ShareLinkView extends StatelessWidget {
  const ShareLinkView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // A share link is opened by a visitor with no app preference — often
    // straight from a chat/email link on their phone. Following the OS's
    // dark mode here turned this public storefront page into a near-black,
    // unbranded screen (the bug report that triggered this design pass).
    // Force light for this one route; the authenticated app still follows
    // AppPreferences.themeMode as before.
    return Theme(
      data: AppTheme.light,
      // ScaffoldMessenger.of(context) below would otherwise resolve to the
      // MaterialApp-level messenger, whose overlay lives OUTSIDE this forced
      // light Theme — its SnackBar then rendered with the app's ambient
      // (possibly dark) theme. A local ScaffoldMessenger keeps the SnackBar
      // inside the light subtree.
      child: ScaffoldMessenger(
        child: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              backgroundColor: AppTheme.brandPetrol,
              foregroundColor: Colors.white,
              title: const BrandLockup(monochrome: true),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: BlocListener<ShareLinkCubit, ShareLinkState>(
                            // Only when navigationError actually became non-null: the
                            // cubit clears it (sets it back to null) on every successful
                            // navigation, and that clearing state change must not itself
                            // pop a SnackBar.
                            listenWhen: (previous, current) =>
                                current is ShareLinkLoaded &&
                                current.navigationError != null &&
                                (previous is! ShareLinkLoaded ||
                                    previous.navigationError != current.navigationError),
                            listener: (context, state) {
                              final error = (state as ShareLinkLoaded).navigationError!;
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(SnackBar(content: Text(describeError(error, l10n))));
                            },
                            child: BlocBuilder<ShareLinkCubit, ShareLinkState>(
                              builder: (context, state) {
                                final content = switch (state) {
                                  ShareLinkLoading() => const _ShareLoadingSkeleton(),
                                  ShareLinkNotFound() => _StatusMessage(
                                      icon: Icons.link_off,
                                      title: l10n.shareNotFoundTitle,
                                      message: l10n.shareNotFoundMessage,
                                    ),
                                  ShareLinkPasswordProtected() => _StatusMessage(
                                      icon: Icons.lock_outline,
                                      title: l10n.sharePasswordProtectedTitle,
                                      message: l10n.sharePasswordProtectedMessage,
                                    ),
                                  ShareLinkFailure() => _StatusMessage(
                                      icon: Icons.error_outline,
                                      title: describeError(state.error, l10n),
                                      onRetry: () => context.read<ShareLinkCubit>().load(),
                                    ),
                                  ShareLinkLoaded(children: null) => _SingleFileCard(
                                      file: state.root,
                                      expiresAt: state.expiresAt,
                                      progress: state.downloadProgress[state.root.id],
                                      error: state.downloadErrors[state.root.id],
                                      canReplace: state.canWrite,
                                      uploadProgress: state.uploadProgress[state.root.name],
                                      uploadError: state.uploadErrors[state.root.name],
                                    ),
                                  ShareLinkLoaded() => _FolderView(state: state),
                                };
                                // The folder view manages its own scrolling (an
                                // Expanded ListView) and needs the bounded height
                                // this Center already provides; every other state
                                // is a fixed-size card that must scroll instead of
                                // overflow when text is scaled up (see 4.6).
                                final isFolder = state is ShareLinkLoaded && state.children != null;
                                return isFolder
                                    ? content
                                    : SingleChildScrollView(child: content);
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const _ShareFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared by the not-found, password-protected and failure states — an icon
/// in a container circle, a title, an optional message, and a retry action
/// only where retrying can actually help (not for not-found/password-
/// protected, which is the same next time).
class _StatusMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final VoidCallback? onRetry;

  const _StatusMessage({
    required this.icon,
    required this.title,
    this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: scheme.secondaryContainer,
              child: Icon(icon, size: 36, color: scheme.onSecondaryContainer),
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Loading placeholder: a circle + two bars echoing the eventual file card,
/// instead of a bare spinner (4.5). Pulses via opacity unless the platform
/// asked for reduced motion, in which case it renders static (4.6).
class _ShareLoadingSkeleton extends StatelessWidget {
  const _ShareLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _SkeletonBlock(width: 96, height: 96, shape: BoxShape.circle),
              SizedBox(height: 24),
              _SkeletonBlock(width: 200, height: 20),
              SizedBox(height: 12),
              _SkeletonBlock(width: 140, height: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatefulWidget {
  final double width;
  final double height;
  final BoxShape shape;

  const _SkeletonBlock({
    required this.width,
    required this.height,
    this.shape = BoxShape.rectangle,
  });

  @override
  State<_SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<_SkeletonBlock> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  }

  // MediaQuery isn't available in initState, and disableAnimations can also
  // change while this widget is alive (a user flips the OS setting). Only
  // running/stopping the controller here — never creating a second one —
  // means a `pumpAndSettle` on the loading state actually settles instead of
  // hanging on a ticker that repeats forever (4.6).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldAnimate = !MediaQuery.disableAnimationsOf(context);
    if (shouldAnimate == _animating) return;
    _animating = shouldAnimate;
    if (shouldAnimate) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHigh;
    Widget block(double opacity) => Opacity(
          opacity: opacity,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: color,
              shape: widget.shape,
              borderRadius: widget.shape == BoxShape.rectangle ? BorderRadius.circular(8) : null,
            ),
          ),
        );
    if (!_animating) return block(1);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => block(0.4 + _controller.value * 0.6),
    );
  }
}

class _FolderView extends StatelessWidget {
  final ShareLinkLoaded state;

  const _FolderView({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final children = state.children!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Breadcrumbs(state: state),
            if (state.canWrite) ...[
              const SizedBox(height: 8),
              const _ShareActionsRow(),
            ],
            if (state.uploadProgress.isNotEmpty || state.uploadErrors.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ShareUploadProgressList(
                progress: state.uploadProgress,
                errors: state.uploadErrors,
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: children.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder_open,
                            size: 48,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(l10n.noFiles),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: children.length,
                      itemBuilder: (context, index) {
                        final file = children[index];
                        return _ShareChildRow(
                          file: file,
                          progress: state.downloadProgress[file.id],
                          error: state.downloadErrors[file.id],
                          canDelete: state.canDelete,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Upload + New folder, shown above the listing only for a link that allows
/// Write — two explicit buttons rather than the authenticated file browser's
/// "+ New" menu (`NewItemMenuButton`), since a share page has only these two
/// actions and a menu would just add a tap.
class _ShareActionsRow extends StatelessWidget {
  const _ShareActionsRow();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () => pickAndUploadShareFile(context),
          icon: const Icon(Icons.upload_file),
          label: Text(l10n.uploadFile),
        ),
        OutlinedButton.icon(
          onPressed: () => _showShareCreateFolderDialog(context),
          icon: const Icon(Icons.create_new_folder),
          label: Text(l10n.newFolder),
        ),
      ],
    );
  }
}

/// Determinate progress row per active/failed upload, keyed by file name
/// (mirrors [_ShareChildRow]'s per-file download progress) — never an
/// indeterminate spinner (this page's tests assert none).
class _ShareUploadProgressList extends StatelessWidget {
  final Map<String, double> progress;
  final Map<String, Object> errors;

  const _ShareUploadProgressList({required this.progress, required this.errors});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final names = {...progress.keys, ...errors.keys};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final name in names) ...[
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          if (errors[name] case final error?)
            Text(describeShareError(error, l10n), style: TextStyle(color: scheme.error))
          else ...[
            LinearProgressIndicator(value: progress[name] == 0 ? 0.0 : progress[name]),
            Text(
              '${((progress[name] ?? 0) * 100).clamp(0, 100).round()}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  final ShareLinkLoaded state;

  const _Breadcrumbs({required this.state});

  @override
  Widget build(BuildContext context) {
    final crumbs = [state.root, ...state.path];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < crumbs.length; i++) ...[
            if (i > 0) const Icon(Icons.chevron_right, size: 18),
            TextButton(
              onPressed: i == crumbs.length - 1
                  ? null
                  : () => context.read<ShareLinkCubit>().goToBreadcrumb(i - 1),
              child: Text(crumbs[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ],
      ),
    );
  }
}

class _SingleFileCard extends StatelessWidget {
  final FileDto file;
  final DateTime? expiresAt;
  final double? progress;
  final Object? error;
  final bool canReplace;
  final double? uploadProgress;
  final Object? uploadError;

  const _SingleFileCard({
    required this.file,
    this.expiresAt,
    this.progress,
    this.error,
    this.canReplace = false,
    this.uploadProgress,
    this.uploadError,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: scheme.tertiaryContainer,
              child: Icon(
                iconForFile(isFolder: file.isFolder, mimeType: file.mimeType),
                size: 44,
                color: scheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            Tooltip(
              message: file.name,
              child: Text(
                file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${formatFileSize(file.sizeBytes)} · ${formatRelativeTime(file.updatedAt, l10n.localeName)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (expiresAt != null) ...[
              const SizedBox(height: 8),
              // Row's children can't wrap; at 200% text scale the date text
              // alone can exceed the card width, so it needs to shrink/wrap
              // instead of forcing the Row wider than its parent (4.6).
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.schedule, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      l10n.shareAvailableUntil(formatShareExpiryDate(expiresAt!, l10n.localeName)),
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            if (error != null) ...[
              Text(describeError(error!, l10n), style: TextStyle(color: scheme.error)),
              const SizedBox(height: 8),
            ],
            if (progress != null)
              // Determinate, never the button's indeterminate spinner this
              // replaced: an indeterminate animation never settles, which
              // hangs any pumpAndSettle on this state (4.6/teeth check).
              SizedBox(
                width: 200,
                child: Column(
                  children: [
                    LinearProgressIndicator(value: progress == 0 ? 0.0 : progress),
                    const SizedBox(height: 8),
                    Text(
                      '${(progress! * 100).clamp(0, 100).round()}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              )
            else
              FilledButton.icon(
                onPressed: () => context.read<ShareLinkCubit>().download(file),
                icon: const Icon(Icons.download),
                label: Text(l10n.download),
              ),
            if (canReplace) ...[
              const SizedBox(height: 12),
              if (uploadError != null) ...[
                Text(describeShareError(uploadError!, l10n), style: TextStyle(color: scheme.error)),
                const SizedBox(height: 8),
              ],
              if (uploadProgress != null)
                SizedBox(
                  width: 200,
                  child: Column(
                    children: [
                      LinearProgressIndicator(value: uploadProgress == 0 ? 0.0 : uploadProgress),
                      const SizedBox(height: 8),
                      Text(
                        '${(uploadProgress! * 100).clamp(0, 100).round()}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => pickAndUploadShareFile(context, replaceFileName: file.name),
                  icon: const Icon(Icons.upload_file),
                  label: Text(l10n.shareReplaceFile),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShareChildRow extends StatelessWidget {
  final FileDto file;
  final double? progress;
  final Object? error;
  final bool canDelete;

  const _ShareChildRow({
    required this.file,
    this.progress,
    this.error,
    this.canDelete = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final downloadAction = file.isFolder
        ? null
        : progress != null
            // A percentage, not an indeterminate spinner (4.6/teeth
            // check): fits a list row better than a progress ring anyway.
            ? SizedBox(
                width: 40,
                child: Text(
                  '${(progress! * 100).clamp(0, 100).round()}%',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            : IconButton(
                icon: const Icon(Icons.download),
                tooltip: l10n.download,
                onPressed: () => context.read<ShareLinkCubit>().download(file),
              );
    final deleteAction = canDelete
        ? IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '${l10n.delete} ${file.name}',
            onPressed: () => _showShareDeleteConfirm(context, file),
          )
        : null;
    return ListTile(
      leading: Icon(iconForFile(isFolder: file.isFolder, mimeType: file.mimeType)),
      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: file.isFolder
          ? null
          : Text(
              error != null
                  ? describeError(error!, l10n)
                  : '${formatFileSize(file.sizeBytes)} · ${formatRelativeTime(file.updatedAt, l10n.localeName)}',
              style: error != null
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
            ),
      trailing: downloadAction == null && deleteAction == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [?downloadAction, ?deleteAction],
            ),
      onTap: file.isFolder ? () => context.read<ShareLinkCubit>().openFolder(file) : null,
    );
  }
}

/// Persistent footer below the card: the page's one secondary exit (open
/// zDrive) plus a trust line — merges pCloud's persistent CTA and Proton's
/// trust strip (3(a)) into a single row instead of stacking both patterns.
class _ShareFooter extends StatelessWidget {
  const _ShareFooter();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => context.go('/login'),
              child: Text(l10n.shareWhatIsZDrive),
            ),
            Text(
              l10n.shareFooterTagline,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

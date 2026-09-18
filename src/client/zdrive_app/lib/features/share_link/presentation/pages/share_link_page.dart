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
import '../../../files/presentation/widgets/file_icon_data.dart';
import '../../../files/presentation/widgets/file_size_format.dart';
import '../../data/share_link_data_source.dart';
import '../share_link_cubit.dart';

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
      child: Scaffold(
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
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
    if (MediaQuery.disableAnimationsOf(context)) return block(1);
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

  const _SingleFileCard({
    required this.file,
    this.expiresAt,
    this.progress,
    this.error,
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
                      l10n.shareAvailableUntil(DateFormat.yMMMd(l10n.localeName).format(expiresAt!)),
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
            FilledButton.icon(
              onPressed: progress != null
                  ? null
                  : () => context.read<ShareLinkCubit>().download(file),
              icon: progress != null
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, value: progress == 0 ? null : progress),
                    )
                  : const Icon(Icons.download),
              label: Text(l10n.download),
            ),
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

  const _ShareChildRow({required this.file, this.progress, this.error});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
      trailing: file.isFolder
          ? null
          : progress != null
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, value: progress == 0 ? null : progress),
                )
              : IconButton(
                  icon: const Icon(Icons.download),
                  tooltip: l10n.download,
                  onPressed: () => context.read<ShareLinkCubit>().download(file),
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

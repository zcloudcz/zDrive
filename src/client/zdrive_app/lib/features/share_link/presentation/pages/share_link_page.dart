import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/error_message.dart';
import '../../../../shared/l10n/app_localizations.dart';
import '../../../../shared/l10n/relative_time.dart';
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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: BlocBuilder<ShareLinkCubit, ShareLinkState>(
              builder: (context, state) => switch (state) {
                ShareLinkLoading() => const Center(child: CircularProgressIndicator()),
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
                ShareLinkLoaded() => _ShareLinkLoadedView(state: state),
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared by the not-found, password-protected and failure states — an
/// icon, a message, an optional retry, and always the sign-in fallback.
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!, textAlign: TextAlign.center),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
          const SizedBox(height: 16),
          TextButton(onPressed: () => context.go('/login'), child: Text(l10n.openZDrive)),
        ],
      ),
    );
  }
}

class _ShareLinkLoadedView extends StatelessWidget {
  final ShareLinkLoaded state;

  const _ShareLinkLoadedView({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final children = state.children;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.current.isFolder) _Breadcrumbs(state: state),
          const SizedBox(height: 8),
          if (children == null)
            Expanded(
              child: Center(
                child: _SingleFileCard(
                  file: state.current,
                  progress: state.downloadProgress[state.current.id],
                  error: state.downloadErrors[state.current.id],
                ),
              ),
            )
          else if (children.isEmpty)
            Expanded(child: Center(child: Text(l10n.noFiles)))
          else
            Expanded(
              child: ListView.builder(
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
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => context.go('/login'),
              child: Text(l10n.openZDrive),
            ),
          ),
        ],
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
  final double? progress;
  final Object? error;

  const _SingleFileCard({required this.file, this.progress, this.error});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(iconForFile(isFolder: file.isFolder, mimeType: file.mimeType), size: 72),
        const SizedBox(height: 16),
        Text(file.name, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(
          '${formatFileSize(file.sizeBytes)} · ${formatRelativeTime(file.updatedAt, l10n.localeName)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        if (error != null) ...[
          Text(describeError(error!, l10n), style: TextStyle(color: Theme.of(context).colorScheme.error)),
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

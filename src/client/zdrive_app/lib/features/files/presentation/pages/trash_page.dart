import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/error_message.dart';
import '../../domain/file_item.dart';
import '../../domain/file_repository.dart';
import '../widgets/file_icon.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  final FileRepository _repository = getIt<FileRepository>();
  List<FileItem>? _files;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 0;
  String? _restoringId;
  bool _confirmingEmpty = false;
  bool _emptying = false;
  Object? _error;

  bool get _busy =>
      _loading || _restoringId != null || _confirmingEmpty || _emptying;

  @override
  void initState() {
    super.initState();
    _loadTrash();
  }

  Future<void> _loadTrash({bool loadMore = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loadingMore = loadMore;
      _error = null;
    });
    try {
      final result = await _repository.listTrash(
        page: loadMore ? _page + 1 : 1,
      );
      if (!mounted) return;
      setState(() {
        _files = loadMore ? [...?_files, ...result.items] : result.items;
        _page = result.page;
        _hasMore = result.hasMore;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.trash),
        actions: [
          if (_files != null && _files!.isNotEmpty)
            TextButton(
              onPressed: _busy ? null : _confirmEmptyTrash,
              child: _emptying
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: l10n.emptyTrash,
                      ),
                    )
                  : Text(l10n.emptyTrash),
            ),
        ],
      ),
      body: _buildBody(context, l10n),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_loading && _files == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: () async {
        if (!_busy) await _loadTrash();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_loading && !_loadingMore)
            const SliverToBoxAdapter(child: LinearProgressIndicator()),
          if (_files?.isNotEmpty == true)
            SliverList.builder(
              itemCount: _files!.length,
              itemBuilder: (context, index) {
                final file = _files![index];
                return ListTile(
                  key: ValueKey(file.id),
                  leading: FileIcon(file: file),
                  title: Text(file.name),
                  subtitle: Text(timeago.format(file.updatedAt)),
                  trailing: _restoringId == file.id
                      ? SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            semanticsLabel: l10n.restore,
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.restore),
                          tooltip: l10n.restore,
                          onPressed: _busy ? null : () => _restoreFile(file),
                        ),
                );
              },
            ),
          if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      describeError(_error!, l10n),
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _loadTrash(loadMore: _loadingMore),
                      child: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
            )
          else if (_hasMore)
            SliverToBoxAdapter(
              child: Center(
                child: _loadingMore && _loading
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      )
                    : TextButton(
                        onPressed: _busy
                            ? null
                            : () => _loadTrash(loadMore: true),
                        child: Text(l10n.loadMore),
                      ),
              ),
            )
          else if (_files?.isEmpty == true)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.delete_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noFiles,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _restoreFile(FileItem file) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _restoringId = file.id);
    try {
      await _repository.restoreFile(file.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.fileRestored)));
        await _loadTrash();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(describeError(e, l10n))));
      }
    } finally {
      if (mounted) setState(() => _restoringId = null);
    }
  }

  Future<void> _confirmEmptyTrash() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _confirmingEmpty = true);
    var dialogClosed = false;
    void closeDialog(BuildContext dialogContext, bool confirmed) {
      if (dialogClosed) return;
      dialogClosed = true;
      Navigator.of(dialogContext).pop(confirmed);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.confirmEmptyTrash),
        actions: [
          TextButton(
            onPressed: () => closeDialog(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => closeDialog(dialogContext, true),
            child: Text(l10n.emptyTrash),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _confirmingEmpty = false);
    if (confirmed == true) {
      setState(() => _emptying = true);
      try {
        await _repository.emptyTrash();
        if (mounted) await _loadTrash();
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text(describeError(e, l10n))),
          );
        }
      } finally {
        if (mounted) setState(() => _emptying = false);
      }
    }
  }
}

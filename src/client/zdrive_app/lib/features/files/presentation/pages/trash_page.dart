import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../../../core/di/injection.dart';
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
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTrash();
  }

  Future<void> _loadTrash() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repository.listTrash();
      setState(() {
        _files = result.items;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
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
              onPressed: () => _confirmEmptyTrash(context),
              child: Text(l10n.emptyTrash),
            ),
        ],
      ),
      body: _buildBody(context, l10n),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_files == null || _files!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outline,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(l10n.noFiles, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTrash,
      child: ListView.builder(
        itemCount: _files!.length,
        itemBuilder: (context, index) {
          final file = _files![index];
          return ListTile(
            leading: FileIcon(file: file),
            title: Text(file.name),
            subtitle: Text(timeago.format(file.updatedAt)),
            trailing: IconButton(
              icon: const Icon(Icons.restore),
              tooltip: l10n.restore,
              onPressed: () => _restoreFile(file),
            ),
          );
        },
      ),
    );
  }

  Future<void> _restoreFile(FileItem file) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await _repository.restoreFile(file.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.fileRestored)),
        );
        _loadTrash();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _confirmEmptyTrash(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.confirmEmptyTrash),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.emptyTrash),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _repository.emptyTrash();
        if (mounted) _loadTrash();
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      }
    }
  }
}

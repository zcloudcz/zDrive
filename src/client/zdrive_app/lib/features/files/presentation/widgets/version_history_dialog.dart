import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../domain/file_version.dart';

/// Version history of a single file: lists recorded versions (newest first)
/// and lets the user restore an older one. Callbacks are injected by the
/// page, same pattern as ShareDialog.
class VersionHistoryDialog extends StatefulWidget {
  final String fileId;
  final String fileName;
  final Future<List<FileVersion>> Function(String fileId) onLoadVersions;
  final Future<FileVersion> Function(String fileId, String versionId) onRestore;

  const VersionHistoryDialog({
    super.key,
    required this.fileId,
    required this.fileName,
    required this.onLoadVersions,
    required this.onRestore,
  });

  @override
  State<VersionHistoryDialog> createState() => _VersionHistoryDialogState();
}

class _VersionHistoryDialogState extends State<VersionHistoryDialog> {
  List<FileVersion>? _versions;
  bool _restoring = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final versions = await widget.onLoadVersions(widget.fileId);
      if (mounted) setState(() => _versions = versions);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _restore(FileVersion version) async {
    final l10n = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.confirmRestoreVersion),
        content: Text(l10n.versionLabel(version.versionNumber)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.restoreVersion),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _restoring = true;
      _error = null;
    });
    try {
      await widget.onRestore(widget.fileId, version.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.versionRestored)),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text('${l10n.versionHistory} — ${widget.fileName}'),
      content: SizedBox(
        width: 420,
        child: _buildBody(l10n),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_error != null) {
      return Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error));
    }
    if (_versions == null) {
      return const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_versions!.isEmpty) {
      return Text(l10n.noVersions);
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: _versions!.length,
      itemBuilder: (context, index) {
        final version = _versions![index];
        final isLatest = index == 0;

        return ListTile(
          dense: true,
          leading: const Icon(Icons.history),
          title: Text(l10n.versionLabel(version.versionNumber)),
          subtitle: Text(
            [
              _formatSize(version.sizeBytes),
              timeago.format(version.createdAt),
              if (version.comment?.isNotEmpty == true) version.comment!,
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: isLatest
              ? Chip(label: Text(l10n.latestVersion), visualDensity: VisualDensity.compact)
              : IconButton(
                  icon: const Icon(Icons.restore),
                  tooltip: l10n.restoreVersion,
                  onPressed: _restoring ? null : () => _restore(version),
                ),
        );
      },
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../../../core/network/api_constants.dart';
import '../../domain/file_item.dart';

class ShareDialog extends StatefulWidget {
  final String fileId;
  final Future<ShareInfo> Function(
      String fileId, SharePermission permission, DateTime? expiresAt) onShare;

  const ShareDialog({
    super.key,
    required this.fileId,
    required this.onShare,
  });

  @override
  State<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<ShareDialog> {
  SharePermission _permission = SharePermission.read;
  DateTime? _expiresAt;
  ShareInfo? _shareInfo;
  bool _loading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.shareLink,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<SharePermission>(
            initialValue: _permission,
            decoration: InputDecoration(labelText: l10n.permission),
            items: [
              DropdownMenuItem(
                value: SharePermission.read,
                child: Text(l10n.readOnly),
              ),
              DropdownMenuItem(
                value: SharePermission.write,
                child: Text(l10n.readWrite),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _permission = value);
            },
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.expiresAt),
            subtitle: Text(_expiresAt?.toString().split('.').first ?? l10n.never),
            trailing: IconButton(
              icon: const Icon(Icons.calendar_today),
              onPressed: _pickExpiryDate,
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_shareInfo != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _buildShareUrl(_shareInfo!.linkToken),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: l10n.copyLink,
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(
                              text: _buildShareUrl(_shareInfo!.linkToken)),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.linkCopied)),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _loading ? null : _generateLink,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.shareLink),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _expiresAt = picked);
    }
  }

  Future<void> _generateLink() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await widget.onShare(
        widget.fileId,
        _permission,
        _expiresAt,
      );
      setState(() {
        _shareInfo = info;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _buildShareUrl(String token) {
    return '${ApiConstants.baseUrl}/share/$token';
  }
}

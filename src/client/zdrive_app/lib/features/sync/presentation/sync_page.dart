import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../../core/di/injection.dart';
import '../../../core/storage/app_preferences.dart';
import '../data/pull_sync_service.dart';
import '../data/sync_coordinator.dart';
import '../data/sync_remote_data_source.dart';
import '../domain/sync_mirror_entry.dart';
import '../domain/sync_models.dart';
import 'sync_bloc.dart';

class SyncPage extends StatelessWidget {
  const SyncPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SyncBloc(
        dataSource: getIt<SyncRemoteDataSource>(),
        syncCoordinator: getIt<SyncCoordinator>(),
        pullService: getIt<PullSyncService>(),
        preferences: getIt<AppPreferences>(),
      )..add(const LoadSyncStatus()),
      child: const _SyncView(),
    );
  }
}

class _SyncView extends StatelessWidget {
  const _SyncView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncStatus)),
      body: BlocBuilder<SyncBloc, SyncState>(
        builder: (context, state) {
          if (state is SyncLoading || state is SyncInitial) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is SyncError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        context.read<SyncBloc>().add(const LoadSyncStatus()),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            );
          }

          if (state is SyncLoaded) {
            return _SyncLoadedBody(state: state);
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _SyncLoadedBody extends StatelessWidget {
  final SyncLoaded state;

  const _SyncLoadedBody({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Nothing has ever synced: no registered devices AND no conflicts. This
    // is the only case with nothing to list, so it is the only case that
    // gets a full-page message instead of the device/conflict list below —
    // a fresh account must not be told "up to date" before anything has
    // happened.
    if (state.devices.isEmpty && state.conflicts.isEmpty) {
      return Column(
        children: [
          _FolderStatusTile(state: state),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.devices_other,
                      size: 64, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(l10n.syncNoDevices, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      children: [
        _FolderStatusTile(state: state),
        if (state.conflicts.isEmpty)
          ListTile(
            leading: Icon(Icons.sync, color: Theme.of(context).colorScheme.primary),
            title: Text(l10n.allSynced),
            subtitle: Text(l10n.syncDescription),
          )
        else ...[
          _SectionHeader(title: l10n.syncConflicts),
          for (final conflict in state.conflicts) _ConflictTile(conflict: conflict),
        ],
        if (state.failedEvents.isNotEmpty) ...[
          _SectionHeader(title: l10n.syncSkippedItems),
          for (final failed in state.failedEvents) _FailedEventTile(failed: failed),
        ],
        _SectionHeader(title: l10n.syncDevices),
        if (state.devices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(l10n.syncNoDevices),
          )
        else
          for (final device in state.devices) _DeviceTile(device: device),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final SyncDevice device;

  const _DeviceTile({required this.device});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      leading: const Icon(Icons.devices),
      title: Text(device.name),
      subtitle: Text(
        device.lastSyncAt != null ? timeago.format(device.lastSyncAt!) : l10n.syncNeverSynced,
      ),
    );
  }
}

/// This device's own pull status — distinct from the account-wide
/// devices/conflicts lists below it. Honest about what pull-only sync can
/// and cannot claim yet: no folder picked, actively pulling, failed, or
/// caught up are all different states, so none of them get to borrow
/// "Everything is synced" (that line describes the account, not this
/// installation's pull loop).
class _FolderStatusTile extends StatelessWidget {
  final SyncLoaded state;

  const _FolderStatusTile({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (state.syncFolderPath == null) {
      return ListTile(
        leading: const Icon(Icons.create_new_folder_outlined),
        title: Text(l10n.syncChooseFolder),
        subtitle: Text(l10n.syncFolderNotConfigured),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _chooseFolder(context),
      );
    }

    if (state.isPulling) {
      return ListTile(
        leading: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text(l10n.syncPulling),
        subtitle: Text(state.syncFolderPath!),
      );
    }

    if (state.pullError != null) {
      return ListTile(
        leading: Icon(Icons.sync_problem, color: Theme.of(context).colorScheme.error),
        title: Text(state.pullError!),
        subtitle: Text(state.syncFolderPath!),
      );
    }

    // A completed pull with something left quarantined (see F1/F3/F5 in the
    // PR #12 review) is not "up to date" — that line must not claim more
    // than pull actually delivered. The skipped-items section below the
    // fold has the detail; this just says something needs a look.
    if (state.failedEvents.isNotEmpty) {
      return ListTile(
        leading: Icon(Icons.warning_amber, color: Theme.of(context).colorScheme.error),
        title: Text(l10n.syncItemsSkipped),
        subtitle: Text(state.syncFolderPath!),
      );
    }

    return ListTile(
      leading: Icon(Icons.check_circle_outline, color: Theme.of(context).colorScheme.primary),
      title: Text(l10n.syncDeviceUpToDate),
      subtitle: Text(state.syncFolderPath!),
    );
  }

  Future<void> _chooseFolder(BuildContext context) async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || !context.mounted) return;
    final l10n = AppLocalizations.of(context)!;

    // Pull never overwrites a file it did not itself write (see F3), but a
    // folder that already has content in it is still worth a heads-up
    // before syncing starts writing into it — the user may not have
    // intended to point sync at, say, their whole Documents folder.
    final isNonEmpty = await Directory(path).exists() &&
        !(await Directory(path).list().isEmpty);
    if (isNonEmpty && context.mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(l10n.syncFolderNotEmptyTitle),
          content: Text(l10n.syncFolderNotEmptyMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
      if (proceed != true || !context.mounted) return;
    }

    if (!context.mounted) return;
    context.read<SyncBloc>().add(SyncFolderChosen(path));
  }
}

class _ConflictTile extends StatelessWidget {
  final SyncConflict conflict;

  const _ConflictTile({required this.conflict});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.warning_amber, color: Theme.of(context).colorScheme.error),
      title: Text(conflict.fileId),
      subtitle: Text('${conflict.status} · ${timeago.format(conflict.createdAt)}'),
    );
  }
}

class _FailedEventTile extends StatelessWidget {
  final SyncFailedEvent failed;

  const _FailedEventTile({required this.failed});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
      title: Text(failed.fileId),
      subtitle: Text(failed.reason),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../../core/di/injection.dart';
import '../data/sync_remote_data_source.dart';
import '../domain/sync_models.dart';
import 'sync_bloc.dart';

class SyncPage extends StatelessWidget {
  const SyncPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SyncBloc(dataSource: getIt<SyncRemoteDataSource>())
        ..add(const LoadSyncStatus()),
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

    // Nothing to list. Which empty state applies depends on *why* there is
    // nothing: zero registered devices means sync has never happened (not
    // "up to date" — a fresh account must not be told everything is fine
    // before anything has happened), whereas devices with zero conflicts
    // really is the synced-and-happy case.
    if (state.conflicts.isEmpty) {
      return Center(
        child: state.devices.isEmpty
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.devices_other,
                      size: 64, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(l10n.syncNoDevices, style: Theme.of(context).textTheme.titleMedium),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sync, size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(l10n.allSynced, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(l10n.syncDescription, style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center),
                ],
              ),
      );
    }

    return ListView(
      children: [
        _SectionHeader(title: l10n.syncConflicts),
        for (final conflict in state.conflicts) _ConflictTile(conflict: conflict),
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

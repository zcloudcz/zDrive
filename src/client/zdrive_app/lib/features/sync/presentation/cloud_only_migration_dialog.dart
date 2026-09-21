import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../shared/l10n/app_localizations.dart';
import 'sync_bloc.dart';

/// Opens [CloudOnlyMigrationDialog] when [SyncBloc] says the one-time
/// cloud-only migration is due. Placed under the desktop-only SyncBloc
/// provider (see buildSyncShellProvider), so on web and mobile, where there is
/// no SyncBloc, it does not exist at all.
class CloudOnlyMigrationHost extends StatelessWidget {
  final Widget child;

  const CloudOnlyMigrationHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return BlocListener<SyncBloc, SyncState>(
      listenWhen: (previous, current) => _migrationOf(previous) == null && _migrationOf(current) != null,
      listener: (context, _) {
        final bloc = context.read<SyncBloc>();
        showDialog<void>(
          context: context,
          // Only the buttons answer it: a stray click outside must not count
          // as (or be mistaken for) a decision.
          barrierDismissible: false,
          builder: (_) => BlocProvider.value(value: bloc, child: const CloudOnlyMigrationDialog()),
        );
      },
      child: child,
    );
  }
}

CloudOnlyMigration? _migrationOf(SyncState state) => state is SyncLoaded ? state.migration : null;

/// The one-time "free the space the old sync used" dialog: question, then
/// progress while freeing, then the result. All of it is driven by
/// [SyncLoaded.migration]; the dialog pops itself when that becomes null.
class CloudOnlyMigrationDialog extends StatelessWidget {
  const CloudOnlyMigrationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SyncBloc, SyncState>(
      listenWhen: (previous, current) => _migrationOf(previous) != null && _migrationOf(current) == null,
      listener: (context, _) => Navigator.of(context).pop(),
      builder: (context, state) {
        final migration = _migrationOf(state);
        if (state is! SyncLoaded || migration == null) return const SizedBox.shrink();
        final l10n = AppLocalizations.of(context)!;
        final bloc = context.read<SyncBloc>();
        final result = migration.result;

        if (result != null) {
          return AlertDialog(
            title: Text(l10n.freeUpSpace),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.cloudMigrationFreed(result.freed, formatFileSize(result.freedBytes))),
                  if (result.skippedUnsynced.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(l10n.freeUpSkippedUnsynced(result.skippedUnsynced.length)),
                  ],
                  if (result.keptPinned > 0) ...[
                    const SizedBox(height: 8),
                    Text(l10n.freeUpKeptPinned(result.keptPinned)),
                  ],
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => bloc.add(const CloudOnlyMigrationAcknowledged()),
                child: Text(l10n.close),
              ),
            ],
          );
        }

        if (migration.running) {
          final progress = state.progress;
          final done = progress == null ? 0 : progress.completedFiles + progress.failedFiles;
          // PopScope: the run is not cancellable from here, so Esc/back must
          // not close the dialog and hide it.
          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: Text(l10n.cloudMigrationWorking),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (progress != null && progress.totalFiles > 0)
                    Text(l10n.syncProgressCounts(progress.completedFiles, progress.totalFiles, progress.remainingFiles)),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    // The total is only an estimate (kept files count too), so
                    // clamp instead of ever showing more than full.
                    value: progress == null || progress.totalFiles == 0
                        ? null
                        : (done / progress.totalFiles).clamp(0.0, 1.0),
                  ),
                ],
              ),
            ),
          );
        }

        return AlertDialog(
          title: Text(l10n.cloudMigrationTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.cloudMigrationBody(
                  migration.estimate.count,
                  formatFileSize(migration.estimate.bytes),
                )),
                const SizedBox(height: 12),
                Text(l10n.cloudMigrationReassure),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => bloc.add(const CloudOnlyMigrationChosen(CloudOnlyMigrationChoice.later)),
              child: Text(l10n.cloudMigrationLater),
            ),
            OutlinedButton(
              onPressed: () => bloc.add(const CloudOnlyMigrationChosen(CloudOnlyMigrationChoice.keepAll)),
              child: Text(l10n.cloudMigrationKeepAll),
            ),
            FilledButton(
              onPressed: () => bloc.add(const CloudOnlyMigrationChosen(CloudOnlyMigrationChoice.freeUp)),
              child: Text(l10n.freeUpSpace),
            ),
          ],
        );
      },
    );
  }
}

/// Human-readable size for the dialog ("up to 1.4 GB"). Same units as the
/// version-history dialog's private formatter, which is not reachable from here.
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

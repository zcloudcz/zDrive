import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/events/remote_file_change_notifier.dart';
import 'package:zdrive_app/core/storage/app_preferences.dart';
import 'package:zdrive_app/features/sync/data/pull_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sync_coordinator.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_entry.dart';
import 'package:zdrive_app/features/sync/domain/sync_progress.dart';
import 'package:zdrive_app/features/sync/presentation/sync_bloc.dart';

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

class MockSyncCoordinator extends Mock implements SyncCoordinator {}

class MockPullSyncService extends Mock implements PullSyncService {}

class MockAppPreferences extends Mock implements AppPreferences {}

class MockRemoteFileChangeNotifier extends Mock implements RemoteFileChangeNotifier {}

/// The one-time cloud-only migration as SyncBloc state: asked at most once per
/// session, "Decide later" persists nothing (that lives in the coordinator, see
/// cloud_only_migration_test.dart), and a failed run does not crash the bloc.
void main() {
  late MockSyncCoordinator coordinator;
  late MockPullSyncService pull;
  const estimate = FreeableEstimate(count: 3, bytes: 3000);
  const seeded = SyncLoaded(devices: [], syncFolderPath: '/local/sync');

  setUpAll(() {
    registerFallbackValue(SyncProgressTracker((_) {}));
  });

  setUp(() {
    coordinator = MockSyncCoordinator();
    pull = MockPullSyncService();
    when(() => pull.getFailedEvents()).thenAnswer((_) async => []);
    when(() => coordinator.pendingCloudOnlyMigration('/local/sync')).thenAnswer((_) async => estimate);
  });

  SyncBloc build() => SyncBloc(
        dataSource: MockSyncRemoteDataSource(),
        syncCoordinator: coordinator,
        pullService: pull,
        preferences: MockAppPreferences(),
        remoteChangeNotifier: MockRemoteFileChangeNotifier(),
        userId: 'user-1',
      );

  Future<void> settle() => pumpEventQueue();

  CloudOnlyMigration? migrationOf(SyncBloc bloc) => (bloc.state as SyncLoaded).migration;

  blocTest<SyncBloc, SyncState>(
    'Check_MigrationDue_ExposesEstimateToTheDialog',
    build: build,
    seed: () => seeded,
    act: (bloc) => bloc.add(const CloudOnlyMigrationCheckRequested()),
    expect: () => [
      const SyncLoaded(devices: [], syncFolderPath: '/local/sync', migration: CloudOnlyMigration(estimate)),
    ],
  );

  blocTest<SyncBloc, SyncState>(
    'Check_NothingToMigrate_EmitsNothing',
    build: build,
    seed: () => seeded,
    setUp: () => when(() => coordinator.pendingCloudOnlyMigration(any())).thenAnswer((_) async => null),
    act: (bloc) => bloc.add(const CloudOnlyMigrationCheckRequested()),
    expect: () => <SyncState>[],
  );

  blocTest<SyncBloc, SyncState>(
    'Check_NoFolderConfigured_NeverAsksTheCoordinator',
    build: build,
    seed: () => const SyncLoaded(devices: []),
    act: (bloc) => bloc.add(const CloudOnlyMigrationCheckRequested()),
    expect: () => <SyncState>[],
    verify: (_) => verifyNever(() => coordinator.pendingCloudOnlyMigration(any())),
  );

  blocTest<SyncBloc, SyncState>(
    'Check_RequestedTwiceInOneSession_IsOnlyAskedOnce',
    build: build,
    seed: () => seeded,
    act: (bloc) async {
      bloc.add(const CloudOnlyMigrationCheckRequested());
      bloc.add(const CloudOnlyMigrationCheckRequested());
      await settle();
    },
    verify: (_) => verify(() => coordinator.pendingCloudOnlyMigration('/local/sync')).called(1),
  );

  test('DecideLater_ClosesWithoutPersistingAndIsNotOfferedAgainThisSession', () async {
    final bloc = build()..emit(seeded);
    addTearDown(bloc.close);

    bloc.add(const CloudOnlyMigrationCheckRequested());
    await settle();
    expect(migrationOf(bloc), isNotNull);

    bloc.add(const CloudOnlyMigrationChosen(CloudOnlyMigrationChoice.later));
    await settle();
    expect(migrationOf(bloc), isNull);

    // e.g. a reload of the sync status in the same session
    bloc.add(const CloudOnlyMigrationCheckRequested());
    await settle();
    expect(migrationOf(bloc), isNull);
    verify(() => coordinator.pendingCloudOnlyMigration('/local/sync')).called(1);
    verifyNever(() => coordinator.freeUpEverythingUnpinned(any(), progress: any(named: 'progress')));
    verifyNever(() => coordinator.keepEverythingOnDevice(any()));
  });

  test('FreeUp_Success_ShowsProgressThenResultAndBumpsOfflineRevision', () async {
    final result = FreeUpResult()
      ..freed = 2
      ..freedBytes = 2000
      ..keptPinned = 1
      ..skippedUnsynced.add('/local/sync/edited.txt');
    when(() => coordinator.freeUpEverythingUnpinned('/local/sync', progress: any(named: 'progress')))
        .thenAnswer((inv) async {
      final tracker = inv.namedArguments[#progress] as SyncProgressTracker;
      tracker.beginPhase(SyncPhase.deleting, totalFiles: 3);
      await Future<void>.delayed(Duration.zero);
      return result;
    });
    final bloc = build()..emit(seeded);
    addTearDown(bloc.close);
    final states = <SyncLoaded>[];
    final sub = bloc.stream.listen((s) => states.add(s as SyncLoaded));
    addTearDown(sub.cancel);

    bloc.add(const CloudOnlyMigrationCheckRequested());
    await settle();
    bloc.add(const CloudOnlyMigrationChosen(CloudOnlyMigrationChoice.freeUp));
    await settle();

    expect(states.any((s) => s.migration?.running == true), isTrue);
    expect(states.any((s) => s.migration?.running == true && s.progress?.totalFiles == 3), isTrue);
    final done = bloc.state as SyncLoaded;
    expect(done.migration!.running, isFalse);
    expect(done.migration!.result, same(result));
    expect(done.progress, isNull);
    expect(done.offlineRevision, 1);

    bloc.add(const CloudOnlyMigrationAcknowledged());
    await settle();
    expect(migrationOf(bloc), isNull);
  });

  test('FreeUp_ChosenTwice_RunsOnce', () async {
    when(() => coordinator.freeUpEverythingUnpinned(any(), progress: any(named: 'progress')))
        .thenAnswer((_) async => FreeUpResult());
    final bloc = build()..emit(seeded);
    addTearDown(bloc.close);
    bloc.add(const CloudOnlyMigrationCheckRequested());
    await settle();

    bloc.add(const CloudOnlyMigrationChosen(CloudOnlyMigrationChoice.freeUp));
    bloc.add(const CloudOnlyMigrationChosen(CloudOnlyMigrationChoice.freeUp));
    await settle();

    verify(() => coordinator.freeUpEverythingUnpinned('/local/sync', progress: any(named: 'progress'))).called(1);
  });

  test('FreeUp_Fails_ClosesDialogReportsErrorAndStaysAliveButIsNotOfferedAgainThisSession', () async {
    when(() => coordinator.freeUpEverythingUnpinned(any(), progress: any(named: 'progress')))
        .thenThrow(Exception('disk on fire'));
    final bloc = build()..emit(seeded);
    addTearDown(bloc.close);
    bloc.add(const CloudOnlyMigrationCheckRequested());
    await settle();

    bloc.add(const CloudOnlyMigrationChosen(CloudOnlyMigrationChoice.freeUp));
    await settle();

    final state = bloc.state as SyncLoaded;
    expect(state.migration, isNull);
    expect(state.pullError, contains('disk on fire'));
    // Alive: a later event still works, and the session does not re-ask.
    bloc.add(const CloudOnlyMigrationCheckRequested());
    await settle();
    expect(migrationOf(bloc), isNull);
    verify(() => coordinator.pendingCloudOnlyMigration('/local/sync')).called(1);
  });

  test('KeepAll_PinsThroughTheCoordinatorAndClosesTheDialog', () async {
    when(() => coordinator.keepEverythingOnDevice('/local/sync')).thenAnswer((_) async {});
    final bloc = build()..emit(seeded);
    addTearDown(bloc.close);
    bloc.add(const CloudOnlyMigrationCheckRequested());
    await settle();

    bloc.add(const CloudOnlyMigrationChosen(CloudOnlyMigrationChoice.keepAll));
    await settle();

    expect(migrationOf(bloc), isNull);
    verify(() => coordinator.keepEverythingOnDevice('/local/sync')).called(1);
    verifyNever(() => coordinator.freeUpEverythingUnpinned(any(), progress: any(named: 'progress')));
  });

  test('KeepAll_WhileWaitingOnTheLock_IsMarkedKeepingNotFreeingAndClearsStaleSnackbarCounts', () async {
    final gate = Completer<void>();
    when(() => coordinator.keepEverythingOnDevice('/local/sync')).thenAnswer((_) => gate.future);
    final bloc = build()
      ..emit(const SyncLoaded(devices: [], syncFolderPath: '/local/sync', freeUpSkipped: 2, freeUpKeptPinned: 1));
    addTearDown(bloc.close);
    bloc.add(const CloudOnlyMigrationCheckRequested());
    await settle();

    bloc.add(const CloudOnlyMigrationChosen(CloudOnlyMigrationChoice.keepAll));
    await settle();

    final running = bloc.state as SyncLoaded;
    expect(running.migration!.running, isTrue);
    expect(running.migration!.keeping, isTrue);
    // A stale per-item snackbar must not fire when the revision bumps.
    expect(running.freeUpSkipped, 0);
    expect(running.freeUpKeptPinned, 0);

    gate.complete();
    await settle();
    expect(migrationOf(bloc), isNull);
  });

  test('FreeUp_Running_IsNotMarkedKeepingAndClearsStaleSnackbarCounts', () async {
    final gate = Completer<FreeUpResult>();
    when(() => coordinator.freeUpEverythingUnpinned(any(), progress: any(named: 'progress')))
        .thenAnswer((_) => gate.future);
    final bloc = build()
      ..emit(const SyncLoaded(devices: [], syncFolderPath: '/local/sync', freeUpSkipped: 2, freeUpKeptPinned: 1));
    addTearDown(bloc.close);
    bloc.add(const CloudOnlyMigrationCheckRequested());
    await settle();

    bloc.add(const CloudOnlyMigrationChosen(CloudOnlyMigrationChoice.freeUp));
    await settle();

    final running = bloc.state as SyncLoaded;
    expect(running.migration!.running, isTrue);
    expect(running.migration!.keeping, isFalse);
    expect(running.freeUpSkipped, 0);
    expect(running.freeUpKeptPinned, 0);
    gate.complete(FreeUpResult());
    await settle();
  });
}

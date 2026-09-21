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

/// "Always keep on this device" / "Free up space" as SyncBloc events: they go
/// through the coordinator (which serializes them with pull and scan), report
/// progress and failures through the state the sync page already shows, and
/// bump [SyncLoaded.offlineRevision] so the file browser re-reads its markers.
void main() {
  late MockSyncCoordinator coordinator;
  late MockPullSyncService pull;
  final failed = SyncFailedEvent(
    fileId: 'f1',
    eventId: 0,
    reason: 'local conflict',
    failedAt: DateTime.utc(2026, 1, 1),
  );

  setUpAll(() {
    registerFallbackValue(SyncProgressTracker((_) {}));
  });

  setUp(() {
    coordinator = MockSyncCoordinator();
    pull = MockPullSyncService();
    when(() => pull.getFailedEvents()).thenAnswer((_) async => [failed]);
  });

  SyncBloc build() => SyncBloc(
        dataSource: MockSyncRemoteDataSource(),
        syncCoordinator: coordinator,
        pullService: pull,
        preferences: MockAppPreferences(),
        remoteChangeNotifier: MockRemoteFileChangeNotifier(),
        userId: 'user-1',
      );

  const seeded = SyncLoaded(devices: [], syncFolderPath: '/local/sync');

  blocTest<SyncBloc, SyncState>(
    'KeepOnDevice_Success_RunsThroughCoordinatorAndRefreshesFailedEvents',
    build: build,
    seed: () => seeded,
    setUp: () {
      when(() => coordinator.keepOnDevice('doc-1', '/local/sync', progress: any(named: 'progress')))
          .thenAnswer((_) async {});
    },
    act: (bloc) => bloc.add(const KeepOnDeviceRequested('doc-1')),
    expect: () => [
      SyncLoaded(devices: const [], syncFolderPath: '/local/sync', failedEvents: [failed], offlineRevision: 1),
    ],
    verify: (_) =>
        verify(() => coordinator.keepOnDevice('doc-1', '/local/sync', progress: any(named: 'progress'))).called(1),
  );

  test('KeepOnDevice_HydrateProgress_ShowsUpInSyncStateThroughTheExistingTracker', () async {
    when(() => coordinator.keepOnDevice('doc-1', '/local/sync', progress: any(named: 'progress')))
        .thenAnswer((inv) async {
      final tracker = inv.namedArguments[#progress] as SyncProgressTracker;
      tracker.beginPhase(SyncPhase.downloading);
      tracker.setTotalFiles(4);
    });
    final bloc = build();
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    bloc.emit(seeded);
    final states = <SyncState>[];
    final sub = bloc.stream.listen(states.add);

    bloc.add(const KeepOnDeviceRequested('doc-1'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final withProgress = states.whereType<SyncLoaded>().where((s) => s.progress != null);
    expect(withProgress.map((s) => s.progress!.totalFiles), contains(4));
    expect((states.last as SyncLoaded).progress, isNull);
    await sub.cancel();
    await bloc.close();
  });

  blocTest<SyncBloc, SyncState>(
    'KeepOnDevice_CoordinatorThrows_SurfacesThroughPullErrorAndStillBumpsRevision',
    build: build,
    seed: () => seeded,
    setUp: () {
      when(() => coordinator.keepOnDevice(any(), any(), progress: any(named: 'progress')))
          .thenThrow(Exception('network down'));
    },
    act: (bloc) => bloc.add(const KeepOnDeviceRequested('doc-1')),
    expect: () => [
      isA<SyncLoaded>()
          .having((s) => s.pullError, 'pullError', contains('network down'))
          .having((s) => s.offlineRevision, 'offlineRevision', 1),
    ],
  );

  blocTest<SyncBloc, SyncState>(
    'FreeUpSpace_SomeFilesHaveUnsyncedChanges_ReportsHowManyWereKept',
    build: build,
    seed: () => seeded,
    setUp: () {
      when(() => coordinator.freeUpSpace('doc-1', '/local/sync')).thenAnswer((_) async {
        return FreeUpResult()
          ..freed = 3
          ..skippedUnsynced.addAll(['/local/sync/a.txt', '/local/sync/b.txt']);
      });
    },
    act: (bloc) => bloc.add(const FreeUpSpaceRequested('doc-1')),
    expect: () => [
      SyncLoaded(
        devices: const [],
        syncFolderPath: '/local/sync',
        failedEvents: [failed],
        freeUpSkipped: 2,
        offlineRevision: 1,
      ),
    ],
  );

  blocTest<SyncBloc, SyncState>(
    'FreeUpSpace_AllFreed_ReportsNothingSkipped',
    build: build,
    seed: () => const SyncLoaded(devices: [], syncFolderPath: '/local/sync', freeUpSkipped: 5),
    setUp: () {
      when(() => coordinator.freeUpSpace('doc-1', '/local/sync'))
          .thenAnswer((_) async => FreeUpResult()..freed = 1);
    },
    act: (bloc) => bloc.add(const FreeUpSpaceRequested('doc-1')),
    // The stale count from the previous action is reset, not carried over.
    expect: () => [
      isA<SyncLoaded>().having((s) => s.freeUpSkipped, 'freeUpSkipped', 0),
      isA<SyncLoaded>()
          .having((s) => s.freeUpSkipped, 'freeUpSkipped', 0)
          .having((s) => s.offlineRevision, 'offlineRevision', 1),
    ],
  );

  blocTest<SyncBloc, SyncState>(
    'FreeUpSpace_CoordinatorThrows_SurfacesThroughPullError',
    build: build,
    seed: () => seeded,
    setUp: () {
      when(() => coordinator.freeUpSpace(any(), any())).thenThrow(Exception('disk error'));
    },
    act: (bloc) => bloc.add(const FreeUpSpaceRequested('doc-1')),
    expect: () => [
      isA<SyncLoaded>().having((s) => s.pullError, 'pullError', contains('disk error')),
    ],
  );

  blocTest<SyncBloc, SyncState>(
    'OfflineActions_NoSyncFolderChosen_DoNothing',
    build: build,
    seed: () => const SyncLoaded(devices: []),
    act: (bloc) => bloc
      ..add(const KeepOnDeviceRequested('doc-1'))
      ..add(const FreeUpSpaceRequested('doc-1')),
    expect: () => <SyncState>[],
    verify: (_) {
      verifyNever(() => coordinator.keepOnDevice(any(), any(), progress: any(named: 'progress')));
      verifyNever(() => coordinator.freeUpSpace(any(), any()));
    },
  );
}

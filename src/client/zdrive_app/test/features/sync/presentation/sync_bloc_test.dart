import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/events/remote_file_change_notifier.dart';
import 'package:zdrive_app/core/storage/app_preferences.dart';
import 'package:zdrive_app/features/sync/data/pull_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sync_coordinator.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';
import 'package:zdrive_app/features/sync/domain/sync_models.dart';
import 'package:zdrive_app/features/sync/presentation/sync_bloc.dart';

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

class MockSyncCoordinator extends Mock implements SyncCoordinator {}

class MockPullSyncService extends Mock implements PullSyncService {}

class MockAppPreferences extends Mock implements AppPreferences {}

class MockRemoteFileChangeNotifier extends Mock implements RemoteFileChangeNotifier {}

void main() {
  late MockSyncRemoteDataSource mockDataSource;
  late MockSyncCoordinator mockSyncCoordinator;
  late MockPullSyncService mockPullService;
  late MockAppPreferences mockPreferences;
  late MockRemoteFileChangeNotifier mockRemoteChangeNotifier;
  // Set from inside a syncOnce stub when two runs are in flight at once, and
  // asserted in that test's verify: an expect() inside the stub is swallowed
  // by _runSync's catch (see the coalescing test below).
  var overlapObserved = false;

  setUp(() {
    mockDataSource = MockSyncRemoteDataSource();
    mockSyncCoordinator = MockSyncCoordinator();
    mockPullService = MockPullSyncService();
    mockPreferences = MockAppPreferences();
    mockRemoteChangeNotifier = MockRemoteFileChangeNotifier();
    // Unstubbed: syncFolderPath returns null (mocktail's default for a
    // nullable getter), matching "no folder chosen yet" — the baseline every
    // existing test below assumes, since none of them are about pulling.
    when(() => mockSyncCoordinator.startSession(any())).thenAnswer((_) async {});
  });

  SyncBloc buildBloc({
    Stream<FileSystemEvent> Function(String path)? watch,
    String userId = 'user-1',
  }) => SyncBloc(
        dataSource: mockDataSource,
        syncCoordinator: mockSyncCoordinator,
        pullService: mockPullService,
        preferences: mockPreferences,
        remoteChangeNotifier: mockRemoteChangeNotifier,
        userId: userId,
        watch: watch,
      );

  group('LoadSyncStatus', () {
    // Shared by the round-6 F2 test below only, like pullGate in the
    // 'PullRequested' group — reassigned fresh in that test's own setUp.
    late Completer<List<Map<String, dynamic>>> devicesGate;
    late Completer<void> reachedGetDevices;
    late bool watchStarted;

    blocTest<SyncBloc, SyncState>(
      'emits [SyncLoading, SyncLoaded] with mapped devices',
      build: buildBloc,
      setUp: () {
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => [
              {
                'id': 'dev-1',
                'name': 'Laptop',
                'platform': 'windows',
                'lastSyncAt': '2024-06-01T12:00:00Z',
              },
            ]);
      },
      act: (bloc) => bloc.add(const LoadSyncStatus()),
      expect: () => [
        const SyncLoading(),
        SyncLoaded(
          devices: [
            SyncDevice(
              id: 'dev-1',
              name: 'Laptop',
              platform: 'windows',
              lastSyncAt: DateTime.parse('2024-06-01T12:00:00Z'),
            ),
          ],
        ),
      ],
      // Re-enables syncOnce after a previous session's endSession — see
      // SyncCoordinator.startSession's doc comment.
      verify: (_) => verify(() => mockSyncCoordinator.startSession('user-1')).called(1),
    );

    blocTest<SyncBloc, SyncState>(
      'maps a device with no lastSyncAt to null',
      build: buildBloc,
      setUp: () {
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => [
              {'id': 'dev-1', 'name': 'Phone', 'platform': 'android'},
            ]);
      },
      act: (bloc) => bloc.add(const LoadSyncStatus()),
      expect: () => [
        const SyncLoading(),
        const SyncLoaded(
          devices: [
            SyncDevice(id: 'dev-1', name: 'Phone', platform: 'android'),
          ],
        ),
      ],
    );

    blocTest<SyncBloc, SyncState>(
      'emits [SyncLoading, SyncError] when the data source throws',
      build: buildBloc,
      setUp: () {
        when(() => mockDataSource.getDevices()).thenThrow(Exception('network down'));
      },
      act: (bloc) => bloc.add(const LoadSyncStatus()),
      expect: () => [
        const SyncLoading(),
        isA<SyncError>(),
      ],
    );

    blocTest<SyncBloc, SyncState>(
      'emits [SyncLoading, SyncError] when a device has a malformed field, '
      'instead of crashing with a raw type-cast error',
      build: buildBloc,
      setUp: () {
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => [
              {'id': 'dev-1', 'name': null, 'platform': 'windows'},
            ]);
      },
      act: (bloc) => bloc.add(const LoadSyncStatus()),
      expect: () => [
        const SyncLoading(),
        isA<SyncError>(),
      ],
    );

    blocTest<SyncBloc, SyncState>(
      'emits [SyncLoading, SyncError] when startSession itself fails, '
      'instead of leaving the state at SyncInitial forever — '
      'indistinguishable from SyncLoading in SyncPage, i.e. an endless '
      'spinner with no Retry button (PR #16 review round 2, finding 7)',
      build: buildBloc,
      setUp: () {
        when(() => mockSyncCoordinator.startSession(any()))
            .thenThrow(Exception('sqlite locked'));
      },
      act: (bloc) => bloc.add(const LoadSyncStatus()),
      expect: () => [
        const SyncLoading(),
        isA<SyncError>(),
      ],
    );

    blocTest<SyncBloc, SyncState>(
      'startSession is awaited to completion before syncOnce ever runs — '
      'never resolving startSession here means syncOnce must never be '
      'called either; a future change that stopped awaiting it before '
      'moving on would still let syncOnce run and fail this test (PR #16 '
      'review round 2, test gap #9)',
      build: buildBloc,
      setUp: () {
        when(() => mockSyncCoordinator.startSession(any()))
            .thenAnswer((_) => Completer<void>().future);
        when(() => mockPreferences.syncFolderPath).thenReturn('/local/sync');
      },
      act: (bloc) => bloc.add(const LoadSyncStatus()),
      wait: const Duration(milliseconds: 20),
      verify: (_) {
        verifyNever(() => mockDataSource.getDevices());
        verifyNever(() => mockSyncCoordinator.syncOnce(any()));
      },
    );

    blocTest<SyncBloc, SyncState>(
      'does not re-arm the poll timer or the folder watch when getDevices() '
      'resolves *during* close() itself — _onLoadSyncStatus had no '
      'close()-during-await guard at all before this fix, unlike '
      'SyncFolderChosen\'s round-5 guard (PR #16 review round 6, F2)',
      build: () => buildBloc(watch: (_) {
        watchStarted = true;
        return const Stream<FileSystemEvent>.empty();
      }),
      setUp: () {
        watchStarted = false;
        devicesGate = Completer<List<Map<String, dynamic>>>();
        reachedGetDevices = Completer<void>();
        when(() => mockDataSource.getDevices()).thenAnswer((_) {
          reachedGetDevices.complete();
          return devicesGate.future;
        });
        when(() => mockPreferences.syncFolderPath).thenReturn('/local/sync');
        // Stubbed broadly so that, if the guard is missing, the handler
        // runs to completion and fails on the verifyNever below instead of
        // on an unstubbed-mock error.
        when(() => mockSyncCoordinator.syncOnce(any()))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
      },
      act: (bloc) async {
        bloc.add(const LoadSyncStatus());
        await reachedGetDevices.future;
        // Unlike `await bloc.close(); devicesGate.complete();`, which would
        // only prove the after-close case already covered elsewhere,
        // releasing the gate WHILE close() is still in flight lands
        // getDevices()'s continuation inside the close()-in-progress window
        // this test is pinning.
        final closing = bloc.close();
        devicesGate.complete([]);
        await closing;
      },
      verify: (_) {
        expect(watchStarted, isFalse);
        verifyNever(() => mockSyncCoordinator.syncOnce(any()));
      },
    );
  });

  group('PullRequested', () {
    // Shared by the generation-guard test below only, like pullGate in the
    // 'SyncFolderChosen' group — reassigned fresh in that test's own setUp.
    late Completer<SyncRunResult> pullGate;

    blocTest<SyncBloc, SyncState>(
      'does nothing when no sync folder is configured yet',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: []),
      act: (bloc) => bloc.add(const PullRequested()),
      expect: () => <SyncState>[],
      verify: (_) => verifyNever(() => mockSyncCoordinator.syncOnce(any())),
    );

    blocTest<SyncBloc, SyncState>(
      'syncs once (pull, then push), then refreshes the device list on success',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/local/sync'),
      setUp: () {
        when(() => mockSyncCoordinator.syncOnce('/local/sync'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 2, pushed: 1));
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => [
              {'id': 'dev-1', 'name': 'This PC', 'platform': 'windows'},
            ]);
      },
      act: (bloc) => bloc.add(const PullRequested()),
      expect: () => [
        const SyncLoaded(
          devices: [],
          syncFolderPath: '/local/sync',
          isPulling: true,
        ),
        const SyncLoaded(
          devices: [SyncDevice(id: 'dev-1', name: 'This PC', platform: 'windows')],
          syncFolderPath: '/local/sync',
        ),
      ],
      verify: (_) => verify(() => mockRemoteChangeNotifier.notifyChanged()).called(1),
    );

    blocTest<SyncBloc, SyncState>(
      'does not ping the remote-change notifier when the run applied '
      'nothing — the Files tab has no reason to reload for a no-op pull',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/local/sync'),
      setUp: () {
        when(() => mockSyncCoordinator.syncOnce('/local/sync'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
      },
      act: (bloc) => bloc.add(const PullRequested()),
      verify: (_) {
        // The run must have actually happened: without this, the test also
        // passes when _runSync bails out on a guard and never syncs at all,
        // which would prove nothing about the applied-nothing case.
        verify(() => mockSyncCoordinator.syncOnce('/local/sync')).called(1);
        verifyNever(() => mockRemoteChangeNotifier.notifyChanged());
      },
    );

    blocTest<SyncBloc, SyncState>(
      'surfaces the error and clears isPulling when the sync fails',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/local/sync'),
      setUp: () {
        when(() => mockSyncCoordinator.syncOnce('/local/sync'))
            .thenThrow(Exception('disk full'));
      },
      act: (bloc) => bloc.add(const PullRequested()),
      expect: () => [
        const SyncLoaded(
          devices: [],
          syncFolderPath: '/local/sync',
          isPulling: true,
        ),
        const SyncLoaded(
          devices: [],
          syncFolderPath: '/local/sync',
          pullError: 'Exception: disk full',
        ),
      ],
    );

    blocTest<SyncBloc, SyncState>(
      'never runs two syncs concurrently, but services a request that arrived '
      'mid-run with exactly one trailing run — a file dropped into the folder '
      'while a run was in flight was otherwise picked up by neither (the run '
      'scanned the disk before it existed, the request was dropped) until the '
      'next 30s poll tick',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/local/sync'),
      setUp: () {
        var inFlight = 0;
        overlapObserved = false;
        final firstRun = Completer<SyncRunResult>();
        when(() => mockSyncCoordinator.syncOnce('/local/sync')).thenAnswer((_) {
          inFlight++;
          // RECORDED here, ASSERTED in verify: overlap is only observable
          // from inside the stub (a call count taken at the end cannot tell a
          // trailing run from a concurrent one — SyncCoordinator's own single
          // flight would hand a concurrent caller the same future, letting
          // pull and scan interleave). But an `expect` here runs synchronously
          // inside syncOnce, i.e. inside _runSync's try, whose `catch (e)`
          // swallows TestFailure like any other error and files it in
          // SyncLoaded.pullError — the test then passes while reporting
          // nothing. Verified by probe: an always-failing expect in this stub
          // left the suite green.
          if (inFlight > 1) overlapObserved = true;
          final run = inFlight == 1 ? firstRun.future : Future.value(const SyncRunResult(pulled: 0, pushed: 0));
          return run.whenComplete(() => inFlight--);
        });
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
        // Resolves after both PullRequested events below have been dispatched
        // — the periodic timer (or a watch event) firing while a slow sync (a
        // whole-file transfer) is still in flight.
        Future.delayed(
          const Duration(milliseconds: 20),
          () => firstRun.complete(const SyncRunResult(pulled: 0, pushed: 0)),
        );
      },
      act: (bloc) {
        bloc.add(const PullRequested());
        bloc.add(const PullRequested());
        // A third request in the same window must still collapse into the one
        // trailing run — a burst of watch events must not queue a run each.
        bloc.add(const PullRequested());
      },
      wait: const Duration(milliseconds: 80),
      verify: (_) {
        expect(
          overlapObserved,
          isFalse,
          reason: 'two syncOnce calls were in flight at the same time — the '
              'trailing run must start only after the previous one finished',
        );
        verify(() => mockSyncCoordinator.syncOnce('/local/sync')).called(2);
      },
    );

    blocTest<SyncBloc, SyncState>(
      'a run with nothing requested during it does not trail a second run — '
      'the flag must not latch, or every sync would start another one forever',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/local/sync'),
      setUp: () {
        when(() => mockSyncCoordinator.syncOnce('/local/sync'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
      },
      act: (bloc) => bloc.add(const PullRequested()),
      wait: const Duration(milliseconds: 50),
      verify: (_) => verify(() => mockSyncCoordinator.syncOnce('/local/sync')).called(1),
    );

    blocTest<SyncBloc, SyncState>(
      'a request that arrived during a run is dropped if the folder changed '
      'meanwhile — the trailing run must not sync the new folder on behalf of '
      'a request made about the old one',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/old'),
      setUp: () {
        final oldRun = Completer<SyncRunResult>();
        when(() => mockSyncCoordinator.syncOnce('/old'))
            .thenAnswer((_) => oldRun.future);
        when(() => mockSyncCoordinator.syncOnce('/new'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockSyncCoordinator.resetForNewFolder('/new'))
            .thenAnswer((_) async {});
        when(() => mockPreferences.setSyncFolderPath('/new')).thenAnswer((_) async {});
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
        Future.delayed(
          const Duration(milliseconds: 30),
          () => oldRun.complete(const SyncRunResult(pulled: 0, pushed: 0)),
        );
      },
      act: (bloc) {
        bloc.add(const PullRequested());
        // Arrives while /old is still running, so it is remembered...
        bloc.add(const PullRequested());
        // ...and then the folder switches, which must discard it.
        bloc.add(const SyncFolderChosen('/new'));
      },
      wait: const Duration(milliseconds: 100),
      verify: (_) {
        // Once for the switch's own sync, and NOT a second time on behalf of
        // the remembered request.
        verify(() => mockSyncCoordinator.syncOnce('/new')).called(1);
      },
    );

    blocTest<SyncBloc, SyncState>(
      'the same holds in the opposite order — a request arriving DURING the '
      'switch (while resetForNewFolder waits on the coordinator mutex for the '
      'old run) is about the old folder and must not earn the new one an '
      'extra run',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/old'),
      setUp: () {
        // A run for /old genuinely in flight, so the request in step 3 below
        // hits the isPulling guard and arms the flag. Without this the
        // request would just start its own run and never exercise the window.
        final oldRun = Completer<SyncRunResult>();
        when(() => mockSyncCoordinator.syncOnce('/old'))
            .thenAnswer((_) => oldRun.future);
        // resetForNewFolder awaits the coordinator's mutex in production,
        // i.e. the old run; held open here to stand in for that wait, which
        // is the window the generation bump alone does not cover.
        final resetGate = Completer<void>();
        when(() => mockSyncCoordinator.resetForNewFolder('/new'))
            .thenAnswer((_) => resetGate.future);
        when(() => mockSyncCoordinator.syncOnce('/new'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockPreferences.setSyncFolderPath('/new')).thenAnswer((_) async {});
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
        Future.delayed(const Duration(milliseconds: 40), () {
          oldRun.complete(const SyncRunResult(pulled: 0, pushed: 0));
          resetGate.complete();
        });
      },
      act: (bloc) async {
        // 1. a run for /old starts and stays in flight
        bloc.add(const PullRequested());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        // 2. the switch begins: bumps the generation (clearing the flag) and
        //    then parks on resetForNewFolder
        bloc.add(const SyncFolderChosen('/new'));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        // 3. a poll tick lands in that window — about /old, since that is
        //    what is still running
        bloc.add(const PullRequested());
      },
      wait: const Duration(milliseconds: 150),
      verify: (_) => verify(() => mockSyncCoordinator.syncOnce('/new')).called(1),
    );

    blocTest<SyncBloc, SyncState>(
      'a run still in flight when the bloc closes does not spend a '
      'getDevices/getFailedEvents request once it wakes up stale — the '
      'generation is checked right after syncOnce, before those two calls, '
      'not after both of them have already run (PR #16 review round 4, N1)',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/local/sync'),
      setUp: () {
        pullGate = Completer<SyncRunResult>();
        when(() => mockSyncCoordinator.syncOnce('/local/sync')).thenAnswer((_) => pullGate.future);
        // Stubbed even though the fix never reaches these calls: reverting
        // the fix must fail this test on the verifyNever assertions below,
        // not on an unstubbed-mock error.
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
      },
      act: (bloc) async {
        bloc.add(const PullRequested());
        await bloc.stream.firstWhere((s) => s is SyncLoaded && s.isPulling);
        // Bumps _syncGeneration (see close()'s doc comment) while syncOnce
        // is still pending — the run's tail wakes up stale below.
        await bloc.close();
        pullGate.complete(const SyncRunResult(pulled: 1, pushed: 1));
        // Two microtask flushes: one for `await syncOnce` to resume, one for
        // the generation check that immediately follows it to run and
        // return — no timer, no arbitrary delay, just letting the already
        // fully-resolved chain settle.
        await Future<void>.value();
        await Future<void>.value();
      },
      verify: (_) {
        verifyNever(() => mockDataSource.getDevices());
        verifyNever(() => mockPullService.getFailedEvents());
      },
    );
  });

  group('SyncFolderChosen', () {
    // Shared by the F2/finding-4/finding-1 race tests below only —
    // reassigned fresh in each test's own setUp, like watchController in the
    // 'folder watch' group.
    late Completer<SyncRunResult> pullGate;
    // Gates syncOnce('/new') for the round-3 finding-1 generation tests
    // below, so the new folder's own run can be held open independently of
    // the stale old run's pullGate.
    late Completer<SyncRunResult> newSyncGate;
    // Shared by the round-5 C2 test only: gates the stale old run's
    // getDevices() call so it can be released after the new folder's own
    // run has already finished, and signals once that call has actually
    // been reached.
    late Completer<List<Map<String, dynamic>>> devicesGate;
    late Completer<void> reachedGetDevices;
    // Shared by the round-5 C1 test only: gates resetForNewFolder so
    // bloc.close() can be called while _onSyncFolderChosen is still awaiting
    // it, and signals once that call has actually been reached.
    late Completer<void> resetGate;
    late Completer<void> reachedReset;
    // Records whether _startWatching's injected watch function was invoked
    // — the round-5 C1 test's proxy for "polling/watching was re-armed".
    late bool watchStarted;

    blocTest<SyncBloc, SyncState>(
      'persists the chosen folder and triggers a sync, when no folder was '
      'configured before (nothing to reset)',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: []),
      setUp: () {
        when(() => mockPreferences.setSyncFolderPath('/new/folder'))
            .thenAnswer((_) async {});
        when(() => mockSyncCoordinator.syncOnce('/new/folder'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
      },
      act: (bloc) => bloc.add(const SyncFolderChosen('/new/folder')),
      expect: () => [
        const SyncLoaded(devices: [], syncFolderPath: '/new/folder'),
        const SyncLoaded(
          devices: [],
          syncFolderPath: '/new/folder',
          isPulling: true,
        ),
        const SyncLoaded(
          devices: [],
          syncFolderPath: '/new/folder',
        ),
      ],
      verify: (_) {
        verify(() => mockPreferences.setSyncFolderPath('/new/folder')).called(1);
        verifyNever(() => mockSyncCoordinator.resetForNewFolder(any()));
      },
    );

    blocTest<SyncBloc, SyncState>(
      'resets the mirror before syncing a different folder than the one '
      'already configured — persisting the new path is now resetForNewFolder\'s '
      'own job, inside its lock (PR #16 review round 2, finding 3), not a '
      'separate call this bloc makes afterwards',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/old/folder'),
      setUp: () {
        when(() => mockSyncCoordinator.resetForNewFolder('/new/folder')).thenAnswer((_) async {});
        when(() => mockSyncCoordinator.syncOnce('/new/folder'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
      },
      act: (bloc) => bloc.add(const SyncFolderChosen('/new/folder')),
      verify: (_) {
        verify(() => mockSyncCoordinator.resetForNewFolder('/new/folder')).called(1);
        verifyNever(() => mockPreferences.setSyncFolderPath(any()));
      },
    );

    blocTest<SyncBloc, SyncState>(
      'does not reset when the "new" folder is the same one already '
      'configured',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/same/folder'),
      setUp: () {
        when(() => mockPreferences.setSyncFolderPath('/same/folder'))
            .thenAnswer((_) async {});
        when(() => mockSyncCoordinator.syncOnce('/same/folder'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
      },
      act: (bloc) => bloc.add(const SyncFolderChosen('/same/folder')),
      verify: (_) => verifyNever(() => mockSyncCoordinator.resetForNewFolder(any())),
    );

    blocTest<SyncBloc, SyncState>(
      'changing the folder while a pull is in flight does not resurrect a '
      'stale isPulling once that pull finishes (PR #16 review round 1, F2) '
      '— resetForNewFolder shares SyncCoordinator\'s mutex with syncOnce, so '
      'it does not resolve until the in-flight pull does; emitting from the '
      'state captured *before* that await would restore isPulling: true '
      'over the pull handler\'s own "finished" update and wedge every later '
      'PullRequested',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/old'),
      setUp: () {
        pullGate = Completer<SyncRunResult>();
        when(() => mockSyncCoordinator.syncOnce('/old')).thenAnswer((_) => pullGate.future);
        // Mirrors the real SyncCoordinator: resetForNewFolder waits on the
        // same mutex syncOnce holds. The extra delay after pullGate settles
        // forces the exact ordering that broke the old code: the pull
        // handler's own "finished" emit (isPulling: false) must land before
        // this resolves, not after.
        when(() => mockSyncCoordinator.resetForNewFolder('/new')).thenAnswer((_) async {
          await pullGate.future;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });
        when(() => mockSyncCoordinator.syncOnce('/new'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
      },
      act: (bloc) async {
        bloc.add(const PullRequested());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const SyncFolderChosen('/new'));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        pullGate.complete(const SyncRunResult(pulled: 1, pushed: 0));
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        final state = bloc.state as SyncLoaded;
        expect(state.syncFolderPath, '/new');
        expect(state.isPulling, isFalse);
        verify(() => mockSyncCoordinator.syncOnce('/new')).called(1);
      },
    );

    blocTest<SyncBloc, SyncState>(
      'switching folders while a pull is in flight for the old one still '
      'syncs the new folder, even though the old pull\'s own finishing '
      'sequence (getDevices/getFailedEvents/its own emit) resumes later on '
      'a stale generation and bails out before touching either call (PR '
      '#16 review round 2, finding 4) — the round-1 fix (F2) re-dispatched '
      'PullRequested, whose isPulling guard ran concurrently with the old '
      'pull\'s handler and could still see it as in flight, silently '
      'dropping the new folder\'s first sync entirely; calling the shared '
      'pull routine directly, with isPulling forced to false in the same '
      'synchronous step as the folder-path emit, removes that race '
      'regardless of how far the old pull has gotten',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/old'),
      setUp: () {
        pullGate = Completer<SyncRunResult>();
        when(() => mockSyncCoordinator.syncOnce('/old')).thenAnswer((_) => pullGate.future);
        // Shares the mutex with syncOnce, same as the real SyncCoordinator —
        // cannot resolve until the old pull's own lock section is done.
        when(() => mockSyncCoordinator.resetForNewFolder('/new')).thenAnswer((_) async {
          await pullGate.future;
        });
        when(() => mockSyncCoordinator.syncOnce('/new'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
        // The old pull's tail resumes once pullGate settles below, but its
        // generation is stale by then (SyncFolderChosen bumped it) and the
        // guard is checked right after syncOnce, before this call (PR #16
        // review round 4, N1) — so only the new folder's own pull ever
        // reaches getDevices, and this stub is never asked to distinguish
        // the two.
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
      },
      act: (bloc) async {
        bloc.add(const PullRequested());
        // Waits for the real state transition (isPulling: true) instead of
        // a timed delay — deterministic proof the old pull's handler has
        // actually started and is suspended on syncOnce('/old').
        await bloc.stream.firstWhere((s) => s is SyncLoaded && s.isPulling);
        bloc.add(const SyncFolderChosen('/new'));
        pullGate.complete(const SyncRunResult(pulled: 1, pushed: 0));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        final state = bloc.state as SyncLoaded;
        expect(state.syncFolderPath, '/new');
        expect(state.isPulling, isFalse);
        verify(() => mockSyncCoordinator.syncOnce('/new')).called(1);
      },
    );

    blocTest<SyncBloc, SyncState>(
      'a stale old-folder pull tail does not clobber the new folder\'s '
      'state once the new run has already reported its own result (PR #16 '
      'review round 3, finding 1) — nothing ties a run\'s tail to the '
      'folder it started for, so whichever of the two settles last used to '
      'win, even when it belongs to a folder nobody is looking at any more',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/old'),
      setUp: () {
        pullGate = Completer<SyncRunResult>();
        newSyncGate = Completer<SyncRunResult>();
        when(() => mockSyncCoordinator.syncOnce('/old')).thenAnswer((_) => pullGate.future);
        when(() => mockSyncCoordinator.resetForNewFolder('/new')).thenAnswer((_) async {});
        when(() => mockSyncCoordinator.syncOnce('/new')).thenAnswer((_) => newSyncGate.future);
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
        // Distinguishes which tail's device list actually landed in state:
        // the FIRST call belongs to the new run (it settles first below),
        // the second to the stale old run.
        var getDevicesCalls = 0;
        when(() => mockDataSource.getDevices()).thenAnswer((_) async {
          getDevicesCalls++;
          return getDevicesCalls == 1
              ? [
                  {'id': 'dev-new', 'name': 'New device', 'platform': 'windows'},
                ]
              : [
                  {'id': 'dev-old', 'name': 'Old device', 'platform': 'windows'},
                ];
        });
      },
      act: (bloc) async {
        bloc.add(const PullRequested());
        await bloc.stream.firstWhere((s) => s is SyncLoaded && s.syncFolderPath == '/old' && s.isPulling);
        bloc.add(const SyncFolderChosen('/new'));
        await bloc.stream.firstWhere((s) => s is SyncLoaded && s.syncFolderPath == '/new' && s.isPulling);
        // The new folder's own run finishes and settles first...
        newSyncGate.complete(const SyncRunResult(pulled: 1, pushed: 0));
        await bloc.stream.firstWhere((s) => s is SyncLoaded && s.syncFolderPath == '/new' && !s.isPulling);
        // ...*then* the stale old run's pull resolves. Its tail
        // (getDevices/getFailedEvents/its own emit) runs entirely after the
        // new folder's own result is already in state.
        pullGate.complete(const SyncRunResult(pulled: 9, pushed: 9));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        final state = bloc.state as SyncLoaded;
        expect(state.syncFolderPath, '/new');
        expect(state.isPulling, isFalse);
        // Only the stale run's device list would appear here if its
        // "finished" emit had been allowed through.
        expect(state.devices, const [SyncDevice(id: 'dev-new', name: 'New device', platform: 'windows')]);
        verify(() => mockSyncCoordinator.syncOnce('/old')).called(1);
        verify(() => mockSyncCoordinator.syncOnce('/new')).called(1);
      },
    );

    blocTest<SyncBloc, SyncState>(
      'an error from a stale old-folder run does not surface as the new '
      'folder\'s pullError once the new run has already succeeded (PR #16 '
      'review round 3, finding 1)',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/old'),
      setUp: () {
        pullGate = Completer<SyncRunResult>();
        newSyncGate = Completer<SyncRunResult>();
        when(() => mockSyncCoordinator.syncOnce('/old')).thenAnswer((_) => pullGate.future);
        when(() => mockSyncCoordinator.resetForNewFolder('/new')).thenAnswer((_) async {});
        when(() => mockSyncCoordinator.syncOnce('/new')).thenAnswer((_) => newSyncGate.future);
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
      },
      act: (bloc) async {
        bloc.add(const PullRequested());
        await bloc.stream.firstWhere((s) => s is SyncLoaded && s.syncFolderPath == '/old' && s.isPulling);
        bloc.add(const SyncFolderChosen('/new'));
        await bloc.stream.firstWhere((s) => s is SyncLoaded && s.syncFolderPath == '/new' && s.isPulling);
        newSyncGate.complete(const SyncRunResult(pulled: 1, pushed: 0));
        await bloc.stream.firstWhere((s) => s is SyncLoaded && s.syncFolderPath == '/new' && !s.isPulling);
        // The stale old run now fails — its error must not be attributed to
        // a folder nobody is even looking at any more.
        pullGate.completeError(Exception('disk full'));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        final state = bloc.state as SyncLoaded;
        expect(state.syncFolderPath, '/new');
        expect(state.pullError, isNull);
      },
    );

    blocTest<SyncBloc, SyncState>(
      'a folder switch that fails surfaces as SyncError instead of leaving '
      'the bloc wedged on a stuck isPulling: true, and the page\'s existing '
      'Retry (LoadSyncStatus) still reaches the coordinator afterwards (PR '
      '#16 review round 4, R1) — before this fix, an uncaught throw from '
      'resetForNewFolder escaped the handler entirely and killed the '
      'bloc\'s event processing for good, so no later PullRequested (the '
      'periodic poll, or Retry\'s own follow-up pull) was ever handled '
      'again short of restarting the app',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/old'),
      setUp: () {
        pullGate = Completer<SyncRunResult>();
        when(() => mockSyncCoordinator.syncOnce('/old')).thenAnswer((_) => pullGate.future);
        when(() => mockSyncCoordinator.resetForNewFolder('/new'))
            .thenThrow(Exception('sqflite clearAll failed'));
        // Retry (LoadSyncStatus) finds the old folder still configured —
        // the failed switch never got far enough to persist '/new'.
        when(() => mockPreferences.syncFolderPath).thenReturn('/old');
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
      },
      act: (bloc) async {
        // A pull for the old folder is in flight — this is what used to end
        // up "stuck" at isPulling: true forever once the switch below threw.
        bloc.add(const PullRequested());
        await bloc.stream.firstWhere((s) => s is SyncLoaded && s.isPulling);
        bloc.add(const SyncFolderChosen('/new'));
        await bloc.stream.firstWhere((s) => s is SyncError);
        // Not a stuck isPulling: true — the bloc left that state behind for
        // the error state, exactly like every other failure in this bloc.
        expect(bloc.state, isA<SyncError>());
        // The old pull's own tail resuming later (if it ever does) must not
        // resurrect a stale state either — see the round-3 generation guard.
        pullGate.complete(const SyncRunResult(pulled: 1, pushed: 0));
        // Retry: the event loop is still alive, so this reaches the
        // coordinator instead of being dropped like it was pre-fix.
        bloc.add(const LoadSyncStatus());
        await bloc.stream.firstWhere((s) => s is SyncLoaded && s.isPulling);
        await bloc.stream.firstWhere((s) => s is SyncLoaded && !s.isPulling);
      },
      verify: (_) => verify(() => mockSyncCoordinator.syncOnce('/old')).called(2),
    );

    blocTest<SyncBloc, SyncState>(
      'a stale old-folder run does not clobber the new folder\'s state by '
      'waking up between getDevices() and the emit, after the new folder\'s '
      'own run has already finished — the generation was checked right '
      'after syncOnce, but not again right before this emit, so a switch '
      'landing during getDevices()/getFailedEvents() was not caught (PR #16 '
      'review round 5, Codex C2)',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/old'),
      setUp: () {
        devicesGate = Completer<List<Map<String, dynamic>>>();
        reachedGetDevices = Completer<void>();
        var getDevicesCalls = 0;
        // syncOnce('/old') resolves immediately — this test is about the
        // two awaits *after* it, not about syncOnce itself.
        when(() => mockSyncCoordinator.syncOnce('/old'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 1, pushed: 0));
        when(() => mockSyncCoordinator.syncOnce('/new'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockSyncCoordinator.resetForNewFolder('/new')).thenAnswer((_) async {});
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
        // The FIRST call is the old run's — held open so the folder switch
        // below can land while it is still in flight. The SECOND call is
        // the new run's own — resolves immediately with a distinct device
        // so a leaked old-run emit is unmistakable in the final state.
        when(() => mockDataSource.getDevices()).thenAnswer((_) {
          getDevicesCalls++;
          if (getDevicesCalls == 1) {
            reachedGetDevices.complete();
            return devicesGate.future;
          }
          return Future.value([
            {'id': 'dev-new', 'name': 'New device', 'platform': 'windows'},
          ]);
        });
      },
      act: (bloc) async {
        bloc.add(const PullRequested());
        // Deterministic proof the old run is suspended inside getDevices(),
        // past its first (post-syncOnce) generation check — not a guessed
        // number of microtask flushes.
        await reachedGetDevices.future;
        bloc.add(const SyncFolderChosen('/new'));
        // Not `!isPulling` alone — _onSyncFolderChosen forces isPulling:
        // false onto the state *before* _runSync('/new') even starts (to
        // stop it seeing a stale isPulling: true and skipping the new
        // folder's first sync — see that emit's own doc comment), so that
        // predicate would match immediately, long before the new run's own
        // getDevices/getFailedEvents tail has actually landed. Waiting for a
        // non-empty device list is what actually proves the new run's own
        // result — not just its isPulling toggle — is the one in state.
        await bloc.stream.firstWhere(
          (s) => s is SyncLoaded && s.syncFolderPath == '/new' && !s.isPulling && s.devices.isNotEmpty,
        );
        // The new folder's own run has already reported its result — now
        // let the stale old run's getDevices() resolve.
        devicesGate.complete([
          {'id': 'dev-old-stale', 'name': 'Old device', 'platform': 'windows'},
        ]);
        // Drains the old run's remaining chain (getFailedEvents, then the
        // emit under test) instead of guessing a microtask count — that
        // chain is one hop longer than the round-4 N1 test's, which only
        // needed to flush a single synchronous check.
        await pumpEventQueue();
      },
      verify: (bloc) {
        final state = bloc.state as SyncLoaded;
        expect(state.syncFolderPath, '/new');
        expect(state.isPulling, isFalse);
        // Only the stale old run's device would appear here if the pre-emit
        // generation check were missing.
        expect(state.devices, const [SyncDevice(id: 'dev-new', name: 'New device', platform: 'windows')]);
      },
    );

    blocTest<SyncBloc, SyncState>(
      'closing the bloc while a folder switch is still awaiting the reset '
      'does not re-arm the poll timer or the folder watch once the reset '
      'resolves — a switch that resumes after close() used to still call '
      '_startPolling/_startWatching, both created *after* close() cancelled '
      'the originals, so they live for the process lifetime: the timer\'s '
      'add() throws an uncaught StateError once it next fires, 30s later, '
      'and the folder watch is never cancelled (PR #16 review round 5, '
      'Codex C1)',
      build: () => buildBloc(watch: (_) {
        watchStarted = true;
        return const Stream<FileSystemEvent>.empty();
      }),
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/old'),
      setUp: () {
        watchStarted = false;
        resetGate = Completer<void>();
        reachedReset = Completer<void>();
        when(() => mockSyncCoordinator.resetForNewFolder('/new')).thenAnswer((_) {
          reachedReset.complete();
          return resetGate.future;
        });
        // Stubbed broadly so that, if the isDone guard is removed, the
        // handler runs to completion and fails on the verifyNever below
        // instead of on an unstubbed-mock error.
        when(() => mockSyncCoordinator.syncOnce('/new'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
      },
      act: (bloc) async {
        bloc.add(const SyncFolderChosen('/new'));
        await reachedReset.future;
        await bloc.close();
        resetGate.complete();
        await Future<void>.value();
        await Future<void>.value();
      },
      verify: (_) {
        expect(watchStarted, isFalse);
        verifyNever(() => mockSyncCoordinator.syncOnce(any()));
      },
    );

    blocTest<SyncBloc, SyncState>(
      'does not re-arm the poll timer or the folder watch when the reset '
      'resolves *during* close() itself, not only after close() has fully '
      'finished — the round-5 C1 test above releases its gate only once '
      '`await bloc.close()` has already completed, so it cannot see this '
      'narrower window: emit.isDone stays false until close() has awaited '
      '_eventController.close() to completion, but isClosed flips '
      'synchronously the instant close() is called, so only checking both '
      'closes the window (PR #16 review round 6, F1)',
      build: () => buildBloc(watch: (_) {
        watchStarted = true;
        return const Stream<FileSystemEvent>.empty();
      }),
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/old'),
      setUp: () {
        watchStarted = false;
        resetGate = Completer<void>();
        reachedReset = Completer<void>();
        when(() => mockSyncCoordinator.resetForNewFolder('/new')).thenAnswer((_) {
          reachedReset.complete();
          return resetGate.future;
        });
        // Stubbed broadly so that, if the guard is missing, the handler
        // runs to completion and fails on the verifyNever below instead of
        // on an unstubbed-mock error.
        when(() => mockSyncCoordinator.syncOnce('/new'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
      },
      act: (bloc) async {
        bloc.add(const SyncFolderChosen('/new'));
        await reachedReset.future;
        // Unlike `await bloc.close(); resetGate.complete();` above, the gate
        // is released WHILE close() is still in flight — not after it has
        // fully finished — to land resetForNewFolder's continuation inside
        // the close()-in-progress window this test is pinning.
        final closing = bloc.close();
        resetGate.complete();
        await closing;
      },
      verify: (_) {
        expect(watchStarted, isFalse);
        verifyNever(() => mockSyncCoordinator.syncOnce(any()));
      },
    );
  });

  group('folder watch', () {
    // Drives the injected watch stream directly instead of touching a real
    // filesystem — the bloc only needs *a* Stream<FileSystemEvent> for the
    // folder path, not a real OS watcher, to prove out its own debounce
    // logic. A plain (non-broadcast) controller is enough: the bloc
    // subscribes to it exactly once, from LoadSyncStatus below.
    late StreamController<FileSystemEvent> watchController;
    // Second controller only the folder-switch test below needs, standing
    // in for the watch stream on a *different* path than watchController.
    late StreamController<FileSystemEvent> oldController;

    setUp(() {
      watchController = StreamController<FileSystemEvent>();
      oldController = StreamController<FileSystemEvent>();
    });

    tearDown(() {
      watchController.close();
      oldController.close();
    });

    blocTest<SyncBloc, SyncState>(
      'a burst of watch events triggers exactly one extra sync, 2s after '
      'the last one',
      build: () => buildBloc(watch: (_) => watchController.stream),
      setUp: () {
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
        when(() => mockPreferences.syncFolderPath).thenReturn('/watched/folder');
        when(() => mockSyncCoordinator.syncOnce('/watched/folder'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
      },
      act: (bloc) async {
        bloc.add(const LoadSyncStatus());
        // Let LoadSyncStatus finish (fetch state, start watching, and its
        // own initial PullRequested/syncOnce) before the burst below, so
        // only the watch-triggered sync is what this test is measuring.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        for (var i = 0; i < 5; i++) {
          watchController.add(FileSystemModifyEvent('/watched/folder/a.txt', false, true));
        }
      },
      wait: const Duration(seconds: 3),
      verify: (_) {
        // One call from LoadSyncStatus's own initial PullRequested, plus
        // exactly one more from the debounced watch burst — not five.
        verify(() => mockSyncCoordinator.syncOnce('/watched/folder')).called(2);
      },
    );

    blocTest<SyncBloc, SyncState>(
      'switching the sync folder cancels the old watch subscription — an '
      'event on the old controller after the switch triggers nothing',
      build: () => buildBloc(
        watch: (path) => path == '/old/folder' ? oldController.stream : watchController.stream,
      ),
      setUp: () {
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
        when(() => mockPreferences.syncFolderPath).thenReturn('/old/folder');
        when(() => mockSyncCoordinator.resetForNewFolder('/new/folder')).thenAnswer((_) async {});
        when(() => mockPreferences.setSyncFolderPath('/new/folder')).thenAnswer((_) async {});
        when(() => mockSyncCoordinator.syncOnce(any()))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
      },
      act: (bloc) async {
        bloc.add(const LoadSyncStatus());
        // Let LoadSyncStatus finish: fetch state, start watching
        // '/old/folder', and run its own initial sync.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const SyncFolderChosen('/new/folder'));
        // Let SyncFolderChosen finish: this is what must cancel the
        // '/old/folder' subscription and start a fresh one on
        // '/new/folder' — see _startWatching's doc comment.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        // No one is listening to this anymore; if the old subscription
        // were still live, this would debounce into a third sync call.
        oldController.add(FileSystemModifyEvent('/old/folder/a.txt', false, true));
        await Future<void>.delayed(const Duration(seconds: 3));
      },
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        // LoadSyncStatus's own initial pull, plus SyncFolderChosen's own
        // pull — exactly 2, not 3.
        verify(() => mockSyncCoordinator.syncOnce(any())).called(2);
      },
    );

    blocTest<SyncBloc, SyncState>(
      'an error on the watch stream does not break the bloc — a later '
      'manual sync (standing in for the periodic poll) still runs',
      build: () => buildBloc(watch: (_) => watchController.stream),
      setUp: () {
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
        when(() => mockPreferences.syncFolderPath).thenReturn('/watched/folder');
        when(() => mockSyncCoordinator.syncOnce('/watched/folder'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
      },
      act: (bloc) async {
        bloc.add(const LoadSyncStatus());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        // Recursive watching is not supported on every platform (e.g.
        // Linux throws asynchronously via the stream rather than on the
        // listen call itself) — must not crash or unsubscribe the bloc.
        watchController.addError(Exception('recursive watch not supported'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const PullRequested());
      },
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        // LoadSyncStatus's own initial pull, plus the manual PullRequested
        // dispatched after the watch error — the bloc is still alive.
        verify(() => mockSyncCoordinator.syncOnce('/watched/folder')).called(2);
      },
    );
  });
}

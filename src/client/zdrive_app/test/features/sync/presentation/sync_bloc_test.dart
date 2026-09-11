import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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

void main() {
  late MockSyncRemoteDataSource mockDataSource;
  late MockSyncCoordinator mockSyncCoordinator;
  late MockPullSyncService mockPullService;
  late MockAppPreferences mockPreferences;

  setUp(() {
    mockDataSource = MockSyncRemoteDataSource();
    mockSyncCoordinator = MockSyncCoordinator();
    mockPullService = MockPullSyncService();
    mockPreferences = MockAppPreferences();
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
        userId: userId,
        watch: watch,
      );

  group('LoadSyncStatus', () {
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
  });

  group('PullRequested', () {
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
      'does not run a second sync while one is already in flight (F4)',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/local/sync'),
      setUp: () {
        final completer = Completer<SyncRunResult>();
        when(() => mockSyncCoordinator.syncOnce('/local/sync'))
            .thenAnswer((_) => completer.future);
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
        // Resolves after both PullRequested events below have already been
        // dispatched — simulating the periodic timer firing again while a
        // slow sync (a whole-file transfer) is still in flight.
        Future.delayed(
          const Duration(milliseconds: 20),
          () => completer.complete(const SyncRunResult(pulled: 0, pushed: 0)),
        );
      },
      act: (bloc) {
        bloc.add(const PullRequested());
        bloc.add(const PullRequested());
      },
      wait: const Duration(milliseconds: 50),
      verify: (_) => verify(() => mockSyncCoordinator.syncOnce('/local/sync')).called(1),
    );
  });

  group('SyncFolderChosen', () {
    // Shared by the F2/finding-4/finding-1 race tests below only —
    // reassigned fresh in each test's own setUp, like watchController in the
    // 'folder watch' group.
    late Completer<SyncRunResult> pullGate;
    late Completer<List<Map<String, dynamic>>> oldDevicesGate;
    // Gates syncOnce('/new') for the round-3 finding-1 generation tests
    // below, so the new folder's own run can be held open independently of
    // the stale old run's pullGate.
    late Completer<SyncRunResult> newSyncGate;

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
      'syncs the new folder, even when the old pull\'s own finishing '
      'sequence (getDevices/getFailedEvents/its own emit) never completes '
      'at all during this test (PR #16 review round 2, finding 4) — the '
      'round-1 fix (F2) re-dispatched PullRequested, whose isPulling guard '
      'ran concurrently with the old pull\'s handler and could still see it '
      'as in flight, silently dropping the new folder\'s first sync '
      'entirely; calling the shared pull routine directly, with isPulling '
      'forced to false in the same synchronous step as the folder-path '
      'emit, removes that race regardless of how far the old pull has '
      'gotten',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/old'),
      setUp: () {
        pullGate = Completer<SyncRunResult>();
        oldDevicesGate = Completer<List<Map<String, dynamic>>>();
        when(() => mockSyncCoordinator.syncOnce('/old')).thenAnswer((_) => pullGate.future);
        // Shares the mutex with syncOnce, same as the real SyncCoordinator —
        // cannot resolve until the old pull's own lock section is done.
        when(() => mockSyncCoordinator.resetForNewFolder('/new')).thenAnswer((_) async {
          await pullGate.future;
        });
        when(() => mockSyncCoordinator.syncOnce('/new'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
        // The FIRST call is the old pull's own tail — left to hang for the
        // rest of this test, so its "finished" emit never lands at all,
        // proving the new folder's sync does not depend on it ever doing
        // so. The SECOND call is the new folder's own pull, which must
        // still resolve normally.
        var getDevicesCalls = 0;
        when(() => mockDataSource.getDevices()).thenAnswer((_) {
          getDevicesCalls++;
          return getDevicesCalls == 1 ? oldDevicesGate.future : Future.value(<Map<String, dynamic>>[]);
        });
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

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
    // Shared by the F2 race test below only — reassigned fresh in that
    // test's own setUp, like watchController in the 'folder watch' group.
    late Completer<SyncRunResult> pullGate;

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
        verifyNever(() => mockSyncCoordinator.resetForNewFolder());
      },
    );

    blocTest<SyncBloc, SyncState>(
      'resets the mirror before persisting a different folder than the '
      'one already configured',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], syncFolderPath: '/old/folder'),
      setUp: () {
        when(() => mockSyncCoordinator.resetForNewFolder()).thenAnswer((_) async {});
        when(() => mockPreferences.setSyncFolderPath('/new/folder'))
            .thenAnswer((_) async {});
        when(() => mockSyncCoordinator.syncOnce('/new/folder'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
      },
      act: (bloc) => bloc.add(const SyncFolderChosen('/new/folder')),
      verify: (_) {
        verifyInOrder([
          () => mockSyncCoordinator.resetForNewFolder(),
          () => mockPreferences.setSyncFolderPath('/new/folder'),
        ]);
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
      verify: (_) => verifyNever(() => mockSyncCoordinator.resetForNewFolder()),
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
        when(() => mockSyncCoordinator.resetForNewFolder()).thenAnswer((_) async {
          await pullGate.future;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });
        when(() => mockSyncCoordinator.syncOnce('/new'))
            .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
        when(() => mockPreferences.setSyncFolderPath('/new')).thenAnswer((_) async {});
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
        when(() => mockSyncCoordinator.resetForNewFolder()).thenAnswer((_) async {});
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

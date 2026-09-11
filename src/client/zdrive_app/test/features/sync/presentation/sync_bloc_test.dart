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
  });

  SyncBloc buildBloc({Stream<FileSystemEvent> Function(String path)? watch}) => SyncBloc(
        dataSource: mockDataSource,
        syncCoordinator: mockSyncCoordinator,
        pullService: mockPullService,
        preferences: mockPreferences,
        watch: watch,
      );

  group('LoadSyncStatus', () {
    blocTest<SyncBloc, SyncState>(
      'emits [SyncLoading, SyncLoaded] with mapped devices and conflicts',
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
        when(() => mockDataSource.getConflicts()).thenAnswer((_) async => [
              {
                'id': 'c-1',
                'fileId': 'file-1',
                'status': 'Pending',
                'createdAt': '2024-06-02T08:00:00Z',
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
          conflicts: [
            SyncConflict(
              id: 'c-1',
              fileId: 'file-1',
              status: 'Pending',
              createdAt: DateTime.parse('2024-06-02T08:00:00Z'),
            ),
          ],
        ),
      ],
    );

    blocTest<SyncBloc, SyncState>(
      'filters out resolved conflicts, keeping only pending ones',
      build: buildBloc,
      setUp: () {
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
        when(() => mockDataSource.getConflicts()).thenAnswer((_) async => [
              {
                'id': 'c-1',
                'fileId': 'file-1',
                'status': 'Pending',
                'createdAt': '2024-06-02T08:00:00Z',
              },
              {
                'id': 'c-2',
                'fileId': 'file-2',
                'status': 'ResolvedLocal',
                'createdAt': '2024-06-02T09:00:00Z',
              },
            ]);
      },
      act: (bloc) => bloc.add(const LoadSyncStatus()),
      expect: () => [
        const SyncLoading(),
        SyncLoaded(
          devices: const [],
          conflicts: [
            SyncConflict(
              id: 'c-1',
              fileId: 'file-1',
              status: 'Pending',
              createdAt: DateTime.parse('2024-06-02T08:00:00Z'),
            ),
          ],
        ),
      ],
    );

    blocTest<SyncBloc, SyncState>(
      'maps a device with no lastSyncAt to null',
      build: buildBloc,
      setUp: () {
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => [
              {'id': 'dev-1', 'name': 'Phone', 'platform': 'android'},
            ]);
        when(() => mockDataSource.getConflicts()).thenAnswer((_) async => []);
      },
      act: (bloc) => bloc.add(const LoadSyncStatus()),
      expect: () => [
        const SyncLoading(),
        const SyncLoaded(
          devices: [
            SyncDevice(id: 'dev-1', name: 'Phone', platform: 'android'),
          ],
          conflicts: [],
        ),
      ],
    );

    blocTest<SyncBloc, SyncState>(
      'emits [SyncLoading, SyncError] when the data source throws',
      build: buildBloc,
      setUp: () {
        when(() => mockDataSource.getDevices()).thenThrow(Exception('network down'));
        when(() => mockDataSource.getConflicts()).thenAnswer((_) async => []);
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
        when(() => mockDataSource.getConflicts()).thenAnswer((_) async => []);
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
      seed: () => const SyncLoaded(devices: [], conflicts: []),
      act: (bloc) => bloc.add(const PullRequested()),
      expect: () => <SyncState>[],
      verify: (_) => verifyNever(() => mockSyncCoordinator.syncOnce(any())),
    );

    blocTest<SyncBloc, SyncState>(
      'syncs once (pull, then push), then refreshes the device list on success',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], conflicts: [], syncFolderPath: '/local/sync'),
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
          conflicts: [],
          syncFolderPath: '/local/sync',
          isPulling: true,
        ),
        const SyncLoaded(
          devices: [SyncDevice(id: 'dev-1', name: 'This PC', platform: 'windows')],
          conflicts: [],
          syncFolderPath: '/local/sync',
        ),
      ],
    );

    blocTest<SyncBloc, SyncState>(
      'surfaces the error and clears isPulling when the sync fails',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], conflicts: [], syncFolderPath: '/local/sync'),
      setUp: () {
        when(() => mockSyncCoordinator.syncOnce('/local/sync'))
            .thenThrow(Exception('disk full'));
      },
      act: (bloc) => bloc.add(const PullRequested()),
      expect: () => [
        const SyncLoaded(
          devices: [],
          conflicts: [],
          syncFolderPath: '/local/sync',
          isPulling: true,
        ),
        const SyncLoaded(
          devices: [],
          conflicts: [],
          syncFolderPath: '/local/sync',
          pullError: 'Exception: disk full',
        ),
      ],
    );

    blocTest<SyncBloc, SyncState>(
      'does not run a second sync while one is already in flight (F4)',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], conflicts: [], syncFolderPath: '/local/sync'),
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
    blocTest<SyncBloc, SyncState>(
      'persists the chosen folder and triggers a sync',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], conflicts: []),
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
        const SyncLoaded(devices: [], conflicts: [], syncFolderPath: '/new/folder'),
        const SyncLoaded(
          devices: [],
          conflicts: [],
          syncFolderPath: '/new/folder',
          isPulling: true,
        ),
        const SyncLoaded(
          devices: [],
          conflicts: [],
          syncFolderPath: '/new/folder',
        ),
      ],
      verify: (_) =>
          verify(() => mockPreferences.setSyncFolderPath('/new/folder')).called(1),
    );
  });

  group('folder watch', () {
    // Drives the injected watch stream directly instead of touching a real
    // filesystem — the bloc only needs *a* Stream<FileSystemEvent> for the
    // folder path, not a real OS watcher, to prove out its own debounce
    // logic. A plain (non-broadcast) controller is enough: the bloc
    // subscribes to it exactly once, from LoadSyncStatus below.
    late StreamController<FileSystemEvent> watchController;

    setUp(() {
      watchController = StreamController<FileSystemEvent>();
    });

    tearDown(() => watchController.close());

    blocTest<SyncBloc, SyncState>(
      'a burst of watch events triggers exactly one extra sync, 2s after '
      'the last one',
      build: () => buildBloc(watch: (_) => watchController.stream),
      setUp: () {
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
        when(() => mockDataSource.getConflicts()).thenAnswer((_) async => []);
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
  });
}

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/storage/app_preferences.dart';
import 'package:zdrive_app/features/sync/data/pull_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';
import 'package:zdrive_app/features/sync/domain/sync_models.dart';
import 'package:zdrive_app/features/sync/presentation/sync_bloc.dart';

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

class MockPullSyncService extends Mock implements PullSyncService {}

class MockAppPreferences extends Mock implements AppPreferences {}

void main() {
  late MockSyncRemoteDataSource mockDataSource;
  late MockPullSyncService mockPullService;
  late MockAppPreferences mockPreferences;

  setUp(() {
    mockDataSource = MockSyncRemoteDataSource();
    mockPullService = MockPullSyncService();
    mockPreferences = MockAppPreferences();
    // Unstubbed: syncFolderPath returns null (mocktail's default for a
    // nullable getter), matching "no folder chosen yet" — the baseline every
    // existing test below assumes, since none of them are about pulling.
  });

  SyncBloc buildBloc() => SyncBloc(
        dataSource: mockDataSource,
        pullService: mockPullService,
        preferences: mockPreferences,
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
      verify: (_) => verifyNever(() => mockPullService.pullOnce(any())),
    );

    blocTest<SyncBloc, SyncState>(
      'pulls once, then refreshes the device list on success',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], conflicts: [], syncFolderPath: '/local/sync'),
      setUp: () {
        when(() => mockPullService.pullOnce('/local/sync')).thenAnswer((_) async => 2);
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
      'surfaces the error and clears isPulling when the pull fails',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], conflicts: [], syncFolderPath: '/local/sync'),
      setUp: () {
        when(() => mockPullService.pullOnce('/local/sync'))
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
      'does not run a second pull while one is already in flight (F4)',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], conflicts: [], syncFolderPath: '/local/sync'),
      setUp: () {
        final completer = Completer<int>();
        when(() => mockPullService.pullOnce('/local/sync'))
            .thenAnswer((_) => completer.future);
        when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => []);
        when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
        // Resolves after both PullRequested events below have already been
        // dispatched — simulating the periodic timer firing again while a
        // slow pull (a whole-file transfer) is still in flight.
        Future.delayed(const Duration(milliseconds: 20), () => completer.complete(0));
      },
      act: (bloc) {
        bloc.add(const PullRequested());
        bloc.add(const PullRequested());
      },
      wait: const Duration(milliseconds: 50),
      verify: (_) => verify(() => mockPullService.pullOnce('/local/sync')).called(1),
    );
  });

  group('SyncFolderChosen', () {
    blocTest<SyncBloc, SyncState>(
      'persists the chosen folder and triggers a pull',
      build: buildBloc,
      seed: () => const SyncLoaded(devices: [], conflicts: []),
      setUp: () {
        when(() => mockPreferences.setSyncFolderPath('/new/folder'))
            .thenAnswer((_) async {});
        when(() => mockPullService.pullOnce('/new/folder')).thenAnswer((_) async => 0);
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
}

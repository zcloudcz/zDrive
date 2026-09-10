import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';
import 'package:zdrive_app/features/sync/domain/sync_models.dart';
import 'package:zdrive_app/features/sync/presentation/sync_bloc.dart';

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

void main() {
  late MockSyncRemoteDataSource mockDataSource;

  setUp(() {
    mockDataSource = MockSyncRemoteDataSource();
  });

  SyncBloc buildBloc() => SyncBloc(dataSource: mockDataSource);

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
}

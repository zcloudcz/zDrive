import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/storage/app_preferences.dart';
import 'package:zdrive_app/features/sync/data/pull_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sync_coordinator.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';
import 'package:zdrive_app/features/sync/presentation/sync_bloc.dart';
import 'package:zdrive_app/shared/router/app_router.dart';

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

class MockSyncCoordinator extends Mock implements SyncCoordinator {}

class MockPullSyncService extends Mock implements PullSyncService {}

class MockAppPreferences extends Mock implements AppPreferences {}

void main() {
  // Router-level regression test for PR #16 review round 1, F1: the shell's
  // BlocProvider<SyncBloc> used the default `lazy: true`, so nothing created
  // the bloc — and nothing ran LoadSyncStatus — until the Sync page happened
  // to be visited. Building the real GoRouter here would need a full
  // authenticated AuthBloc/GoRouter setup just to reach the shell; instead
  // this drives [buildSyncShellProvider] directly, the function the router
  // itself calls to build that provider (app_router.dart), with mocked
  // SyncBloc dependencies standing in for getIt.
  late MockSyncRemoteDataSource mockDataSource;
  late MockSyncCoordinator mockSyncCoordinator;
  late MockPullSyncService mockPullService;
  late MockAppPreferences mockPreferences;

  setUp(() {
    mockDataSource = MockSyncRemoteDataSource();
    mockSyncCoordinator = MockSyncCoordinator();
    mockPullService = MockPullSyncService();
    mockPreferences = MockAppPreferences();
    when(() => mockSyncCoordinator.startSession(any())).thenAnswer((_) async {});
    when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
  });

  testWidgets(
      'the sync provider is eager: LoadSyncStatus is handled without any '
      'descendant ever reading the bloc (F1) — proves lazy: false, not the '
      'default lazy: true a widget-triggered read would also satisfy',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: buildSyncShellProvider(
        createBloc: () => SyncBloc(
          dataSource: mockDataSource,
          syncCoordinator: mockSyncCoordinator,
          pullService: mockPullService,
          preferences: mockPreferences,
          userId: 'user-1',
        ),
        // Deliberately a plain widget that never reads SyncBloc from
        // context — if create() only ran because something asked for the
        // bloc (the old lazy: true default), this test would see neither
        // call below.
        child: const SizedBox(),
      ),
    ));
    await tester.pump();

    verify(() => mockSyncCoordinator.startSession('user-1')).called(1);
    verify(() => mockDataSource.getDevices()).called(1);
  });
}

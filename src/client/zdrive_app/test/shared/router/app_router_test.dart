import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/events/remote_file_change_notifier.dart';
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

class MockRemoteFileChangeNotifier extends Mock implements RemoteFileChangeNotifier {}

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
  late MockRemoteFileChangeNotifier mockRemoteChangeNotifier;

  setUp(() {
    mockDataSource = MockSyncRemoteDataSource();
    mockSyncCoordinator = MockSyncCoordinator();
    mockPullService = MockPullSyncService();
    mockPreferences = MockAppPreferences();
    mockRemoteChangeNotifier = MockRemoteFileChangeNotifier();
    when(() => mockSyncCoordinator.startSession(any())).thenAnswer((_) async {});
    when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
  });

  testWidgets(
      'syncSupported: true builds the sync provider eagerly: LoadSyncStatus '
      'is handled without any descendant ever reading the bloc (F1) — '
      'proves lazy: false, not the default lazy: true a widget-triggered '
      'read would also satisfy',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: buildSyncShellProvider(
        syncSupported: true,
        createBloc: () => SyncBloc(
          dataSource: mockDataSource,
          syncCoordinator: mockSyncCoordinator,
          pullService: mockPullService,
          preferences: mockPreferences,
          remoteChangeNotifier: mockRemoteChangeNotifier,
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

  testWidgets(
      'syncSupported: false never calls createBloc at all — desktop sync '
      '(and, through it, SyncCoordinator/PullSyncService/'
      'LocalChangeScanner, whose constructors read Platform.isWindows) '
      'must never be built for web or mobile (PR #16 review round 2, '
      'blocking finding 1)',
      (tester) async {
    var createBlocCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: buildSyncShellProvider(
        syncSupported: false,
        createBloc: () {
          createBlocCalled = true;
          return SyncBloc(
            dataSource: mockDataSource,
            syncCoordinator: mockSyncCoordinator,
            pullService: mockPullService,
            preferences: mockPreferences,
            remoteChangeNotifier: mockRemoteChangeNotifier,
            userId: 'user-1',
          );
        },
        child: const SizedBox(),
      ),
    ));
    await tester.pump();

    expect(createBlocCalled, isFalse);
    verifyZeroInteractions(mockSyncCoordinator);
    verifyZeroInteractions(mockDataSource);
  });

  group('buildHomeBranches', () {
    // photosEnabled is threaded in as a parameter (default: kPhotosEnabled,
    // a compile-time bool.fromEnvironment) rather than read directly, so this
    // can drive both branches without a `--dart-define` per test run.
    test('photosEnabled: false omits the Photos branch and its route entirely', () {
      final branches = buildHomeBranches(photosEnabled: false);

      expect(branches, hasLength(2));
      final paths = branches
          .expand((b) => b.routes)
          .whereType<GoRoute>()
          .map((r) => r.path);
      expect(paths, isNot(contains('/home/photos')));
    });

    test('photosEnabled: true includes the Photos branch and its route', () {
      final branches = buildHomeBranches(photosEnabled: true);

      expect(branches, hasLength(3));
      final paths = branches
          .expand((b) => b.routes)
          .whereType<GoRoute>()
          .map((r) => r.path);
      expect(paths, contains('/home/photos'));
    });
  });
}

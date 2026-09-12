import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/storage/app_preferences.dart';
import 'package:zdrive_app/features/sync/data/pull_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sync_coordinator.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_entry.dart';
import 'package:zdrive_app/features/sync/presentation/sync_bloc.dart';
import 'package:zdrive_app/features/sync/presentation/sync_page.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

class MockPullSyncService extends Mock implements PullSyncService {}

class MockSyncCoordinator extends Mock implements SyncCoordinator {}

class MockAppPreferences extends Mock implements AppPreferences {}

void main() {
  late MockSyncRemoteDataSource mockDataSource;
  late MockPullSyncService mockPullService;
  late MockSyncCoordinator mockCoordinator;
  late MockAppPreferences mockPreferences;

  setUp(() {
    mockDataSource = MockSyncRemoteDataSource();
    mockPullService = MockPullSyncService();
    mockCoordinator = MockSyncCoordinator();
    mockPreferences = MockAppPreferences();
    // No stubbing of syncFolderPath: mocktail returns null for an unstubbed
    // nullable getter, matching "no folder chosen yet" — the state every
    // existing scenario below assumes, since none of them are about pulling.
    // startSession must be stubbed (unlike a plain void method, an unstubbed
    // Future-returning one throws instead of resolving to null) — every
    // scenario here dispatches LoadSyncStatus via buildTestWidget.
    when(() => mockCoordinator.startSession(any())).thenAnswer((_) async {});
  });

  // SyncPage now reads the ancestor SyncBloc provided once for the whole
  // authenticated app shell (app_router.dart) instead of creating its own —
  // this test wraps it the same way, with a real SyncBloc over mocks.
  Widget buildTestWidget() {
    return MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider<SyncBloc>(
        create: (_) => SyncBloc(
          dataSource: mockDataSource,
          syncCoordinator: mockCoordinator,
          pullService: mockPullService,
          preferences: mockPreferences,
          userId: 'user-1',
        )..add(const LoadSyncStatus()),
        child: const SyncPage(),
      ),
    );
  }

  group('SyncPage', () {
    testWidgets('shows the registered devices', (tester) async {
      when(() => mockDataSource.getDevices()).thenAnswer((_) async => [
            {'id': 'dev-1', 'name': 'Laptop', 'platform': 'windows'},
          ]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Laptop'), findsOneWidget);
      expect(find.text('Everything is synced'), findsOneWidget);
    });

    testWidgets('shows the no-devices state when nothing has ever synced',
        (tester) async {
      when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // A fresh account with zero devices must not be told it is "up to
      // date" — nothing has happened yet, which is a different state.
      expect(find.text('No devices registered'), findsOneWidget);
      expect(find.text('Everything is synced'), findsNothing);
    });

    testWidgets('shows an error with retry when loading fails', (tester) async {
      when(() => mockDataSource.getDevices()).thenThrow(Exception('network down'));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('network down'), findsOneWidget);

      when(() => mockDataSource.getDevices()).thenAnswer((_) async => [
            {'id': 'dev-1', 'name': 'Laptop', 'platform': 'windows'},
          ]);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Everything is synced'), findsOneWidget);
      expect(find.text('Laptop'), findsOneWidget);
    });

    testWidgets(
        'shows the unsupported-platform message instead of reading the '
        'bloc when no ancestor SyncBloc is provided — the state on web and '
        'mobile, where app_router.dart never provides one (PR #16 review '
        'round 2, blocking finding 1)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        // No BlocProvider<SyncBloc> ancestor at all — deliberately, unlike
        // buildTestWidget() above.
        home: const SyncPage(),
      ));
      await tester.pump();

      expect(find.text('Sync is available in the Windows and macOS app'), findsOneWidget);
    });

    testWidgets('shows skipped items when pull quarantined something',
        (tester) async {
      when(() => mockPreferences.syncFolderPath).thenReturn('/local/sync');
      when(() => mockDataSource.getDevices()).thenAnswer((_) async => [
            {'id': 'dev-1', 'name': 'Laptop', 'platform': 'windows'},
          ]);
      when(() => mockCoordinator.syncOnce('/local/sync'))
          .thenAnswer((_) async => const SyncRunResult(pulled: 1, pushed: 0));
      when(() => mockPullService.getFailedEvents()).thenAnswer((_) async => [
            SyncFailedEvent(
              fileId: 'file-1',
              eventId: 1,
              reason: 'unsafe remote name',
              failedAt: DateTime.utc(2026, 1, 1),
            ),
          ]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Skipped items'), findsOneWidget);
      expect(find.text('file-1'), findsOneWidget);
    });
  });
}

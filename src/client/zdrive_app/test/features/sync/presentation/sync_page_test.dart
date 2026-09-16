import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/events/remote_file_change_notifier.dart';
import 'package:zdrive_app/core/storage/app_preferences.dart';
import 'package:zdrive_app/features/sync/data/pull_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sync_coordinator.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_entry.dart';
import 'package:zdrive_app/features/sync/domain/sync_models.dart';
import 'package:zdrive_app/features/sync/domain/sync_progress.dart';
import 'package:zdrive_app/features/sync/presentation/sync_bloc.dart';
import 'package:zdrive_app/features/sync/presentation/sync_page.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

class MockPullSyncService extends Mock implements PullSyncService {}

class MockSyncCoordinator extends Mock implements SyncCoordinator {}

class MockAppPreferences extends Mock implements AppPreferences {}

class MockRemoteFileChangeNotifier extends Mock implements RemoteFileChangeNotifier {}

class MockSyncBloc extends MockBloc<SyncEvent, SyncState> implements SyncBloc {}

void main() {
  late MockSyncRemoteDataSource mockDataSource;
  late MockPullSyncService mockPullService;
  late MockSyncCoordinator mockCoordinator;
  late MockAppPreferences mockPreferences;
  late MockRemoteFileChangeNotifier mockRemoteChangeNotifier;

  setUp(() {
    mockDataSource = MockSyncRemoteDataSource();
    mockPullService = MockPullSyncService();
    mockCoordinator = MockSyncCoordinator();
    mockPreferences = MockAppPreferences();
    mockRemoteChangeNotifier = MockRemoteFileChangeNotifier();
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
          remoteChangeNotifier: mockRemoteChangeNotifier,
          userId: 'user-1',
        )..add(const LoadSyncStatus()),
        child: const SyncPage(),
      ),
    );
  }

  testWidgets('shows active file and remaining counts before device registration', (tester) async {
    final bloc = MockSyncBloc();
    when(() => bloc.state).thenReturn(SyncLoaded(devices: const [], syncFolderPath: '/sync', isPulling: true,
      progress: SyncProgress(phase: SyncPhase.uploading, totalFiles: 4, completedFiles: 1,
        activeFiles: const [SyncFileProgress(key: 'a', path: 'photos/cat.jpg', transferredBytes: 1024, totalBytes: 4096)])));
    await tester.pumpWidget(MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales, locale: const Locale('en'),
      home: BlocProvider<SyncBloc>.value(value: bloc, child: const SyncPage())));
    expect(find.text('Uploading'), findsOneWidget);
    expect(find.text('photos/cat.jpg'), findsOneWidget);
    expect(find.text('1 / 4 items completed · 3 remaining'), findsOneWidget);
    expect(find.text('1.0 KiB / 4.0 KiB · 3.0 KiB remaining'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown discovery total stays indeterminate', (tester) async {
    final bloc = MockSyncBloc();
    when(() => bloc.state).thenReturn(SyncLoaded(devices: const [], syncFolderPath: '/sync', isPulling: true,
      progress: SyncProgress(phase: SyncPhase.scanning, totalFiles: 4, discovering: true)));
    await tester.pumpWidget(MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales, locale: const Locale('en'),
      home: BlocProvider<SyncBloc>.value(value: bloc, child: const SyncPage())));
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, isNull);
    expect(find.text('Discovering items — total is not known yet'), findsOneWidget);
  });

  group('SyncPage', () {
    testWidgets('shows the registered devices', (tester) async {
      when(() => mockDataSource.getDevices()).thenAnswer((_) async => [
            {'id': 'dev-1', 'name': 'Laptop', 'platform': 'windows'},
          ]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Laptop'), findsOneWidget);
      // No folder is configured in this scenario — the real per-install
      // status tile (not the removed static "Everything is synced" line)
      // shows the "pick a folder" prompt instead.
      expect(find.text('Choose sync folder'), findsOneWidget);
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

      expect(find.text('Choose sync folder'), findsOneWidget);
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
      when(() => mockCoordinator.syncOnce('/local/sync', onProgress: any(named: 'onProgress')))
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

    // The static "Everything is synced" tile used to render unconditionally
    // underneath the live status tile, so a pull in flight showed "Syncing…"
    // and "Everything is synced" at the same time. Driven through a MockBloc
    // (the pattern file_browser_page_test.dart already uses) rather than a
    // real SyncBloc: this is a question about what one state renders, and a
    // real bloc drags in the 30s poll timer, an in-flight syncOnce that
    // close() then waits on, and a device refresh — none of which this
    // assertion is about.
    testWidgets(
        'shows exactly one status line while a pull is in flight, and it is '
        'the pulling one — the removed static "Everything is synced" tile '
        'used to render underneath it unconditionally, contradicting it',
        (tester) async {
      final mockBloc = MockSyncBloc();
      when(() => mockBloc.state).thenReturn(SyncLoaded(
        devices: const [SyncDevice(id: 'dev-1', name: 'Laptop', platform: 'windows')],
        syncFolderPath: '/local/sync',
        isPulling: true,
      ));

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider<SyncBloc>.value(value: mockBloc, child: const SyncPage()),
      ));
      // pump(), not pumpAndSettle(): the pulling state renders a
      // CircularProgressIndicator, whose animation never settles.
      await tester.pump();

      expect(find.text('Syncing…'), findsOneWidget);

      // The load-bearing assertion. Checking that specific strings are absent
      // is nearly free: 'Everything is synced' can no longer be produced by
      // any code path (its ARB key is gone, so re-adding the tile would not
      // compile), and the other _FolderStatusTile branches are unreachable
      // for this state anyway. Counting tiles is what actually fails if
      // somebody reintroduces a second status line — whatever text it uses.
      // Exactly two: the folder status tile, and the one device below it.
      expect(
        find.byType(ListTile),
        findsNWidgets(2),
        reason: 'one status tile + one device; a third means a second status '
            'line is back',
      );
      expect(find.text('This device is up to date.'), findsNothing);
      expect(find.text('Choose sync folder'), findsNothing);
      expect(find.text('Some items could not be synced'), findsNothing);
    });
  });
}

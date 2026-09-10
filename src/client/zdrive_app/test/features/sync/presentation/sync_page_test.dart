import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/di/injection.dart';
import 'package:zdrive_app/core/storage/app_preferences.dart';
import 'package:zdrive_app/features/sync/data/pull_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';
import 'package:zdrive_app/features/sync/presentation/sync_page.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

class MockPullSyncService extends Mock implements PullSyncService {}

class MockAppPreferences extends Mock implements AppPreferences {}

void main() {
  late MockSyncRemoteDataSource mockDataSource;

  setUp(() {
    mockDataSource = MockSyncRemoteDataSource();
    getIt.registerLazySingleton<SyncRemoteDataSource>(() => mockDataSource);
    getIt.registerLazySingleton<PullSyncService>(() => MockPullSyncService());
    // No stubbing of syncFolderPath: mocktail returns null for an unstubbed
    // nullable getter, matching "no folder chosen yet" — the state every
    // existing scenario below assumes, since none of them are about pulling.
    getIt.registerLazySingleton<AppPreferences>(() => MockAppPreferences());
  });

  tearDown(() => getIt.reset());

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
      home: const SyncPage(),
    );
  }

  group('SyncPage', () {
    testWidgets('shows the registered devices and pending conflicts', (tester) async {
      when(() => mockDataSource.getDevices()).thenAnswer((_) async => [
            {'id': 'dev-1', 'name': 'Laptop', 'platform': 'windows'},
          ]);
      when(() => mockDataSource.getConflicts()).thenAnswer((_) async => [
            {
              'id': 'c-1',
              'fileId': 'file-1',
              'status': 'Pending',
              'createdAt': '2024-06-02T08:00:00Z',
            },
          ]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Laptop'), findsOneWidget);
      expect(find.text('file-1'), findsOneWidget);
      expect(find.textContaining('Pending'), findsOneWidget);
    });

    testWidgets(
        'shows the all-synced empty state when devices exist with no conflicts, '
        'and keeps the device list visible', (tester) async {
      when(() => mockDataSource.getDevices()).thenAnswer((_) async => [
            {'id': 'dev-1', 'name': 'Laptop', 'platform': 'windows'},
          ]);
      when(() => mockDataSource.getConflicts()).thenAnswer((_) async => []);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Everything is synced'), findsOneWidget);
      // The commonest state (a registered device, no conflicts) must still
      // list the device — this regressed in round 2 when the empty-state
      // gate was widened to `conflicts.isEmpty` alone.
      expect(find.text('Laptop'), findsOneWidget);
    });

    testWidgets('resolved conflicts do not block the all-synced state',
        (tester) async {
      when(() => mockDataSource.getDevices()).thenAnswer((_) async => [
            {'id': 'dev-1', 'name': 'Laptop', 'platform': 'windows'},
          ]);
      when(() => mockDataSource.getConflicts()).thenAnswer((_) async => [
            {
              'id': 'c-1',
              'fileId': 'file-1',
              'status': 'ResolvedLocal',
              'createdAt': '2024-06-02T08:00:00Z',
            },
          ]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Everything is synced'), findsOneWidget);
      expect(find.text('Laptop'), findsOneWidget);
      expect(find.text('file-1'), findsNothing);
    });

    testWidgets('shows the no-devices state when nothing has ever synced',
        (tester) async {
      when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
      when(() => mockDataSource.getConflicts()).thenAnswer((_) async => []);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // A fresh account with zero devices must not be told it is "up to
      // date" — nothing has happened yet, which is a different state.
      expect(find.text('No devices registered'), findsOneWidget);
      expect(find.text('Everything is synced'), findsNothing);
    });

    testWidgets('shows conflicts alongside the no-devices message when devices are empty',
        (tester) async {
      when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
      when(() => mockDataSource.getConflicts()).thenAnswer((_) async => [
            {
              'id': 'c-1',
              'fileId': 'file-1',
              'status': 'Pending',
              'createdAt': '2024-06-02T08:00:00Z',
            },
          ]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('file-1'), findsOneWidget);
      expect(find.text('No devices registered'), findsOneWidget);
    });

    testWidgets('shows an error with retry when loading fails', (tester) async {
      when(() => mockDataSource.getDevices()).thenThrow(Exception('network down'));
      when(() => mockDataSource.getConflicts()).thenAnswer((_) async => []);

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
  });
}

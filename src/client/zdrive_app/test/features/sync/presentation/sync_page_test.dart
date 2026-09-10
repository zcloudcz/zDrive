import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/di/injection.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';
import 'package:zdrive_app/features/sync/presentation/sync_page.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

void main() {
  late MockSyncRemoteDataSource mockDataSource;

  setUp(() {
    mockDataSource = MockSyncRemoteDataSource();
    getIt.registerLazySingleton<SyncRemoteDataSource>(() => mockDataSource);
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
              'status': 'pending',
              'createdAt': '2024-06-02T08:00:00Z',
            },
          ]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Laptop'), findsOneWidget);
      expect(find.text('file-1'), findsOneWidget);
      expect(find.textContaining('pending'), findsOneWidget);
    });

    testWidgets('shows the all-synced empty state when devices exist with no conflicts',
        (tester) async {
      when(() => mockDataSource.getDevices()).thenAnswer((_) async => [
            {'id': 'dev-1', 'name': 'Laptop', 'platform': 'windows'},
          ]);
      when(() => mockDataSource.getConflicts()).thenAnswer((_) async => []);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Everything is synced'), findsOneWidget);
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
              'status': 'pending',
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
    });
  });
}

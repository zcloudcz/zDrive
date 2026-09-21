import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/events/remote_file_change_notifier.dart';
import 'package:zdrive_app/core/storage/app_preferences.dart';
import 'package:zdrive_app/features/sync/data/pull_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sync_coordinator.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_entry.dart';
import 'package:zdrive_app/features/sync/domain/sync_progress.dart';
import 'package:zdrive_app/features/sync/presentation/sync_bloc.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';
import 'package:zdrive_app/shared/router/app_router.dart';

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

class MockSyncCoordinator extends Mock implements SyncCoordinator {}

class MockPullSyncService extends Mock implements PullSyncService {}

class MockAppPreferences extends Mock implements AppPreferences {}

class MockRemoteFileChangeNotifier extends Mock implements RemoteFileChangeNotifier {}

/// The migration dialog as the desktop shell shows it: a real SyncBloc over
/// mocked services, mounted through buildSyncShellProvider like the router does.
void main() {
  late MockSyncCoordinator coordinator;
  late MockPullSyncService pull;
  late MockAppPreferences prefs;
  late MockSyncRemoteDataSource dataSource;
  var createBlocCalls = 0;

  setUpAll(() {
    registerFallbackValue(SyncProgressTracker((_) {}));
  });

  setUp(() {
    createBlocCalls = 0;
    coordinator = MockSyncCoordinator();
    pull = MockPullSyncService();
    prefs = MockAppPreferences();
    dataSource = MockSyncRemoteDataSource();
    when(() => prefs.syncFolderPath).thenReturn('/sync');
    when(() => coordinator.startSession(any())).thenAnswer((_) async {});
    when(() => coordinator.syncOnce(any(), onProgress: any(named: 'onProgress')))
        .thenAnswer((_) async => const SyncRunResult(pulled: 0, pushed: 0));
    when(() => coordinator.pendingCloudOnlyMigration('/sync'))
        .thenAnswer((_) async => const FreeableEstimate(count: 3, bytes: 3 * 1024 * 1024));
    when(() => dataSource.getDevices()).thenAnswer((_) async => []);
    when(() => pull.getFailedEvents()).thenAnswer((_) async => []);
  });

  Widget shell({required bool desktop}) => MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: buildSyncShellProvider(
          syncSupported: desktop,
          createBloc: () {
            createBlocCalls++;
            return SyncBloc(
              dataSource: dataSource,
              syncCoordinator: coordinator,
              pullService: pull,
              preferences: prefs,
              remoteChangeNotifier: MockRemoteFileChangeNotifier(),
              userId: 'user-1',
              watch: (_) => const Stream.empty(),
            );
          },
          child: const Scaffold(body: Text('shell')),
        ),
      );

  /// Unmounting closes the bloc, which stops its 30s poll timer.
  Future<void> unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  testWidgets('Dialog_Desktop_ShowsEstimateExplanationAndThreeChoices', (tester) async {
    await tester.pumpWidget(shell(desktop: true));
    await tester.pumpAndSettle();

    expect(find.text('Free up space on this device?'), findsOneWidget);
    expect(find.textContaining('3, up to 3.0 MB'), findsOneWidget);
    expect(find.textContaining('available in the cloud and on the web'), findsOneWidget);
    expect(find.textContaining('download them again at any time'), findsOneWidget);
    expect(find.textContaining('not synced yet are always kept'), findsOneWidget);
    expect(find.text('Free up space'), findsOneWidget);
    expect(find.text('Keep everything on this device'), findsOneWidget);
    expect(find.text('Decide later'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Dialog_NarrowWindow_DoesNotOverflow', (tester) async {
    tester.view.physicalSize = const Size(300, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(shell(desktop: true));
    await tester.pumpAndSettle();

    expect(find.text('Free up space on this device?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('Dialog_NonDesktop_NeverBuiltAndNeverAsks', (tester) async {
    await tester.pumpWidget(shell(desktop: false));
    await tester.pumpAndSettle();

    expect(find.text('shell'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(createBlocCalls, 0);
    verifyZeroInteractions(coordinator);
  });

  testWidgets('Dialog_NothingDue_NoDialog', (tester) async {
    when(() => coordinator.pendingCloudOnlyMigration('/sync')).thenAnswer((_) async => null);

    await tester.pumpWidget(shell(desktop: true));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    await unmount(tester);
  });

  testWidgets('Dialog_DecideLater_ClosesWithoutTouchingFiles', (tester) async {
    await tester.pumpWidget(shell(desktop: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Decide later'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    verifyNever(() => coordinator.freeUpEverythingUnpinned(any(), progress: any(named: 'progress')));
    verifyNever(() => coordinator.keepEverythingOnDevice(any()));
    await unmount(tester);
  });

  testWidgets('Dialog_KeepEverything_PinsAndCloses', (tester) async {
    when(() => coordinator.keepEverythingOnDevice('/sync')).thenAnswer((_) async {});
    await tester.pumpWidget(shell(desktop: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keep everything on this device'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    verify(() => coordinator.keepEverythingOnDevice('/sync')).called(1);
    await unmount(tester);
  });

  testWidgets('Dialog_KeepEverythingWaitingOnTheLock_SaysKeepingNotFreeingUp', (tester) async {
    final gate = Completer<void>();
    when(() => coordinator.keepEverythingOnDevice('/sync')).thenAnswer((_) => gate.future);
    await tester.pumpWidget(shell(desktop: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keep everything on this device'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Keeping everything on this device…'), findsOneWidget);
    expect(find.text('Freeing up space…'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await unmount(tester);
  });

  testWidgets('Dialog_FreeUp_ShowsProgressThenResultWithKeptCounts', (tester) async {
    final finish = Completer<FreeUpResult>();
    when(() => coordinator.freeUpEverythingUnpinned('/sync', progress: any(named: 'progress')))
        .thenAnswer((inv) {
      (inv.namedArguments[#progress] as SyncProgressTracker)
          .beginPhase(SyncPhase.deleting, totalFiles: 3);
      return finish.future;
    });
    await tester.pumpWidget(shell(desktop: true));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Free up space'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Freeing up space…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    finish.complete(FreeUpResult()
      ..freed = 1
      ..freedBytes = 2048
      ..keptPinned = 4
      ..skippedUnsynced.addAll(['/sync/a.txt', '/sync/b.txt']));
    await tester.pumpAndSettle();

    expect(find.text('Freed 1 files, 2.0 KB'), findsOneWidget);
    expect(find.text('2 kept on this device: unsynced changes'), findsOneWidget);
    expect(find.text('4 kept on this device: always kept'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await unmount(tester);
  });
}

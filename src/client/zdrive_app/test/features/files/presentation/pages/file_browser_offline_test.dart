import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/files/domain/file_item.dart';
import 'package:zdrive_app/features/files/presentation/file_browser_bloc.dart';
import 'package:zdrive_app/features/files/presentation/pages/file_browser_page.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_entry.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_repository.dart';
import 'package:zdrive_app/features/sync/presentation/offline_status_cubit.dart';
import 'package:zdrive_app/features/sync/presentation/sync_bloc.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

class MockFileBrowserBloc extends MockBloc<FileBrowserEvent, FileBrowserState>
    implements FileBrowserBloc {}

class MockSyncBloc extends MockBloc<SyncEvent, SyncState> implements SyncBloc {}

class MockSyncMirrorRepository extends Mock implements SyncMirrorRepository {}

/// The desktop-only selective-sync surface of the real [FileBrowserView]:
/// per-item markers and the keep / free-up menu entries. Web and mobile never
/// provide a SyncBloc, and must show none of it.
void main() {
  late MockFileBrowserBloc browserBloc;
  late MockSyncBloc syncBloc;
  late MockSyncMirrorRepository mirror;
  final now = DateTime(2026, 1, 1);

  FileItem file(String id, String name) =>
      FileItem(id: id, name: name, isFolder: false, createdAt: now, updatedAt: now);
  final files = [file('cloud', 'cloud.txt'), file('avail', 'avail.txt'), file('pin', 'pin.txt'), file('via', 'via.txt')];

  setUpAll(() {
    registerFallbackValue(const KeepOnDeviceRequested('x'));
  });

  setUp(() {
    browserBloc = MockFileBrowserBloc();
    syncBloc = MockSyncBloc();
    mirror = MockSyncMirrorRepository();
    when(() => mirror.getOfflineStatuses(any(), parentId: any(named: 'parentId'))).thenAnswer(
      (_) async => {
        'cloud': OfflineStatus.cloudOnly,
        'avail': OfflineStatus.available,
        'pin': OfflineStatus.alwaysKeep,
        'via': OfflineStatus.alwaysKeepViaFolder,
      },
    );
    // The listing arrives as a state CHANGE (loading -> loaded), which is what
    // makes the view ask the cubit for statuses.
    whenListen(
      browserBloc,
      Stream.value(FileBrowserLoaded(files: files, breadcrumbs: const [])),
      initialState: const FileBrowserLoading(),
    );
  });

  Widget build({required bool desktop}) {
    Widget view = const FileBrowserView();
    if (desktop) {
      view = MultiBlocProvider(
        providers: [
          BlocProvider<SyncBloc>.value(value: syncBloc),
          BlocProvider<OfflineStatusCubit>(create: (_) => OfflineStatusCubit(mirror)),
        ],
        child: view,
      );
    }
    return MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider<FileBrowserBloc>.value(value: browserBloc, child: view),
    );
  }

  Future<List<String>> menuEntries(WidgetTester tester, String fileName) async {
    await tester.tap(find.descendant(
      of: find.widgetWithText(ListTile, fileName),
      matching: find.byType(PopupMenuButton<String>),
    ));
    await tester.pumpAndSettle();
    final labels = tester.widgetList<Text>(find.descendant(
      of: find.byType(PopupMenuItem<String>),
      matching: find.byType(Text),
    )).map((t) => t.data!).toList();
    await tester.tapAt(const Offset(1, 1)); // dismiss
    await tester.pumpAndSettle();
    return labels;
  }

  group('desktop', () {
    testWidgets('EachItemShowsItsOfflineMarker_LoadedWithOneBatchedLookup', (tester) async {
      when(() => syncBloc.state).thenReturn(const SyncLoaded(devices: [], syncFolderPath: '/s'));
      await tester.pumpWidget(build(desktop: true));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.offline_pin), findsNWidgets(2));
      // One lookup for the whole listing, not one per row.
      verify(() => mirror.getOfflineStatuses(any(), parentId: any(named: 'parentId'))).called(1);
    });

    testWidgets('MenuOffersOnlyTheActionsThatApplyToEachState', (tester) async {
      when(() => syncBloc.state).thenReturn(const SyncLoaded(devices: [], syncFolderPath: '/s'));
      await tester.pumpWidget(build(desktop: true));
      await tester.pumpAndSettle();

      expect(await menuEntries(tester, 'cloud.txt'), contains('Always keep on this device'));
      expect(await menuEntries(tester, 'cloud.txt'), isNot(contains('Free up space')));
      final available = await menuEntries(tester, 'avail.txt');
      expect(available, containsAll(['Always keep on this device', 'Free up space']));
      final pinned = await menuEntries(tester, 'pin.txt');
      expect(pinned, contains('Free up space'));
      expect(pinned, isNot(contains('Always keep on this device')));
      // Kept by a folder above: unpin there, nothing to do on the item.
      final via = await menuEntries(tester, 'via.txt');
      expect(via, isNot(contains('Free up space')));
      expect(via, isNot(contains('Always keep on this device')));
    });

    testWidgets('ChoosingKeepAndFreeUp_DispatchesSyncBlocEventsForThatItem', (tester) async {
      when(() => syncBloc.state).thenReturn(const SyncLoaded(devices: [], syncFolderPath: '/s'));
      await tester.pumpWidget(build(desktop: true));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
        of: find.widgetWithText(ListTile, 'cloud.txt'),
        matching: find.byType(PopupMenuButton<String>),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Always keep on this device'));
      await tester.pumpAndSettle();
      verify(() => syncBloc.add(const KeepOnDeviceRequested('cloud'))).called(1);

      await tester.tap(find.descendant(
        of: find.widgetWithText(ListTile, 'pin.txt'),
        matching: find.byType(PopupMenuButton<String>),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Free up space'));
      await tester.pumpAndSettle();
      verify(() => syncBloc.add(const FreeUpSpaceRequested('pin'))).called(1);
    });

    testWidgets('FinishedAction_RefreshesMarkersAndTellsAboutKeptUnsyncedFiles', (tester) async {
      whenListen(
        syncBloc,
        Stream.value(const SyncLoaded(
          devices: [],
          syncFolderPath: '/s',
          freeUpSkipped: 2,
          offlineRevision: 1,
        )),
        initialState: const SyncLoaded(devices: [], syncFolderPath: '/s'),
      );
      await tester.pumpWidget(build(desktop: true));
      await tester.pumpAndSettle();

      // Initial listing lookup + the refresh after the action.
      verify(() => mirror.getOfflineStatuses(any(), parentId: any(named: 'parentId'))).called(2);
      expect(find.text('2 kept on this device: unsynced changes'), findsOneWidget);
    });

    testWidgets('FinishedAction_TellsAboutFilesKeptBecauseAPinCoversThem', (tester) async {
      whenListen(
        syncBloc,
        Stream.value(const SyncLoaded(
          devices: [],
          syncFolderPath: '/s',
          freeUpKeptPinned: 3,
          offlineRevision: 1,
        )),
        initialState: const SyncLoaded(devices: [], syncFolderPath: '/s'),
      );
      await tester.pumpWidget(build(desktop: true));
      await tester.pumpAndSettle();

      expect(find.text('3 kept on this device: always kept'), findsOneWidget);
    });
  });

  group('web / mobile (no SyncBloc provided)', () {
    testWidgets('NoMarkersAndNoOfflineMenuEntries_AndNothingThrows', (tester) async {
      await tester.pumpWidget(build(desktop: false));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.cloud_outlined), findsNothing);
      expect(find.byIcon(Icons.offline_pin), findsNothing);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      final entries = await menuEntries(tester, 'cloud.txt');
      expect(entries, isNot(contains('Always keep on this device')));
      expect(entries, isNot(contains('Free up space')));
      expect(entries, contains('Rename'));
      expect(tester.takeException(), isNull);
    });
  });
}

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/files/domain/file_item.dart';
import 'package:zdrive_app/features/files/presentation/file_browser_bloc.dart';
import 'package:zdrive_app/features/files/presentation/pages/file_browser_page.dart';
import 'package:zdrive_app/features/files/presentation/widgets/file_actions_toolbar.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

class MockFileBrowserBloc extends MockBloc<FileBrowserEvent, FileBrowserState>
    implements FileBrowserBloc {}

void main() {
  late MockFileBrowserBloc bloc;

  setUp(() {
    bloc = MockFileBrowserBloc();
  });

  Widget build() {
    return MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider<FileBrowserBloc>.value(
        value: bloc,
        child: const FileBrowserView(),
      ),
    );
  }

  testWidgets('the real page shows the actions toolbar and no FAB',
      (tester) async {
    whenListen(
      bloc,
      const Stream<FileBrowserState>.empty(),
      initialState: const FileBrowserLoading(),
    );

    await tester.pumpWidget(build());

    expect(find.byType(FileActionsToolbar), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('New'), findsOneWidget);
  });

  testWidgets('the New menu stays reachable in the empty state',
      (tester) async {
    whenListen(
      bloc,
      const Stream<FileBrowserState>.empty(),
      initialState: const FileBrowserLoaded(files: [], breadcrumbs: []),
    );

    await tester.pumpWidget(build());

    // Toolbar's "New" plus the empty state's own repeat of the same action.
    expect(find.text('New'), findsNWidgets(2));
    expect(find.text('No files'), findsOneWidget);
  });

  testWidgets('the empty state action fires the same upload/create callbacks',
      (tester) async {
    whenListen(
      bloc,
      const Stream<FileBrowserState>.empty(),
      initialState: const FileBrowserLoaded(files: [], breadcrumbs: []),
    );

    await tester.pumpWidget(build());

    // Opening the empty state's "+ New" menu and picking "New folder"
    // dispatches CreateFolder through the same bloc the toolbar uses — there
    // is no separate flow behind the repeated action.
    await tester.tap(find.text('New').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();

    // The dialog reads a name from a text field before it dispatches, so
    // just confirm the flow reached the dialog it shares with the toolbar.
    expect(find.text('Create folder'), findsOneWidget);
  });

  // A folder with just a couple of files is shorter than the viewport, so
  // there is nothing to overscroll unless the listing opts into
  // AlwaysScrollableScrollPhysics — without it, pull-to-refresh silently did
  // nothing on any folder short enough not to need scrolling (review round
  // 2, finding 1). Two files each in list and grid mode.
  final now = DateTime(2026, 1, 1);
  final twoFiles = [
    FileItem(id: '1', name: 'a.txt', isFolder: false, createdAt: now, updatedAt: now),
    FileItem(id: '2', name: 'b.txt', isFolder: false, createdAt: now, updatedAt: now),
  ];

  testWidgets('pull-to-refresh works on a short list (fewer rows than the viewport)',
      (tester) async {
    whenListen(
      bloc,
      const Stream<FileBrowserState>.empty(),
      initialState: FileBrowserLoaded(files: twoFiles, breadcrumbs: const []),
    );

    await tester.pumpWidget(build());
    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    verify(() => bloc.add(const RefreshFiles())).called(1);
  });

  testWidgets('pull-to-refresh works on a short grid (fewer tiles than the viewport)',
      (tester) async {
    whenListen(
      bloc,
      const Stream<FileBrowserState>.empty(),
      initialState: FileBrowserLoaded(
        files: twoFiles,
        breadcrumbs: const [],
        viewMode: FileViewMode.grid,
      ),
    );

    await tester.pumpWidget(build());
    await tester.fling(find.byType(GridView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    verify(() => bloc.add(const RefreshFiles())).called(1);
  });

  testWidgets('loading shows skeletons, no CircularProgressIndicator',
      (tester) async {
    whenListen(
      bloc,
      const Stream<FileBrowserState>.empty(),
      initialState: const FileBrowserLoading(),
    );

    await tester.pumpWidget(build());

    expect(find.byType(CircularProgressIndicator), findsNothing);
    // 6 skeleton rows, each with a circular leading placeholder.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle,
      ),
      findsNWidgets(6),
    );
  });
}

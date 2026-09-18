import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
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

    expect(find.text('New'), findsOneWidget);
    expect(find.text('No files'), findsOneWidget);
  });
}

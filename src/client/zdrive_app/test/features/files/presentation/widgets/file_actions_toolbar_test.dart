import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/files/presentation/file_browser_bloc.dart';
import 'package:zdrive_app/features/files/presentation/widgets/file_actions_toolbar.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

class MockFileBrowserBloc extends MockBloc<FileBrowserEvent, FileBrowserState>
    implements FileBrowserBloc {}

void main() {
  late MockFileBrowserBloc bloc;
  var uploaded = false;
  var folderCreated = false;

  setUp(() {
    bloc = MockFileBrowserBloc();
    when(() => bloc.state).thenReturn(const FileBrowserInitial());
    uploaded = false;
    folderCreated = false;
  });

  Widget build({FileViewMode? viewMode = FileViewMode.list}) {
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
        child: Scaffold(
          body: FileActionsToolbar(
            viewMode: viewMode,
            onUploadFile: () => uploaded = true,
            onCreateFolder: () => folderCreated = true,
          ),
        ),
      ),
    );
  }

  testWidgets('the New menu offers upload and new folder, and fires them',
      (tester) async {
    await tester.pumpWidget(build());

    // Menu items only exist once the anchor is opened.
    expect(find.text('Upload file'), findsNothing);

    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    expect(find.text('Upload file'), findsOneWidget);
    expect(find.text('New folder'), findsOneWidget);

    await tester.tap(find.text('Upload file'));
    await tester.pumpAndSettle();
    expect(uploaded, isTrue);

    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    expect(folderCreated, isTrue);
  });

  testWidgets('refresh and view-mode toggle dispatch their events',
      (tester) async {
    await tester.pumpWidget(build());

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pump();

    verify(() => bloc.add(const RefreshFiles())).called(1);
    verify(() => bloc.add(const ToggleViewMode())).called(1);
    expect(find.byTooltip('Grid view'), findsOneWidget);
  });

  testWidgets('no view-mode toggle before a listing has loaded',
      (tester) async {
    await tester.pumpWidget(build(viewMode: null));

    expect(find.byIcon(Icons.grid_view), findsNothing);
    expect(find.byIcon(Icons.view_list), findsNothing);
  });
}

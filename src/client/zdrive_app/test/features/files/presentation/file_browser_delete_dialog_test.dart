import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/di/injection.dart';
import 'package:zdrive_app/core/events/remote_file_change_notifier.dart';
import 'package:zdrive_app/features/files/domain/file_item.dart';
import 'package:zdrive_app/features/files/domain/file_repository.dart';
import 'package:zdrive_app/features/files/domain/use_cases/create_folder_use_case.dart';
import 'package:zdrive_app/features/files/domain/use_cases/delete_file_use_case.dart';
import 'package:zdrive_app/features/files/domain/use_cases/list_files_use_case.dart';
import 'package:zdrive_app/features/files/domain/use_cases/search_files_use_case.dart';
import 'package:zdrive_app/features/files/presentation/pages/file_browser_page.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

class _Repository extends Mock implements FileRepository {}

void main() {
  late _Repository repository;
  setUp(() {
    repository = _Repository();
    getIt.registerSingleton<FileRepository>(repository);
    getIt.registerSingleton(ListFilesUseCase(repository));
    getIt.registerSingleton(CreateFolderUseCase(repository));
    getIt.registerSingleton(DeleteFileUseCase(repository));
    getIt.registerSingleton(SearchFilesUseCase(repository));
    getIt.registerSingleton(RemoteFileChangeNotifier());
    when(() => repository.listChildren(null, page: 1, pageSize: 50)).thenAnswer(
      (_) async => PagedResult(
        items: [
          FileItem(
            id: 'file-1',
            name: 'sample.txt',
            isFolder: false,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ],
        totalCount: 1,
        page: 1,
        pageSize: 50,
      ),
    );
    when(() => repository.deleteFile('file-1')).thenAnswer((_) async {});
  });
  tearDown(() => getIt.reset());

  for (final confirm in [true, false]) {
    for (final repeat in [false, true]) {
      testWidgets(
        'DeleteDialog_NestedNavigator${repeat ? 'Repeated' : ''}${confirm ? 'Confirm' : 'Cancel'}_ClosesAndKeepsPageResponsive',
        (tester) async {
          final nestedNavigator = GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: Navigator(
                key: nestedNavigator,
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => const FileBrowserPage(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(PopupMenuButton<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          final buttonFinder = find.widgetWithText(
            confirm ? FilledButton : TextButton,
            confirm ? 'Delete' : 'Cancel',
          );
          if (repeat) {
            // Two activations before the dialog's exit animation completes.
            final button = tester.widget<ButtonStyleButton>(buttonFinder);
            button.onPressed!();
            button.onPressed!();
          } else {
            await tester.tap(buttonFinder);
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.byType(FileBrowserPage), findsOneWidget);
          expect(nestedNavigator.currentState!.canPop(), isFalse);
          if (confirm) {
            verify(() => repository.deleteFile('file-1')).called(1);
          } else {
            verifyNever(() => repository.deleteFile(any()));
          }
          await tester.tap(find.byIcon(Icons.grid_view));
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.view_list), findsOneWidget);
        },
      );
    }
  }
}

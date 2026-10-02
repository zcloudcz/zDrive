import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
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

class _Picker extends FilePicker {
  late final result = Completer<String?>();
  int calls = 0;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) {
    calls++;
    return result.future;
  }
}

void main() {
  downloadHelperTests();
  late _Repository repository;
  late _Picker picker;
  late StreamController<Uint8List> content;

  setUp(() {
    repository = _Repository();
    picker = _Picker();
    FilePicker.platform = picker;
    content = StreamController<Uint8List>();
    final file = FileItem(
      id: 'f1',
      name: 'report.pdf',
      isFolder: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    when(() => repository.listChildren(null, page: 1, pageSize: 50)).thenAnswer(
      (_) async =>
          PagedResult(items: [file], totalCount: 1, page: 1, pageSize: 50),
    );
    when(
      () => repository.downloadFileStream('f1'),
    ).thenAnswer((_) => content.stream);
    getIt.registerSingleton<FileRepository>(repository);
    getIt.registerSingleton(ListFilesUseCase(repository));
    getIt.registerSingleton(CreateFolderUseCase(repository));
    getIt.registerSingleton(DeleteFileUseCase(repository));
    getIt.registerSingleton(SearchFilesUseCase(repository));
    getIt.registerSingleton(RemoteFileChangeNotifier());
  });

  tearDown(() async {
    if (!content.isClosed) unawaited(content.close());
    await getIt.reset();
  });

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('cs'),
        home: FileBrowserPage(),
      ),
    );
    await tester.pumpAndSettle();
    // A tap on the row opens the preview; the menu's "Download" entry is the
    // direct download.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stáhnout'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'Download_WaitingAndTransferring_ShowsProgressUntilSaved',
    (tester) async {
      await start(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Stahování...'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('report.pdf'),
        ),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      content.add(Uint8List.fromList([1, 2, 3]));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      unawaited(content.close());
      await tester.pump();
      expect(picker.calls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      picker.result.complete('report.pdf');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      verify(() => repository.downloadFileStream('f1')).called(1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'Download_DesktopSaveCancelled_RemovesProgressWithoutTransfer',
    (tester) async {
      await start(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(picker.calls, 1);
      expect(content.hasListener, isFalse);
      picker.result.complete(null);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(content.hasListener, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'Download_Fails_RemovesProgressAndShowsLocalizedError',
    (tester) async {
      await start(tester);
      content.addError(Exception('internal chunk details'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(FileBrowserPage)),
      )!;
      expect(find.text(l10n.errorRequestFailed), findsOneWidget);
      expect(find.textContaining('internal chunk details'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'Download_AppDisposedDuringWait_CompletesWithoutUiException',
    (tester) async {
      await start(tester);
      await tester.pumpWidget(const SizedBox());
      content.addError(Exception('late failure'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

void downloadHelperTests() {
  test('DownloadFile_LoadedBytesGiven_SavesThemWithoutDownloadingAgain', () async {
    final repository = _Repository();
    final file = FileItem(
      id: 'f1',
      name: 'a.txt',
      isFolder: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final saved = <int>[];
    String? savedName;

    await downloadFile(
      file,
      repository,
      loadedBytes: Uint8List.fromList([1, 2, 3]),
      save: (name, content) async {
        savedName = name;
        await for (final chunk in content) {
          saved.addAll(chunk);
        }
      },
    );

    expect(savedName, 'a.txt');
    expect(saved, [1, 2, 3]);
    verifyNever(() => repository.downloadFileStream(any()));
  });
}


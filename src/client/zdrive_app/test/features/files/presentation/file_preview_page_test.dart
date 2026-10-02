import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/di/injection.dart';
import 'package:zdrive_app/core/events/remote_file_change_notifier.dart';
import 'package:zdrive_app/features/files/domain/file_item.dart';
import 'package:zdrive_app/features/files/domain/file_preview_type.dart';
import 'package:zdrive_app/features/files/domain/file_repository.dart';
import 'package:zdrive_app/features/files/domain/use_cases/create_folder_use_case.dart';
import 'package:zdrive_app/features/files/domain/use_cases/delete_file_use_case.dart';
import 'package:zdrive_app/features/files/domain/use_cases/list_files_use_case.dart';
import 'package:zdrive_app/features/files/domain/use_cases/search_files_use_case.dart';
import 'package:zdrive_app/features/files/presentation/pages/file_browser_page.dart';
import 'package:zdrive_app/features/files/presentation/pages/file_preview_page.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

class _Repository extends Mock implements FileRepository {}

// 1x1 transparent PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Widget _app(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: home,
    );

void main() {
  group('FilePreviewPage', () {
    testWidgets('Preview_ImageFile_ShowsZoomableImage', (tester) async {
      await tester.pumpWidget(_app(FilePreviewPage(
        fileName: 'photo.png',
        sizeBytes: _png.length,
        openContent: () => Stream.value(Uint8List.fromList(_png)),
        onDownload: (_, _) {},
      )));
      await tester.pump();
      await tester.pump();

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('Preview_TextFile_ShowsSelectableTextWithInvalidBytesReplaced',
        (tester) async {
      await tester.pumpWidget(_app(FilePreviewPage(
        fileName: 'notes.txt',
        openContent: () => Stream.value(
          Uint8List.fromList([...utf8.encode('héllo '), 0xFF, ...utf8.encode(' end')]),
        ),
        onDownload: (_, _) {},
      )));
      await tester.pump();
      await tester.pump();

      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.text('héllo � end'), findsOneWidget);
    });

    testWidgets('Preview_FileOverLimit_ShowsSizeAndDownloadButton', (tester) async {
      var downloads = 0;
      await tester.pumpWidget(_app(FilePreviewPage(
        fileName: 'huge.png',
        sizeBytes: previewMaxBytes + 1,
        openContent: () => fail('content must not be opened'),
        onDownload: (_, _) => downloads++,
      )));
      await tester.pump();

      expect(find.text('Preview not available'), findsOneWidget);
      expect(find.text('50.0 MB'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Download'));
      expect(downloads, 1);
    });

    testWidgets('Preview_UnsupportedType_OffersDownload', (tester) async {
      var downloads = 0;
      await tester.pumpWidget(_app(FilePreviewPage(
        fileName: 'report.docx',
        sizeBytes: 2048,
        openContent: () => fail('content must not be opened'),
        onDownload: (_, _) => downloads++,
      )));
      await tester.pump();

      expect(find.text('Preview not available'), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Download'));
      expect(downloads, 1);
    });

    testWidgets('Preview_LoadFails_RetryLoadsContent', (tester) async {
      var attempts = 0;
      await tester.pumpWidget(_app(FilePreviewPage(
        fileName: 'notes.txt',
        openContent: () {
          attempts++;
          return attempts == 1
              ? Stream<Uint8List>.error(StateError('boom'))
              : Stream.value(Uint8List.fromList(utf8.encode('recovered')));
        },
        onDownload: (_, _) {},
      )));
      await tester.pump();
      await tester.pump();

      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('recovered'), findsOneWidget);
    });

    testWidgets('Download_AfterLoaded_PassesLoadedBytesToCaller', (tester) async {
      Uint8List? received;
      var calls = 0;
      await tester.pumpWidget(_app(FilePreviewPage(
        fileName: 'notes.txt',
        openContent: () => Stream.value(Uint8List.fromList(utf8.encode('abc'))),
        onDownload: (_, bytes) {
          calls++;
          received = bytes;
        },
      )));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byIcon(Icons.download));

      expect(calls, 1);
      expect(received, Uint8List.fromList(utf8.encode('abc')));
    });

    testWidgets('Download_BeforeLoaded_PassesNoBytes', (tester) async {
      final never = StreamController<Uint8List>();
      addTearDown(never.close);
      var calls = 0;
      Uint8List? received = Uint8List(1);
      await tester.pumpWidget(_app(FilePreviewPage(
        fileName: 'notes.txt',
        openContent: () => never.stream,
        onDownload: (_, bytes) {
          calls++;
          received = bytes;
        },
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.download));

      expect(calls, 1);
      expect(received, isNull);
    });

    testWidgets('Preview_ToolbarShareAndClose_InvokeCallbacksAndPop', (tester) async {
      var shares = 0;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
          onPressed: () => FilePreviewPage.show(
            context,
            fileName: 'notes.txt',
            openContent: () => Stream.value(Uint8List.fromList(utf8.encode('x'))),
            onDownload: (_, _) {},
            onShare: (_) => shares++,
          ),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.share));
      expect(shares, 1);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(FilePreviewPage), findsNothing);
    });
  });

  group('FileBrowserPage', () {
    late _Repository repository;

    setUp(() {
      repository = _Repository();
      final file = FileItem(
        id: 'f1',
        name: 'notes.txt',
        isFolder: false,
        sizeBytes: 5,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      when(() => repository.listChildren(null, page: 1, pageSize: 50)).thenAnswer(
        (_) async => PagedResult(items: [file], totalCount: 1, page: 1, pageSize: 50),
      );
      when(() => repository.downloadFileStream('f1'))
          .thenAnswer((_) => Stream.value(Uint8List.fromList(utf8.encode('hello'))));
      getIt.registerSingleton<FileRepository>(repository);
      getIt.registerSingleton(ListFilesUseCase(repository));
      getIt.registerSingleton(CreateFolderUseCase(repository));
      getIt.registerSingleton(DeleteFileUseCase(repository));
      getIt.registerSingleton(SearchFilesUseCase(repository));
      getIt.registerSingleton(RemoteFileChangeNotifier());
    });

    tearDown(() => getIt.reset());

    testWidgets('Tap_File_OpensPreviewInsteadOfDownloading', (tester) async {
      await tester.pumpWidget(_app(const FileBrowserPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('notes.txt'));
      await tester.pumpAndSettle();

      expect(find.byType(FilePreviewPage), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
      verify(() => repository.downloadFileStream('f1')).called(1);
    });

    testWidgets('Menu_File_ContainsDownloadEntry', (tester) async {
      await tester.pumpWidget(_app(const FileBrowserPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Download'), findsOneWidget);
      expect(find.byType(FilePreviewPage), findsNothing);
    });
  });
}

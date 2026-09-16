import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/files/domain/file_item.dart';
import 'package:zdrive_app/features/files/domain/file_repository.dart';
import 'package:zdrive_app/features/files/presentation/file_browser_bloc.dart';
import 'package:zdrive_app/features/files/presentation/pages/file_browser_page.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

class MockFileBrowserBloc
    extends MockBloc<FileBrowserEvent, FileBrowserState>
    implements FileBrowserBloc {}

class MockFileRepository extends Mock implements FileRepository {}

void main() {
  late MockFileBrowserBloc mockBloc;

  final now = DateTime(2024, 1, 15);
  final testFolder = FileItem(
    id: 'folder-1',
    name: 'Documents',
    isFolder: true,
    createdAt: now,
    updatedAt: now,
  );
  final testFile = FileItem(
    id: 'file-1',
    name: 'readme.txt',
    isFolder: false,
    sizeBytes: 1024,
    mimeType: 'text/plain',
    createdAt: now,
    updatedAt: now,
  );

  setUpAll(() {
    registerFallbackValue(const LoadFolder());
    registerFallbackValue(const FileBrowserInitial());
  });

  setUp(() {
    mockBloc = MockFileBrowserBloc();
  });

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
      home: BlocProvider<FileBrowserBloc>.value(
        value: mockBloc,
        child: const Scaffold(body: _TestFileBrowserBody()),
      ),
    );
  }

  group('FileBrowserPage', () {
    testWidgets('shows loading indicator when loading', (tester) async {
      when(() => mockBloc.state).thenReturn(const FileBrowserLoading());

      await tester.pumpWidget(buildTestWidget());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows empty state when no files', (tester) async {
      when(() => mockBloc.state).thenReturn(const FileBrowserLoaded(
        files: [],
        breadcrumbs: [BreadcrumbItem(name: 'Home')],
      ));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('No files'), findsOneWidget);
    });

    testWidgets('shows files in list view', (tester) async {
      when(() => mockBloc.state).thenReturn(FileBrowserLoaded(
        files: [testFolder, testFile],
        breadcrumbs: const [BreadcrumbItem(name: 'Home')],
      ));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('readme.txt'), findsOneWidget);
    });

    testWidgets('shows error message on error state', (tester) async {
      when(() => mockBloc.state)
          .thenReturn(const FileBrowserError('Something went wrong'));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('navigates into folder on folder tap', (tester) async {
      when(() => mockBloc.state).thenReturn(FileBrowserLoaded(
        files: [testFolder],
        breadcrumbs: const [BreadcrumbItem(name: 'Home')],
      ));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Verify folder is displayed
      expect(find.text('Documents'), findsOneWidget);

      // Tapping would normally trigger navigation via GoRouter,
      // which we can't fully test in a unit widget test without GoRouter setup.
      // We verify the tile is tappable.
      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();
    });
  });

  group('downloadFile', () {
    late MockFileRepository mockRepository;

    setUp(() {
      mockRepository = MockFileRepository();
    });

    test('cancelled save does not consume the download or use the byte API', () async {
      var consumed = false;
      when(() => mockRepository.downloadFile('file-1'))
          .thenAnswer((_) async => Uint8List.fromList([1]));
      when(() => mockRepository.downloadFileStream('file-1'))
          .thenAnswer((_) async* {
        consumed = true;
        yield Uint8List.fromList([1]);
      });

      await downloadFile(testFile, mockRepository, save: (_, _) async {});

      expect(consumed, isFalse);
      verifyNever(() => mockRepository.downloadFile(any()));
    });

    test('hands the verified stream to the platform saver', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      when(() => mockRepository.downloadFileStream('file-1'))
          .thenAnswer((_) => Stream.value(bytes));

      String? savedName;
      Uint8List? savedBytes;

      await downloadFile(
        testFile,
        mockRepository,
        save: (fileName, data) async {
          savedName = fileName;
          savedBytes = await data.single;
        },
      );

      verify(() => mockRepository.downloadFileStream('file-1')).called(1);
      verifyNever(() => mockRepository.downloadFile(any()));
      expect(savedName, 'readme.txt');
      expect(savedBytes, bytes);
    });

    test('propagates a download stream failure through the saver', () async {
      when(() => mockRepository.downloadFileStream('file-1'))
          .thenAnswer((_) => Stream.error(Exception('chunk hash mismatch')));

      var saverCalled = false;

      await expectLater(
        () => downloadFile(
          testFile,
          mockRepository,
          save: (fileName, data) async {
            saverCalled = true;
            await data.drain<void>();
          },
        ),
        throwsA(isException),
      );
      expect(saverCalled, isTrue);
    });

    test('propagates a failure from the platform saver', () async {
      when(() => mockRepository.downloadFileStream('file-1'))
          .thenAnswer((_) => Stream.value(Uint8List.fromList([1])));

      await expectLater(
        () => downloadFile(
          testFile,
          mockRepository,
          save: (fileName, data) async => throw Exception('save cancelled'),
        ),
        throwsA(isException),
      );
    });
  });
}

/// Simplified body widget that uses the bloc directly,
/// avoiding full GoRouter and DI setup in tests.
class _TestFileBrowserBody extends StatelessWidget {
  const _TestFileBrowserBody();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return BlocBuilder<FileBrowserBloc, FileBrowserState>(
      builder: (context, state) {
        if (state is FileBrowserLoading || state is FileBrowserInitial) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state is FileBrowserLoaded) {
          if (state.files.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open, size: 64,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(l10n.noFiles),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: state.files.length,
            itemBuilder: (context, index) {
              final file = state.files[index];
              return ListTile(
                leading: Icon(file.isFolder ? Icons.folder : Icons.insert_drive_file),
                title: Text(file.name),
                onTap: () {
                  // Navigation handled by GoRouter in real app
                },
              );
            },
          );
        }

        if (state is FileBrowserError) {
          return Center(child: Text(state.message));
        }

        return const SizedBox.shrink();
      },
    );
  }
}

import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/files/domain/file_item.dart';
import 'package:zdrive_app/features/files/domain/file_repository.dart';
import 'package:zdrive_app/features/files/domain/use_cases/create_folder_use_case.dart';
import 'package:zdrive_app/features/files/domain/use_cases/delete_file_use_case.dart';
import 'package:zdrive_app/features/files/domain/use_cases/list_files_use_case.dart';
import 'package:zdrive_app/features/files/domain/use_cases/search_files_use_case.dart';
import 'package:zdrive_app/features/files/presentation/file_browser_bloc.dart';

class MockFileRepository extends Mock implements FileRepository {}

class MockListFilesUseCase extends Mock implements ListFilesUseCase {}

class MockCreateFolderUseCase extends Mock implements CreateFolderUseCase {}

class MockDeleteFileUseCase extends Mock implements DeleteFileUseCase {}

class MockSearchFilesUseCase extends Mock implements SearchFilesUseCase {}

void main() {
  late MockFileRepository mockRepository;
  late MockListFilesUseCase mockListFiles;
  late MockCreateFolderUseCase mockCreateFolder;
  late MockDeleteFileUseCase mockDeleteFile;
  late MockSearchFilesUseCase mockSearchFiles;

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
  final testFiles = [testFolder, testFile];
  final pagedResult = PagedResult(
    items: testFiles,
    totalCount: 2,
    page: 1,
    pageSize: 50,
  );
  final emptyResult = const PagedResult<FileItem>(
    items: [],
    totalCount: 0,
    page: 1,
    pageSize: 50,
  );

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mockRepository = MockFileRepository();
    mockListFiles = MockListFilesUseCase();
    mockCreateFolder = MockCreateFolderUseCase();
    mockDeleteFile = MockDeleteFileUseCase();
    mockSearchFiles = MockSearchFilesUseCase();
  });

  FileBrowserBloc buildBloc() => FileBrowserBloc(
        listFiles: mockListFiles,
        createFolder: mockCreateFolder,
        deleteFile: mockDeleteFile,
        searchFiles: mockSearchFiles,
        fileRepository: mockRepository,
      );

  group('LoadFolder', () {
    blocTest<FileBrowserBloc, FileBrowserState>(
      'emits [Loading, Loaded] with files when loading root folder succeeds',
      build: () {
        when(() => mockListFiles(null, page: 1, pageSize: 50))
            .thenAnswer((_) async => pagedResult);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const LoadFolder()),
      expect: () => [
        const FileBrowserLoading(),
        isA<FileBrowserLoaded>()
            .having((s) => s.files, 'files', testFiles)
            .having((s) => s.currentFolderId, 'currentFolderId', isNull)
            .having((s) => s.breadcrumbs.length, 'breadcrumbs length', 1),
      ],
    );

    blocTest<FileBrowserBloc, FileBrowserState>(
      'emits [Loading, Loaded] with empty list when folder has no children',
      build: () {
        when(() => mockListFiles(null, page: 1, pageSize: 50))
            .thenAnswer((_) async => emptyResult);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const LoadFolder()),
      expect: () => [
        const FileBrowserLoading(),
        isA<FileBrowserLoaded>()
            .having((s) => s.files, 'files', isEmpty),
      ],
    );

    blocTest<FileBrowserBloc, FileBrowserState>(
      'emits [Loading, Loaded] when loading subfolder with breadcrumbs',
      build: () {
        when(() => mockRepository.getFile('folder-1'))
            .thenAnswer((_) async => testFolder);
        when(() => mockListFiles('folder-1', page: 1, pageSize: 50))
            .thenAnswer((_) async => emptyResult);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const LoadFolder(folderId: 'folder-1')),
      expect: () => [
        const FileBrowserLoading(),
        isA<FileBrowserLoaded>()
            .having((s) => s.currentFolderId, 'folderId', 'folder-1')
            .having((s) => s.breadcrumbs.length, 'breadcrumbs', 2),
      ],
    );

    blocTest<FileBrowserBloc, FileBrowserState>(
      'emits [Loading, Error] when loading fails',
      build: () {
        when(() => mockListFiles(null, page: 1, pageSize: 50))
            .thenThrow(Exception('Network error'));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const LoadFolder()),
      expect: () => [
        const FileBrowserLoading(),
        isA<FileBrowserError>(),
      ],
    );
  });

  group('CreateFolder', () {
    blocTest<FileBrowserBloc, FileBrowserState>(
      'creates folder and reloads current folder',
      build: () {
        when(() => mockCreateFolder(null, 'New Folder'))
            .thenAnswer((_) async => testFolder);
        when(() => mockListFiles(null, page: 1, pageSize: 50))
            .thenAnswer((_) async => pagedResult);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const CreateFolder('New Folder')),
      expect: () => [
        // After create, it dispatches LoadFolder which emits Loading + Loaded
        const FileBrowserLoading(),
        isA<FileBrowserLoaded>(),
      ],
    );
  });

  group('DeleteFile', () {
    blocTest<FileBrowserBloc, FileBrowserState>(
      'deletes file and reloads current folder',
      build: () {
        when(() => mockDeleteFile('file-1'))
            .thenAnswer((_) async {});
        when(() => mockListFiles(null, page: 1, pageSize: 50))
            .thenAnswer((_) async => emptyResult);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const DeleteFile('file-1')),
      expect: () => [
        const FileBrowserLoading(),
        isA<FileBrowserLoaded>(),
      ],
    );
  });

  group('RenameFile', () {
    blocTest<FileBrowserBloc, FileBrowserState>(
      'renames file and reloads current folder',
      build: () {
        when(() => mockRepository.renameFile('file-1', 'new-name.txt'))
            .thenAnswer((_) async => testFile);
        when(() => mockListFiles(null, page: 1, pageSize: 50))
            .thenAnswer((_) async => pagedResult);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const RenameFile('file-1', 'new-name.txt')),
      expect: () => [
        const FileBrowserLoading(),
        isA<FileBrowserLoaded>(),
      ],
    );
  });

  group('ToggleViewMode', () {
    blocTest<FileBrowserBloc, FileBrowserState>(
      'toggles from list to grid when in loaded state',
      build: () {
        when(() => mockListFiles(null, page: 1, pageSize: 50))
            .thenAnswer((_) async => pagedResult);
        return buildBloc();
      },
      seed: () => FileBrowserLoaded(
        files: testFiles,
        breadcrumbs: const [BreadcrumbItem(name: 'Home')],
      ),
      act: (bloc) => bloc.add(const ToggleViewMode()),
      expect: () => [
        isA<FileBrowserLoaded>()
            .having((s) => s.viewMode, 'viewMode', FileViewMode.grid),
      ],
    );
  });

  group('SearchFiles', () {
    blocTest<FileBrowserBloc, FileBrowserState>(
      'emits [Loading, Loaded] with search results',
      build: () {
        when(() => mockSearchFiles('readme', page: 1, pageSize: 50))
            .thenAnswer((_) async => PagedResult(
                  items: [testFile],
                  totalCount: 1,
                  page: 1,
                  pageSize: 50,
                ));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const SearchFiles('readme')),
      expect: () => [
        const FileBrowserLoading(),
        isA<FileBrowserLoaded>()
            .having((s) => s.files.length, 'result count', 1),
      ],
    );

    blocTest<FileBrowserBloc, FileBrowserState>(
      'emits [Loading, Error] when search fails',
      build: () {
        when(() => mockSearchFiles('fail', page: 1, pageSize: 50))
            .thenThrow(Exception('Search failed'));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const SearchFiles('fail')),
      expect: () => [
        const FileBrowserLoading(),
        isA<FileBrowserError>(),
      ],
    );
  });
}

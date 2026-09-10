import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/files/data/folder_downloader_io.dart';
import 'package:zdrive_app/features/files/domain/file_item.dart';
import 'package:zdrive_app/features/files/domain/file_repository.dart';

class MockFileRepository extends Mock implements FileRepository {}

void main() {
  late MockFileRepository repository;
  late Directory tempRoot;

  final now = DateTime(2026, 1, 1);

  FileItem fileItem(String id, String name, {bool isFolder = false}) => FileItem(
        id: id,
        name: name,
        isFolder: isFolder,
        createdAt: now,
        updatedAt: now,
      );

  PagedResult<FileItem> paged(List<FileItem> items) => PagedResult(
        items: items,
        totalCount: items.length,
        page: 1,
        pageSize: 200,
      );

  setUp(() async {
    repository = MockFileRepository();
    tempRoot = await Directory.systemTemp.createTemp('folder_downloader_test_');
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('saves a normal tree under the destination directory', () async {
    when(() => repository.listChildren('folder-id', page: 1, pageSize: 200)).thenAnswer(
        (_) async => paged([fileItem('sub-id', 'sub', isFolder: true), fileItem('f-id', 'a.txt')]));
    when(() => repository.listChildren('sub-id', page: 1, pageSize: 200))
        .thenAnswer((_) async => paged([]));
    when(() => repository.downloadFile('f-id'))
        .thenAnswer((_) async => Uint8List.fromList('hello'.codeUnits));

    await mirrorRemoteFolder(repository, 'folder-id', Directory('${tempRoot.path}/dest'));

    expect(await File('${tempRoot.path}/dest/a.txt').readAsString(), 'hello');
    expect(await Directory('${tempRoot.path}/dest/sub').exists(), isTrue);
  });

  test('rejects a file name that would escape the destination directory', () async {
    when(() => repository.listChildren('folder-id', page: 1, pageSize: 200)).thenAnswer(
        (_) async => paged([fileItem('evil-id', '../../evil.txt')]));

    final dest = Directory('${tempRoot.path}/dest');
    await expectLater(
      mirrorRemoteFolder(repository, 'folder-id', dest),
      throwsFormatException,
    );

    // The point of the check: nothing was ever written for the escaping name.
    verifyNever(() => repository.downloadFile('evil-id'));
    expect(await File('${tempRoot.path}/evil.txt').exists(), isFalse);
  });

  test('rejects a folder name that is an absolute path', () async {
    when(() => repository.listChildren('folder-id', page: 1, pageSize: 200)).thenAnswer(
        (_) async => paged([fileItem('evil-id', Platform.isWindows ? r'C:\evil' : '/etc/evil', isFolder: true)]));

    final dest = Directory('${tempRoot.path}/dest');
    await expectLater(
      mirrorRemoteFolder(repository, 'folder-id', dest),
      throwsFormatException,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/files/data/file_dtos.dart';
import 'package:zdrive_app/features/files/data/file_remote_data_source.dart';
import 'package:zdrive_app/features/files/data/file_repository_impl.dart';
import 'package:zdrive_app/features/files/data/file_upload_data_source.dart';

class MockFileRemoteDataSource extends Mock implements FileRemoteDataSource {}

class MockFileUploadDataSource extends Mock implements FileUploadDataSource {}

// F5, PR #16 review round 1: header tests existed only for createFolder and
// deleteFile at this layer, so a regression dropping originDeviceId from
// renameFile or moveFile went uncaught. Every mutating FileRepositoryImpl
// call that carries an origin device id is covered here.
void main() {
  late MockFileRemoteDataSource remote;
  late FileRepositoryImpl repository;

  final now = DateTime.utc(2026, 1, 1);

  FileDto fileDto(String id, {bool isFolder = false}) => FileDto(
        id: id,
        name: 'doc.txt',
        isFolder: isFolder,
        createdAt: now,
        updatedAt: now,
      );

  setUp(() {
    remote = MockFileRemoteDataSource();
    repository = FileRepositoryImpl(remote, MockFileUploadDataSource());
  });

  test('createFolder passes originDeviceId to the remote call', () async {
    when(() => remote.createFolder('parent1', 'New Folder',
            originDeviceId: any(named: 'originDeviceId')))
        .thenAnswer((_) async => fileDto('folder-1', isFolder: true));

    await repository.createFolder('parent1', 'New Folder', originDeviceId: 'dev-1');

    final captured = verify(() => remote.createFolder('parent1', 'New Folder',
            originDeviceId: captureAny(named: 'originDeviceId')))
        .captured;
    expect(captured.single, 'dev-1');
  });

  test('renameFile passes originDeviceId to the remote call', () async {
    when(() => remote.renameFile('f1', 'renamed.txt',
            originDeviceId: any(named: 'originDeviceId')))
        .thenAnswer((_) async => fileDto('f1'));

    await repository.renameFile('f1', 'renamed.txt', originDeviceId: 'dev-2');

    final captured = verify(() => remote.renameFile('f1', 'renamed.txt',
            originDeviceId: captureAny(named: 'originDeviceId')))
        .captured;
    expect(captured.single, 'dev-2');
  });

  test('moveFile passes originDeviceId to the remote call', () async {
    when(() => remote.moveFile('f1', 'parent2',
            originDeviceId: any(named: 'originDeviceId')))
        .thenAnswer((_) async => fileDto('f1'));

    await repository.moveFile('f1', 'parent2', originDeviceId: 'dev-3');

    final captured = verify(() => remote.moveFile('f1', 'parent2',
            originDeviceId: captureAny(named: 'originDeviceId')))
        .captured;
    expect(captured.single, 'dev-3');
  });

  test('deleteFile passes originDeviceId to the remote call', () async {
    when(() => remote.deleteFile('f1', originDeviceId: any(named: 'originDeviceId')))
        .thenAnswer((_) async {});

    await repository.deleteFile('f1', originDeviceId: 'dev-4');

    final captured = verify(() =>
            remote.deleteFile('f1', originDeviceId: captureAny(named: 'originDeviceId')))
        .captured;
    expect(captured.single, 'dev-4');
  });
}

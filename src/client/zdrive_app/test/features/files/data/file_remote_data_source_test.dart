import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/files/data/file_remote_data_source.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late FileRemoteDataSource ds;

  Response<dynamic> ok(dynamic data, String path) => Response<dynamic>(
        data: {'success': true, 'data': data, 'error': null},
        statusCode: 200,
        requestOptions: RequestOptions(path: path),
      );

  final fileJson = {
    'id': 'f1',
    'name': 'doc.txt',
    'isFolder': false,
    'sizeBytes': 10,
    'mimeType': 'text/plain',
    'parentId': null,
    'createdAt': '2026-01-01T00:00:00.000Z',
    'updatedAt': '2026-01-01T00:00:00.000Z',
    'isDeleted': false,
  };

  setUp(() {
    dio = MockDio();
    ds = FileRemoteDataSource(dio);
  });

  test('getFile unwraps envelope into FileDto', () async {
    when(() => dio.get('/files/f1')).thenAnswer((_) async => ok(fileJson, '/files/f1'));
    final dto = await ds.getFile('f1');
    expect(dto.id, 'f1');
    expect(dto.name, 'doc.txt');
  });

  test('listChildren(null) hits the root children route', () async {
    final paged = {'items': <dynamic>[], 'totalCount': 0, 'page': 1, 'pageSize': 50};
    when(() => dio.get('/files/root/children',
            queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => ok(paged, '/files/root/children'));

    await ds.listChildren(null);

    verify(() => dio.get('/files/root/children',
        queryParameters: {'page': 1, 'pageSize': 50})).called(1);
  });

  test('listChildren(id) hits the per-folder children route', () async {
    final paged = {'items': <dynamic>[], 'totalCount': 0, 'page': 1, 'pageSize': 50};
    when(() => dio.get('/files/f1/children',
            queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => ok(paged, '/files/f1/children'));

    await ds.listChildren('f1');

    verify(() => dio.get('/files/f1/children',
        queryParameters: {'page': 1, 'pageSize': 50})).called(1);
  });

  test('createFolder posts to /files with isFolder=true', () async {
    when(() => dio.post('/files', data: any(named: 'data'), options: any(named: 'options')))
        .thenAnswer((_) async => ok(fileJson, '/files'));

    await ds.createFolder('parent1', 'New Folder');

    verify(() => dio.post('/files',
        data: {
          'name': 'New Folder',
          'isFolder': true,
          'parentId': 'parent1',
        },
        options: null)).called(1);
  });

  test('createFolder sends X-Device-Id when originDeviceId is given', () async {
    when(() => dio.post('/files', data: any(named: 'data'), options: any(named: 'options')))
        .thenAnswer((_) async => ok(fileJson, '/files'));

    await ds.createFolder('parent1', 'New Folder', originDeviceId: 'dev-1');

    final captured = verify(() => dio.post('/files',
            data: any(named: 'data'), options: captureAny(named: 'options')))
        .captured
        .single as Options;
    expect(captured.headers, {'X-Device-Id': 'dev-1'});
  });

  test('renameFile uses PUT /files/{id}/rename with newName', () async {
    when(() => dio.put('/files/f1/rename', data: any(named: 'data'), options: any(named: 'options')))
        .thenAnswer((_) async => ok(fileJson, '/files/f1/rename'));

    await ds.renameFile('f1', 'renamed.txt');

    verify(() => dio.put('/files/f1/rename', data: {'newName': 'renamed.txt'}, options: null))
        .called(1);
  });

  test('moveFile uses PUT /files/{id}/move with newParentId', () async {
    when(() => dio.put('/files/f1/move', data: any(named: 'data'), options: any(named: 'options')))
        .thenAnswer((_) async => ok(fileJson, '/files/f1/move'));

    await ds.moveFile('f1', 'p2');

    verify(() => dio.put('/files/f1/move', data: {'newParentId': 'p2'}, options: null)).called(1);
  });

  test('getChanges hits /files/changes with cursor and limit, and sends '
      'X-Device-Id when deviceId is given', () async {
    final feedJson = {
      'changes': [
        {'id': 5, 'fileId': 'f1', 'type': 'Create', 'occurredAt': '2026-01-01T00:00:00.000Z'},
      ],
      'nextCursor': 5,
      'hasMore': false,
    };
    when(() => dio.get('/files/changes',
            queryParameters: any(named: 'queryParameters'), options: any(named: 'options')))
        .thenAnswer((_) async => ok(feedJson, '/files/changes'));

    final page = await ds.getChanges(0, deviceId: 'dev-1');

    expect(page.changes.single.fileId, 'f1');
    expect(page.hasMore, isFalse);
    final captured = verify(() => dio.get('/files/changes',
            queryParameters: {'cursor': 0, 'limit': 500},
            options: captureAny(named: 'options')))
        .captured
        .single as Options;
    expect(captured.headers, {'X-Device-Id': 'dev-1'});
  });

  test('getChanges omits X-Device-Id when no deviceId is given', () async {
    final feedJson = {'changes': <dynamic>[], 'nextCursor': 0, 'hasMore': false};
    when(() => dio.get('/files/changes',
            queryParameters: any(named: 'queryParameters'), options: any(named: 'options')))
        .thenAnswer((_) async => ok(feedJson, '/files/changes'));

    await ds.getChanges(0);

    verify(() => dio.get('/files/changes',
        queryParameters: {'cursor': 0, 'limit': 500}, options: null)).called(1);
  });

  test('searchFiles passes q query parameter', () async {
    final paged = {'items': <dynamic>[], 'totalCount': 0, 'page': 1, 'pageSize': 50};
    when(() => dio.get('/files/search', queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => ok(paged, '/files/search'));

    await ds.searchFiles('report');

    verify(() => dio.get('/files/search',
        queryParameters: {'q': 'report', 'page': 1, 'pageSize': 50})).called(1);
  });

  test('createShare posts to /shares', () async {
    final shareJson = {
      'id': 's1',
      'fileId': 'f1',
      'permission': 'read',
      'linkToken': 'tok',
      'expiresAt': null,
    };
    when(() => dio.post('/shares', data: any(named: 'data')))
        .thenAnswer((_) async => ok(shareJson, '/shares'));

    final dto = await ds.createShare('f1', 'read', null);

    expect(dto.id, 's1');
    verify(() => dio.post('/shares', data: {'fileId': 'f1', 'permission': 'read'}))
        .called(1);
  });

  test('deleteFile succeeds on success envelope', () async {
    when(() => dio.delete('/files/f1', options: any(named: 'options')))
        .thenAnswer((_) async => ok(true, '/files/f1'));
    await ds.deleteFile('f1');
    verify(() => dio.delete('/files/f1', options: null)).called(1);
  });

  test('deleteFile sends X-Device-Id when originDeviceId is given', () async {
    when(() => dio.delete('/files/f1', options: any(named: 'options')))
        .thenAnswer((_) async => ok(true, '/files/f1'));

    await ds.deleteFile('f1', originDeviceId: 'dev-1');

    final captured = verify(() => dio.delete('/files/f1', options: captureAny(named: 'options')))
        .captured
        .single as Options;
    expect(captured.headers, {'X-Device-Id': 'dev-1'});
  });

  test('getFileVersions unwraps the data list', () async {
    final versions = [
      {'id': 'v1', 'versionNumber': 1},
      {'id': 'v2', 'versionNumber': 2},
    ];
    when(() => dio.get('/files/f1/versions'))
        .thenAnswer((_) async => ok(versions, '/files/f1/versions'));

    final list = await ds.getFileVersions('f1');

    expect(list, hasLength(2));
    expect(list.last['versionNumber'], 2);
  });
}

import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/files/data/file_dtos.dart';
import 'package:zdrive_app/features/share_link/data/share_link_data_source.dart';
import 'package:zdrive_app/features/share_link/data/share_link_dtos.dart';
import 'package:zdrive_app/features/share_link/presentation/share_link_cubit.dart';

class MockShareLinkDataSource extends Mock implements ShareLinkDataSource {}

void main() {
  late MockShareLinkDataSource dataSource;
  const token = 'tok123';

  FileDto fileShare({required bool isFolder}) => FileDto(
        id: 'f1',
        name: isFolder ? 'Photos' : 'report.pdf',
        isFolder: isFolder,
        sizeBytes: isFolder ? null : 10,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  final child = FileDto(
    id: 'c1',
    name: 'child.txt',
    isFolder: false,
    sizeBytes: 5,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  final subfolder = FileDto(
    id: 'sf1',
    name: 'Sub',
    isFolder: true,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  final subfolderA = FileDto(
    id: 'sfA',
    name: 'A',
    isFolder: true,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  final subfolderB = FileDto(
    id: 'sfB',
    name: 'B',
    isFolder: true,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  final childOfB = FileDto(
    id: 'cB',
    name: 'b-child.txt',
    isFolder: false,
    sizeBytes: 1,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  DioException notFound() => DioException(
        requestOptions: RequestOptions(path: '/shares/link/$token'),
        response: Response(
          statusCode: 404,
          requestOptions: RequestOptions(path: '/shares/link/$token'),
        ),
      );

  DioException forbidden() => DioException(
        requestOptions: RequestOptions(path: '/shares/link/$token'),
        response: Response(
          statusCode: 403,
          requestOptions: RequestOptions(path: '/shares/link/$token'),
        ),
      );

  DioException withStatus(int status) => DioException(
        requestOptions: RequestOptions(path: '/shares/link/$token'),
        response: Response(
          statusCode: status,
          requestOptions: RequestOptions(path: '/shares/link/$token'),
        ),
      );

  ShareInfoDto info({required String permission, bool allowDelete = false}) => ShareInfoDto(
        permission: permission,
        allowDelete: allowDelete,
        root: fileShare(isFolder: true),
      );

  setUpAll(() => registerFallbackValue(const Stream<List<int>>.empty()));

  setUp(() {
    dataSource = MockShareLinkDataSource();
  });

  blocTest<ShareLinkCubit, ShareLinkState>(
    'a file share loads straight to a single-file ShareLinkLoaded (children: null)',
    setUp: () {
      when(() => dataSource.getShareLink(token)).thenAnswer(
          (_) async => (share: _share, file: fileShare(isFolder: false)));
    },
    build: () => ShareLinkCubit(dataSource, token),
    act: (cubit) => cubit.load(),
    expect: () => [
      isA<ShareLinkLoading>(),
      isA<ShareLinkLoaded>()
          .having((s) => s.current.isFolder, 'isFolder', isFalse)
          .having((s) => s.children, 'children', isNull),
    ],
  );

  blocTest<ShareLinkCubit, ShareLinkState>(
    'a folder share loads its children',
    setUp: () {
      when(() => dataSource.getShareLink(token)).thenAnswer(
          (_) async => (share: _share, file: fileShare(isFolder: true)));
      when(() => dataSource.getChildren(token)).thenAnswer((_) async => [child]);
    },
    build: () => ShareLinkCubit(dataSource, token),
    act: (cubit) => cubit.load(),
    expect: () => [
      isA<ShareLinkLoading>(),
      isA<ShareLinkLoaded>().having((s) => s.children, 'children', [child]),
    ],
  );

  blocTest<ShareLinkCubit, ShareLinkState>(
    'entering a subfolder appends it to path and loads its children; the '
    'breadcrumb then goes back up via goToBreadcrumb',
    setUp: () {
      when(() => dataSource.getShareLink(token)).thenAnswer(
          (_) async => (share: _share, file: fileShare(isFolder: true)));
      when(() => dataSource.getChildren(token)).thenAnswer((_) async => [subfolder]);
      when(() => dataSource.getChildren(token, folderId: subfolder.id))
          .thenAnswer((_) async => [child]);
    },
    build: () => ShareLinkCubit(dataSource, token),
    act: (cubit) async {
      await cubit.load();
      await cubit.openFolder(subfolder);
      await cubit.goToBreadcrumb(-1);
    },
    verify: (cubit) {
      final state = cubit.state as ShareLinkLoaded;
      expect(state.path, isEmpty);
      expect(state.children, [subfolder]);
      verify(() => dataSource.getChildren(token, folderId: subfolder.id)).called(1);
    },
  );

  blocTest<ShareLinkCubit, ShareLinkState>(
    '404 from the backend surfaces as ShareLinkNotFound',
    setUp: () {
      when(() => dataSource.getShareLink(token)).thenThrow(notFound());
    },
    build: () => ShareLinkCubit(dataSource, token),
    act: (cubit) => cubit.load(),
    expect: () => [isA<ShareLinkLoading>(), isA<ShareLinkNotFound>()],
  );

  blocTest<ShareLinkCubit, ShareLinkState>(
    '403 from the backend surfaces as ShareLinkPasswordProtected',
    setUp: () {
      when(() => dataSource.getShareLink(token)).thenThrow(forbidden());
    },
    build: () => ShareLinkCubit(dataSource, token),
    act: (cubit) => cubit.load(),
    expect: () => [isA<ShareLinkLoading>(), isA<ShareLinkPasswordProtected>()],
  );

  blocTest<ShareLinkCubit, ShareLinkState>(
    'a network error surfaces as ShareLinkFailure, and retrying via load() can succeed',
    setUp: () {
      var callCount = 0;
      when(() => dataSource.getShareLink(token)).thenAnswer((_) {
        callCount++;
        if (callCount == 1) {
          throw DioException(
            requestOptions: RequestOptions(path: '/shares/link/$token'),
            type: DioExceptionType.connectionError,
          );
        }
        return Future.value((share: _share, file: fileShare(isFolder: false)));
      });
    },
    build: () => ShareLinkCubit(dataSource, token),
    act: (cubit) async {
      await cubit.load();
      await cubit.load();
    },
    expect: () => [
      isA<ShareLinkLoading>(),
      isA<ShareLinkFailure>(),
      isA<ShareLinkLoading>(),
      isA<ShareLinkLoaded>(),
    ],
  );

  blocTest<ShareLinkCubit, ShareLinkState>(
    'downloading a file emits progress then clears it on success',
    setUp: () {
      when(() => dataSource.getShareLink(token)).thenAnswer(
          (_) async => (share: _share, file: fileShare(isFolder: true)));
      when(() => dataSource.getChildren(token)).thenAnswer((_) async => [child]);
      when(() => dataSource.downloadFile(token, child.id, onProgress: any(named: 'onProgress')))
          .thenAnswer((invocation) async {
        final onProgress =
            invocation.namedArguments[#onProgress] as void Function(double)?;
        onProgress?.call(0.5);
        onProgress?.call(1.0);
      });
    },
    build: () => ShareLinkCubit(dataSource, token),
    act: (cubit) async {
      await cubit.load();
      await cubit.download(child);
    },
    verify: (cubit) {
      final state = cubit.state as ShareLinkLoaded;
      expect(state.downloadProgress.containsKey(child.id), isFalse);
      expect(state.downloadErrors.containsKey(child.id), isFalse);
    },
  );

  blocTest<ShareLinkCubit, ShareLinkState>(
    'a 404 on download leaves the page loaded, with a per-file error instead',
    setUp: () {
      when(() => dataSource.getShareLink(token)).thenAnswer(
          (_) async => (share: _share, file: fileShare(isFolder: true)));
      when(() => dataSource.getChildren(token)).thenAnswer((_) async => [child]);
      when(() => dataSource.downloadFile(token, child.id, onProgress: any(named: 'onProgress')))
          .thenThrow(notFound());
    },
    build: () => ShareLinkCubit(dataSource, token),
    act: (cubit) async {
      await cubit.load();
      await cubit.download(child);
    },
    verify: (cubit) {
      final state = cubit.state as ShareLinkLoaded;
      expect(state.downloadProgress.containsKey(child.id), isFalse);
      expect(state.downloadErrors[child.id], isNotNull);
    },
  );

  test(
      'a stale navigation response (A resolves after a later B already '
      'landed) is dropped — final state is B, and a download progress '
      'emitted while both were in flight survives', () async {
    when(() => dataSource.getShareLink(token)).thenAnswer(
        (_) async => (share: _share, file: fileShare(isFolder: true)));
    when(() => dataSource.getChildren(token)).thenAnswer((_) async => [subfolderA, subfolderB]);
    final completerA = Completer<List<FileDto>>();
    final completerB = Completer<List<FileDto>>();
    when(() => dataSource.getChildren(token, folderId: subfolderA.id))
        .thenAnswer((_) => completerA.future);
    when(() => dataSource.getChildren(token, folderId: subfolderB.id))
        .thenAnswer((_) => completerB.future);
    // Download never resolves — this asserts the progress it set is still
    // there after B lands, not that the download itself finished.
    when(() => dataSource.downloadFile(token, child.id, onProgress: any(named: 'onProgress')))
        .thenAnswer((invocation) {
      final onProgress =
          invocation.namedArguments[#onProgress] as void Function(double)?;
      onProgress?.call(0.5);
      return Completer<void>().future;
    });

    final cubit = ShareLinkCubit(dataSource, token);
    await cubit.load();
    unawaited(cubit.openFolder(subfolderA)); // tap A
    unawaited(cubit.openFolder(subfolderB)); // tap B
    unawaited(cubit.download(child)); // progress while both are pending

    completerB.complete([childOfB]);
    await Future<void>.delayed(Duration.zero);
    completerA.complete([FileDto(
      id: 'cA',
      name: 'a-child.txt',
      isFolder: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    )]);
    await Future<void>.delayed(Duration.zero);

    final state = cubit.state as ShareLinkLoaded;
    expect(state.path, [subfolderB]);
    expect(state.children, [childOfB]);
    expect(state.downloadProgress[child.id], 0.5);
  });

  test(
      'closing the cubit while a download is in flight does not throw when '
      'it later reports progress or fails — the callback and both '
      'completion paths guard on isClosed', () async {
    when(() => dataSource.getShareLink(token)).thenAnswer(
        (_) async => (share: _share, file: fileShare(isFolder: true)));
    when(() => dataSource.getChildren(token)).thenAnswer((_) async => [child]);
    final downloadCompleter = Completer<void>();
    void Function(double)? capturedOnProgress;
    when(() => dataSource.downloadFile(token, child.id, onProgress: any(named: 'onProgress')))
        .thenAnswer((invocation) {
      capturedOnProgress = invocation.namedArguments[#onProgress] as void Function(double)?;
      return downloadCompleter.future;
    });

    final cubit = ShareLinkCubit(dataSource, token);
    await cubit.load();
    final downloadFuture = cubit.download(child);
    await cubit.close();

    capturedOnProgress?.call(0.5);
    downloadCompleter.completeError(Exception('late failure, after close'));

    await expectLater(downloadFuture, completes);
  });

  blocTest<ShareLinkCubit, ShareLinkState>(
    'a failed openFolder keeps the visitor on the current folder and '
    'surfaces a transient navigationError instead of leaving the page',
    setUp: () {
      when(() => dataSource.getShareLink(token)).thenAnswer(
          (_) async => (share: _share, file: fileShare(isFolder: true)));
      when(() => dataSource.getChildren(token)).thenAnswer((_) async => [subfolder]);
      when(() => dataSource.getChildren(token, folderId: subfolder.id)).thenThrow(notFound());
    },
    build: () => ShareLinkCubit(dataSource, token),
    act: (cubit) async {
      await cubit.load();
      await cubit.openFolder(subfolder);
    },
    verify: (cubit) {
      final state = cubit.state as ShareLinkLoaded;
      expect(state.path, isEmpty);
      expect(state.children, [subfolder]);
      expect(state.navigationError, isNotNull);
    },
  );

  blocTest<ShareLinkCubit, ShareLinkState>(
    'navigationError is cleared by the next successful navigation',
    setUp: () {
      when(() => dataSource.getShareLink(token)).thenAnswer(
          (_) async => (share: _share, file: fileShare(isFolder: true)));
      when(() => dataSource.getChildren(token)).thenAnswer((_) async => [subfolder]);
      var callCount = 0;
      when(() => dataSource.getChildren(token, folderId: subfolder.id)).thenAnswer((_) {
        callCount++;
        if (callCount == 1) throw notFound();
        return Future.value([child]);
      });
    },
    build: () => ShareLinkCubit(dataSource, token),
    act: (cubit) async {
      await cubit.load();
      await cubit.openFolder(subfolder);
      await cubit.openFolder(subfolder);
    },
    verify: (cubit) {
      final state = cubit.state as ShareLinkLoaded;
      expect(state.children, [child]);
      expect(state.navigationError, isNull);
    },
  );

  blocTest<ShareLinkCubit, ShareLinkState>(
    'canWrite/canDelete come from GET .../info',
    setUp: () {
      when(() => dataSource.getShareLink(token)).thenAnswer(
          (_) async => (share: _share, file: fileShare(isFolder: true)));
      when(() => dataSource.getChildren(token)).thenAnswer((_) async => [child]);
      when(() => dataSource.getInfo(token))
          .thenAnswer((_) async => info(permission: 'Write', allowDelete: true));
    },
    build: () => ShareLinkCubit(dataSource, token),
    act: (cubit) => cubit.load(),
    verify: (cubit) {
      final state = cubit.state as ShareLinkLoaded;
      expect(state.canWrite, isTrue);
      expect(state.canDelete, isTrue);
    },
  );

  blocTest<ShareLinkCubit, ShareLinkState>(
    'a 404 from GET .../info (older backend) falls back to read-only instead of breaking the page',
    setUp: () {
      when(() => dataSource.getShareLink(token)).thenAnswer(
          (_) async => (share: _share, file: fileShare(isFolder: true)));
      when(() => dataSource.getChildren(token)).thenAnswer((_) async => [child]);
      when(() => dataSource.getInfo(token)).thenThrow(notFound());
    },
    build: () => ShareLinkCubit(dataSource, token),
    act: (cubit) => cubit.load(),
    verify: (cubit) {
      final state = cubit.state as ShareLinkLoaded;
      expect(state.canWrite, isFalse);
      expect(state.canDelete, isFalse);
    },
  );

  blocTest<ShareLinkCubit, ShareLinkState>(
    'a successful upload into a folder refreshes the listing and keeps the current path',
    setUp: () {
      when(() => dataSource.getShareLink(token)).thenAnswer(
          (_) async => (share: _share, file: fileShare(isFolder: true)));
      when(() => dataSource.getChildren(token)).thenAnswer((_) async => [child]);
      when(() => dataSource.getInfo(token))
          .thenAnswer((_) async => info(permission: 'Write'));
      when(() => dataSource.uploadFile(
            token,
            parentId: null,
            fileName: 'new.txt',
            content: any(named: 'content'),
            sizeBytes: 3,
            overwrite: false,
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => child);
      when(() => dataSource.getChildren(token, folderId: null))
          .thenAnswer((_) async => [child, child]);
    },
    build: () => ShareLinkCubit(dataSource, token),
    act: (cubit) async {
      await cubit.load();
      await cubit.uploadFile('new.txt', Stream.value([1, 2, 3]), 3);
    },
    verify: (cubit) {
      final state = cubit.state as ShareLinkLoaded;
      expect(state.path, isEmpty);
      expect(state.children, [child, child]);
      expect(state.uploadProgress, isEmpty);
      expect(state.uploadErrors, isEmpty);
    },
  );

  blocTest<ShareLinkCubit, ShareLinkState>(
    'a 409 (name exists) surfaces as an upload error and does NOT auto-retry with overwrite',
    setUp: () {
      when(() => dataSource.getShareLink(token)).thenAnswer(
          (_) async => (share: _share, file: fileShare(isFolder: true)));
      when(() => dataSource.getChildren(token)).thenAnswer((_) async => [child]);
      when(() => dataSource.getInfo(token))
          .thenAnswer((_) async => info(permission: 'Write'));
      when(() => dataSource.uploadFile(
            token,
            parentId: null,
            fileName: 'new.txt',
            content: any(named: 'content'),
            sizeBytes: 3,
            overwrite: false,
            onProgress: any(named: 'onProgress'),
          )).thenThrow(withStatus(409));
    },
    build: () => ShareLinkCubit(dataSource, token),
    act: (cubit) async {
      await cubit.load();
      await cubit.uploadFile('new.txt', Stream.value([1, 2, 3]), 3);
    },
    verify: (cubit) {
      final state = cubit.state as ShareLinkLoaded;
      expect((state.uploadErrors['new.txt'] as DioException).response?.statusCode, 409);
      verifyNever(() => dataSource.uploadFile(
            token,
            parentId: null,
            fileName: 'new.txt',
            content: any(named: 'content'),
            sizeBytes: 3,
            overwrite: true,
            onProgress: any(named: 'onProgress'),
          ));
    },
  );

  blocTest<ShareLinkCubit, ShareLinkState>(
    'retrying with overwrite: true sends it through to the data source',
    setUp: () {
      when(() => dataSource.getShareLink(token)).thenAnswer(
          (_) async => (share: _share, file: fileShare(isFolder: true)));
      when(() => dataSource.getChildren(token)).thenAnswer((_) async => [child]);
      when(() => dataSource.getInfo(token))
          .thenAnswer((_) async => info(permission: 'Write'));
      when(() => dataSource.uploadFile(
            token,
            parentId: null,
            fileName: 'new.txt',
            content: any(named: 'content'),
            sizeBytes: 3,
            overwrite: true,
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => child);
      when(() => dataSource.getChildren(token, folderId: null)).thenAnswer((_) async => [child]);
    },
    build: () => ShareLinkCubit(dataSource, token),
    act: (cubit) async {
      await cubit.load();
      await cubit.uploadFile('new.txt', Stream.value([1, 2, 3]), 3, overwrite: true);
    },
    verify: (cubit) {
      verify(() => dataSource.uploadFile(
            token,
            parentId: null,
            fileName: 'new.txt',
            content: any(named: 'content'),
            sizeBytes: 3,
            overwrite: true,
            onProgress: any(named: 'onProgress'),
          )).called(1);
      final state = cubit.state as ShareLinkLoaded;
      expect(state.uploadErrors, isEmpty);
    },
  );

  for (final status in [403, 413, 429]) {
    blocTest<ShareLinkCubit, ShareLinkState>(
      'a $status upload failure is captured as the raw error for the page to describe',
      setUp: () {
        when(() => dataSource.getShareLink(token)).thenAnswer(
            (_) async => (share: _share, file: fileShare(isFolder: true)));
        when(() => dataSource.getChildren(token)).thenAnswer((_) async => [child]);
        when(() => dataSource.getInfo(token))
            .thenAnswer((_) async => info(permission: 'Write'));
        when(() => dataSource.uploadFile(
              token,
              parentId: null,
              fileName: 'new.txt',
              content: any(named: 'content'),
              sizeBytes: 3,
              overwrite: false,
              onProgress: any(named: 'onProgress'),
            )).thenThrow(withStatus(status));
      },
      build: () => ShareLinkCubit(dataSource, token),
      act: (cubit) async {
        await cubit.load();
        await cubit.uploadFile('new.txt', Stream.value([1, 2, 3]), 3);
      },
      verify: (cubit) {
        final state = cubit.state as ShareLinkLoaded;
        expect((state.uploadErrors['new.txt'] as DioException).response?.statusCode, status);
      },
    );
  }

  blocTest<ShareLinkCubit, ShareLinkState>(
    'deleting an item refreshes the listing',
    setUp: () {
      when(() => dataSource.getShareLink(token)).thenAnswer(
          (_) async => (share: _share, file: fileShare(isFolder: true)));
      when(() => dataSource.getChildren(token)).thenAnswer((_) async => [child]);
      when(() => dataSource.getInfo(token))
          .thenAnswer((_) async => info(permission: 'Write', allowDelete: true));
      when(() => dataSource.deleteItem(token, child.id)).thenAnswer((_) async {});
      when(() => dataSource.getChildren(token, folderId: null)).thenAnswer((_) async => []);
    },
    build: () => ShareLinkCubit(dataSource, token),
    act: (cubit) async {
      await cubit.load();
      await cubit.deleteItem(child.id);
    },
    verify: (cubit) {
      final state = cubit.state as ShareLinkLoaded;
      expect(state.children, isEmpty);
    },
  );

  test(
      'a navigation during an in-flight upload makes its listing refresh '
      'stale — the folder the visitor navigated to is not clobbered', () async {
    when(() => dataSource.getShareLink(token)).thenAnswer(
        (_) async => (share: _share, file: fileShare(isFolder: true)));
    when(() => dataSource.getChildren(token)).thenAnswer((_) async => [subfolder]);
    when(() => dataSource.getInfo(token)).thenAnswer((_) async => info(permission: 'Write'));
    final uploadCompleter = Completer<FileDto>();
    when(() => dataSource.uploadFile(
          token,
          parentId: null,
          fileName: 'new.txt',
          content: any(named: 'content'),
          sizeBytes: 3,
          overwrite: false,
          onProgress: any(named: 'onProgress'),
        )).thenAnswer((_) => uploadCompleter.future);
    when(() => dataSource.getChildren(token, folderId: subfolder.id))
        .thenAnswer((_) async => [child]);

    final cubit = ShareLinkCubit(dataSource, token);
    await cubit.load();
    final uploadFuture = cubit.uploadFile('new.txt', Stream.value([1, 2, 3]), 3);
    await cubit.openFolder(subfolder); // visitor navigates away while the upload is in flight
    uploadCompleter.complete(child);
    await uploadFuture;

    // getChildren(folderId: null) happens exactly once — the initial load.
    // The upload's own stale refresh (for the root, which the visitor has
    // since left) must not fire a second one that would clobber the
    // navigation's listing below.
    verify(() => dataSource.getChildren(token, folderId: null)).called(1);
    final state = cubit.state as ShareLinkLoaded;
    expect(state.path, [subfolder]);
    expect(state.children, [child]);
    // The upload is over: its progress row must not stay frozen in every
    // folder just because the visitor navigated while it ran.
    expect(state.uploadProgress, isEmpty);
  });

  test(
      'a failing listing refresh after a SUCCESSFUL upload is not reported '
      'as a failed upload', () async {
    when(() => dataSource.getShareLink(token)).thenAnswer(
        (_) async => (share: _share, file: fileShare(isFolder: true)));
    var listings = 0;
    when(() => dataSource.getChildren(token)).thenAnswer((_) async {
      // First call = initial load; second = the refresh after the upload.
      if (++listings == 1) return [subfolder];
      throw Exception('listing timed out');
    });
    when(() => dataSource.getInfo(token)).thenAnswer((_) async => info(permission: 'Write'));
    when(() => dataSource.uploadFile(
          token,
          parentId: null,
          fileName: 'new.txt',
          content: any(named: 'content'),
          sizeBytes: 3,
          overwrite: false,
          onProgress: any(named: 'onProgress'),
        )).thenAnswer((_) async => child);

    final cubit = ShareLinkCubit(dataSource, token);
    await cubit.load();
    await cubit.uploadFile('new.txt', Stream.value([1, 2, 3]), 3);

    final state = cubit.state as ShareLinkLoaded;
    expect(listings, 2);
    expect(state.uploadErrors, isEmpty);
    expect(state.uploadProgress, isEmpty);
  });

  test('Download_LoadedBytesGiven_SavesThemWithoutRequestingAGrant', () async {
    when(() => dataSource.getShareLink(token)).thenAnswer(
        (_) async => (share: _share, file: fileShare(isFolder: true)));
    when(() => dataSource.getChildren(token)).thenAnswer((_) async => [child]);
    String? savedName;
    final savedBytes = <int>[];
    final cubit = ShareLinkCubit(dataSource, token, save: (name, content) async {
      savedName = name;
      await for (final chunk in content) {
        savedBytes.addAll(chunk);
      }
    });
    await cubit.load();

    await cubit.download(child, loadedBytes: Uint8List.fromList([1, 2, 3]));

    expect(savedName, child.name);
    expect(savedBytes, [1, 2, 3]);
    verifyNever(() => dataSource.downloadFile(any(), any(),
        onProgress: any(named: 'onProgress')));
    expect((cubit.state as ShareLinkLoaded).downloadProgress, isEmpty);
    await cubit.close();
  });

  test('Download_SameFileAlreadyRunning_DoesNotStartASecondDownload', () async {
    when(() => dataSource.getShareLink(token)).thenAnswer(
        (_) async => (share: _share, file: fileShare(isFolder: true)));
    when(() => dataSource.getChildren(token)).thenAnswer((_) async => [child]);
    final running = Completer<void>();
    when(() => dataSource.downloadFile(token, child.id, onProgress: any(named: 'onProgress')))
        .thenAnswer((_) => running.future);
    final cubit = ShareLinkCubit(dataSource, token);
    await cubit.load();

    final first = cubit.download(child);
    await cubit.download(child);
    running.complete();
    await first;

    verify(() => dataSource.downloadFile(token, child.id, onProgress: any(named: 'onProgress')))
        .called(1);
    await cubit.close();
  });
}

final _share = ShareDto(
  id: 's1',
  fileId: 'f1',
  permission: 'read',
  linkToken: 'tok123',
);

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/files/data/file_dtos.dart';
import 'package:zdrive_app/features/share_link/data/share_link_data_source.dart';
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
}

final _share = ShareDto(
  id: 's1',
  fileId: 'f1',
  permission: 'read',
  linkToken: 'tok123',
);

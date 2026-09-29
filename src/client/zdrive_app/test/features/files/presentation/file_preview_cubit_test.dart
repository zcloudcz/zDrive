import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/features/files/domain/file_preview_type.dart';
import 'package:zdrive_app/features/files/presentation/file_preview_cubit.dart';

Uint8List _bytes(int n) => Uint8List.fromList(List.filled(n, 65));

void main() {
  blocTest<FilePreviewCubit, FilePreviewState>(
    'Load_TextFile_EmitsLoadingProgressThenLoaded',
    build: () => FilePreviewCubit(
      fileName: 'a.txt',
      sizeBytes: 4,
      openContent: () => Stream.fromIterable([_bytes(2), _bytes(2)]),
    ),
    act: (cubit) => cubit.load(),
    expect: () => [
      const FilePreviewLoading(progress: 0),
      const FilePreviewLoading(progress: 0.5),
      const FilePreviewLoading(progress: 1),
      FilePreviewLoaded(kind: PreviewKind.text, bytes: _bytes(4)),
    ],
  );

  blocTest<FilePreviewCubit, FilePreviewState>(
    'Load_UnknownSize_LoadsWithoutProgress',
    build: () => FilePreviewCubit(
      fileName: 'a.png',
      openContent: () => Stream.value(_bytes(3)),
    ),
    act: (cubit) => cubit.load(),
    expect: () => [
      const FilePreviewLoading(progress: 0),
      FilePreviewLoaded(kind: PreviewKind.image, bytes: _bytes(3)),
    ],
  );

  blocTest<FilePreviewCubit, FilePreviewState>(
    'Load_StreamThrows_EmitsError',
    build: () => FilePreviewCubit(
      fileName: 'a.png',
      openContent: () => Stream<Uint8List>.error(StateError('boom')),
    ),
    act: (cubit) => cubit.load(),
    expect: () => [
      const FilePreviewLoading(progress: 0),
      isA<FilePreviewError>(),
    ],
  );

  test('Retry_AfterError_LoadsContent', () async {
    var attempts = 0;
    final cubit = FilePreviewCubit(
      fileName: 'a.png',
      openContent: () {
        attempts++;
        return attempts == 1
            ? Stream<Uint8List>.error(StateError('boom'))
            : Stream.value(_bytes(3));
      },
    );
    await cubit.load();
    expect(cubit.state, isA<FilePreviewError>());
    await cubit.retry();
    expect(cubit.state, isA<FilePreviewLoaded>());
    await cubit.close();
  });

  blocTest<FilePreviewCubit, FilePreviewState>(
    'Load_DeclaredSizeOverLimit_EmitsTooLargeWithoutOpeningContent',
    build: () => FilePreviewCubit(
      fileName: 'a.png',
      sizeBytes: previewMaxBytes + 1,
      openContent: () => fail('content must not be opened'),
    ),
    act: (cubit) => cubit.load(),
    expect: () => [const FilePreviewTooLarge()],
  );

  blocTest<FilePreviewCubit, FilePreviewState>(
    'Load_TextOverTextLimit_EmitsTooLarge',
    build: () => FilePreviewCubit(
      fileName: 'a.txt',
      sizeBytes: previewTextMaxBytes + 1,
      openContent: () => fail('content must not be opened'),
    ),
    act: (cubit) => cubit.load(),
    expect: () => [const FilePreviewTooLarge()],
  );

  blocTest<FilePreviewCubit, FilePreviewState>(
    'Load_StreamExceedsLimitDespiteSmallDeclaredSize_EmitsTooLarge',
    build: () => FilePreviewCubit(
      fileName: 'a.txt',
      sizeBytes: 10,
      openContent: () => Stream.value(_bytes(previewTextMaxBytes + 1)),
    ),
    act: (cubit) => cubit.load(),
    expect: () => [
      const FilePreviewLoading(progress: 0),
      const FilePreviewTooLarge(),
    ],
  );

  blocTest<FilePreviewCubit, FilePreviewState>(
    'Load_UnsupportedType_EmitsUnsupportedWithoutOpeningContent',
    build: () => FilePreviewCubit(
      fileName: 'a.docx',
      sizeBytes: 10,
      openContent: () => fail('content must not be opened'),
    ),
    act: (cubit) => cubit.load(),
    expect: () => [const FilePreviewUnsupported()],
  );
}

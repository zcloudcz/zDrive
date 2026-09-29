import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/files/data/file_dtos.dart';
import 'package:zdrive_app/features/files/presentation/pages/file_preview_page.dart';
import 'package:zdrive_app/features/share_link/presentation/pages/share_link_page.dart';
import 'package:zdrive_app/features/share_link/presentation/share_link_cubit.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';
import 'package:zdrive_app/shared/theme/app_theme.dart';
import 'package:zdrive_app/shared/widgets/brand_lockup.dart';

import '../../../shared/theme/app_theme_test.dart' show contrastRatio;

class MockShareLinkCubit extends MockCubit<ShareLinkState> implements ShareLinkCubit {}

void main() {
  group('describeShareError', () {
    DioException dio(int status, [Object? data]) => DioException(
          requestOptions: RequestOptions(path: '/x'),
          response: Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: status,
            data: data,
          ),
          type: DioExceptionType.badResponse,
        );
    final l10n = lookupAppLocalizations(const Locale('en'));

    test('share-specific texts come from the envelope error code', () {
      expect(
        describeShareError(dio(429, {'error': {'code': 'TOO_MANY_PENDING_UPLOADS'}}), l10n),
        l10n.shareErrorTooManyUploads,
      );
      expect(
        describeShareError(dio(413, {'error': {'code': 'QUOTA_EXCEEDED'}}), l10n),
        l10n.shareErrorQuotaExceeded,
      );
    });

    test('a bare gateway 429 / 413 without an envelope gets the generic text', () {
      expect(describeShareError(dio(429), l10n), isNot(l10n.shareErrorTooManyUploads));
      expect(describeShareError(dio(413, 'Payload Too Large'), l10n),
          isNot(l10n.shareErrorQuotaExceeded));
    });

    test('403 and 409 map by status', () {
      expect(describeShareError(dio(403), l10n), l10n.shareErrorNotAllowed);
      expect(describeShareError(dio(409), l10n), l10n.shareErrorNameExists);
    });
  });

  late MockShareLinkCubit cubit;

  setUp(() {
    cubit = MockShareLinkCubit();
  });

  // themeMode/theme default to dark so the "forced light" test below proves
  // ShareLinkView overrides the ambient theme rather than merely matching it
  // by coincidence.
  Widget build({ThemeMode themeMode = ThemeMode.dark}) {
    return MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider<ShareLinkCubit>.value(
        value: cubit,
        child: const ShareLinkView(),
      ),
    );
  }

  final file = FileDto(
    id: 'f1',
    name: 'report.pdf',
    isFolder: false,
    sizeBytes: 2048,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final folder = FileDto(
    id: 'fo1',
    name: 'Photos',
    isFolder: true,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final child = FileDto(
    id: 'c1',
    name: 'child.txt',
    isFolder: false,
    sizeBytes: 5,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  testWidgets('a single-file share shows its name, size, and a Download button',
      (tester) async {
    whenListen(
      cubit,
      const Stream<ShareLinkState>.empty(),
      initialState: ShareLinkLoaded(root: file, path: const [], children: null),
    );

    await tester.pumpWidget(build());

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.textContaining('2.0 KB'), findsOneWidget);
    final l10n = AppLocalizations.of(tester.element(find.byType(ShareLinkView)))!;
    expect(find.widgetWithText(FilledButton, l10n.download), findsOneWidget);
  });

  testWidgets('a folder share lists its children', (tester) async {
    whenListen(
      cubit,
      const Stream<ShareLinkState>.empty(),
      initialState: ShareLinkLoaded(root: folder, path: const [], children: [child]),
    );

    await tester.pumpWidget(build());

    expect(find.text('child.txt'), findsOneWidget);
  });

  testWidgets('ShareLinkNotFound shows the not-found text', (tester) async {
    whenListen(cubit, const Stream<ShareLinkState>.empty(),
        initialState: const ShareLinkNotFound());

    await tester.pumpWidget(build());

    final l10n = AppLocalizations.of(tester.element(find.byType(ShareLinkView)))!;
    expect(find.text(l10n.shareNotFoundTitle), findsOneWidget);
  });

  testWidgets('ShareLinkPasswordProtected shows the password-protected text',
      (tester) async {
    whenListen(cubit, const Stream<ShareLinkState>.empty(),
        initialState: const ShareLinkPasswordProtected());

    await tester.pumpWidget(build());

    final l10n = AppLocalizations.of(tester.element(find.byType(ShareLinkView)))!;
    expect(find.text(l10n.sharePasswordProtectedTitle), findsOneWidget);
  });

  testWidgets('tapping Download on a single-file share calls the cubit',
      (tester) async {
    whenListen(
      cubit,
      const Stream<ShareLinkState>.empty(),
      initialState: ShareLinkLoaded(root: file, path: const [], children: null),
    );
    when(() => cubit.download(file)).thenAnswer((_) async {});

    await tester.pumpWidget(build());
    final l10n = AppLocalizations.of(tester.element(find.byType(ShareLinkView)))!;
    await tester.tap(find.widgetWithText(FilledButton, l10n.download));
    await tester.pump();

    verify(() => cubit.download(file)).called(1);
  });

  testWidgets('a navigationError appearing on the loaded state pops a SnackBar '
      'and the page stays on the same folder listing', (tester) async {
    final loaded = ShareLinkLoaded(root: folder, path: const [], children: [child]);
    final controller = StreamController<ShareLinkState>();
    addTearDown(controller.close);
    whenListen(cubit, controller.stream, initialState: loaded);

    await tester.pumpWidget(build());
    expect(find.byType(SnackBar), findsNothing);

    controller.add(loaded.copyWith(navigationError: () => Exception('boom')));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    // The listing itself is untouched — a failed navigation must not blank
    // the page the visitor was already looking at.
    expect(find.text('child.txt'), findsOneWidget);
  });

  testWidgets('the header carries the brand lockup', (tester) async {
    whenListen(
      cubit,
      const Stream<ShareLinkState>.empty(),
      initialState: ShareLinkLoaded(root: file, path: const [], children: null),
    );

    await tester.pumpWidget(build());

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.byType(BrandLockup)),
      findsOneWidget,
    );
  });

  testWidgets(
    'the header wordmark is white on the petrol band, not the black84 '
    'BrandLockup would otherwise inherit from titleLarge (PR review BLOCKER)',
    (tester) async {
      whenListen(
        cubit,
        const Stream<ShareLinkState>.empty(),
        initialState: ShareLinkLoaded(root: file, path: const [], children: null),
      );

      await tester.pumpWidget(build());

      final wordmark = tester.widget<Text>(
        find.descendant(of: find.byType(AppBar), matching: find.text('zDrive')),
      );
      expect(wordmark.style!.color, Colors.white);
      expect(
        contrastRatio(wordmark.style!.color!, AppTheme.brandPetrol),
        greaterThanOrEqualTo(4.5),
      );
    },
  );

  testWidgets(
    'the page forces light theme even when the surrounding app is in dark mode',
    (tester) async {
      whenListen(
        cubit,
        const Stream<ShareLinkState>.empty(),
        initialState: ShareLinkLoaded(root: file, path: const [], children: null),
      );

      await tester.pumpWidget(build(themeMode: ThemeMode.dark));

      // Theme.of(context) on ShareLinkView's own element would read the
      // ambient (dark) theme — the forced-light Theme wraps its build
      // output, so assert from a descendant instead, same as the app does.
      final brightness = Theme.of(tester.element(find.byType(Scaffold))).brightness;
      expect(brightness, Brightness.light);
    },
  );

  testWidgets('an expiry date shows "Available until", absent when there is none',
      (tester) async {
    whenListen(
      cubit,
      const Stream<ShareLinkState>.empty(),
      initialState: ShareLinkLoaded(
        root: file,
        path: const [],
        children: null,
        expiresAt: DateTime(2026, 9, 30),
      ),
    );
    await tester.pumpWidget(build());
    expect(find.textContaining('Available until'), findsOneWidget);
  });

  testWidgets('no expiry date on the share means no "Available until" line',
      (tester) async {
    whenListen(
      cubit,
      const Stream<ShareLinkState>.empty(),
      initialState: ShareLinkLoaded(root: file, path: const [], children: null),
    );
    await tester.pumpWidget(build());
    expect(find.textContaining('Available until'), findsNothing);
  });

  test(
    'formatShareExpiryDate converts to local time before formatting — a '
    'UTC instant printed as UTC calendar fields is the wrong day for '
    'visitors east/west of Greenwich (PR review fix #2). Timezone-'
    'independent: compares the function against the same formatter applied '
    'to .toLocal() by hand, which holds in any timezone CI or a dev '
    'machine runs in.',
    () {
      final utcInstant = DateTime.utc(2026, 9, 30, 23, 30);
      final expected = DateFormat.yMMMd('en').format(utcInstant.toLocal());
      expect(formatShareExpiryDate(utcInstant, 'en'), expected);
    },
  );

  testWidgets('loading shows skeleton placeholders, never a bare spinner',
      (tester) async {
    whenListen(cubit, const Stream<ShareLinkState>.empty(),
        initialState: const ShareLinkLoading());

    await tester.pumpWidget(build());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    // The skeleton is a Card standing in for the eventual file card.
    expect(find.byType(Card), findsOneWidget);
  });

  testWidgets(
    'downloading (progress != null) shows a determinate indicator, never '
    'CircularProgressIndicator (PR review fix #4)',
    (tester) async {
      whenListen(
        cubit,
        const Stream<ShareLinkState>.empty(),
        initialState: ShareLinkLoaded(
          root: file,
          path: const [],
          children: null,
          downloadProgress: const {'f1': 0.5},
        ),
      );

      await tester.pumpWidget(build());

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    },
  );

  testWidgets(
    'the loading skeleton settles when animations are disabled — a '
    'perpetually repeating AnimationController would otherwise hang '
    'pumpAndSettle forever (PR review fix #3, teeth check)',
    (tester) async {
      whenListen(cubit, const Stream<ShareLinkState>.empty(),
          initialState: const ShareLinkLoading());

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: build(),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('not-found and password-protected states render as a card, '
      'not a SnackBar', (tester) async {
    for (final state in [const ShareLinkNotFound(), const ShareLinkPasswordProtected()]) {
      cubit = MockShareLinkCubit();
      whenListen(cubit, const Stream<ShareLinkState>.empty(), initialState: state);

      await tester.pumpWidget(build());

      expect(find.byType(Card), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    }
  });

  testWidgets('no overflow at a narrow width with text scaled to 200%',
      (tester) async {
    whenListen(
      cubit,
      const Stream<ShareLinkState>.empty(),
      initialState: ShareLinkLoaded(
        root: file,
        path: const [],
        children: null,
        expiresAt: DateTime(2026, 9, 30),
      ),
    );
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(build());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'no overflow at a narrow width with text scaled to 200% — folder state '
    '(PR review fix #5)',
    (tester) async {
      whenListen(
        cubit,
        const Stream<ShareLinkState>.empty(),
        initialState: ShareLinkLoaded(root: folder, path: const [], children: [child]),
      );
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(build());
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'no overflow at a narrow width with text scaled to 200% — a 120-'
    'character file name (PR review fix #5)',
    (tester) async {
      final longName = FileDto(
        id: 'f2',
        name: 'a' * 120,
        isFolder: false,
        sizeBytes: 2048,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      whenListen(
        cubit,
        const Stream<ShareLinkState>.empty(),
        initialState: ShareLinkLoaded(
          root: longName,
          path: const [],
          children: null,
          expiresAt: DateTime(2026, 9, 30),
        ),
      );
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(build());
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a Read link (canWrite/canDelete both false) shows no upload/new-folder/delete controls',
      (tester) async {
    whenListen(
      cubit,
      const Stream<ShareLinkState>.empty(),
      initialState: ShareLinkLoaded(root: folder, path: const [], children: [child]),
    );

    await tester.pumpWidget(build());
    final l10n = AppLocalizations.of(tester.element(find.byType(ShareLinkView)))!;

    // Teeth check 1: if the page ignored canWrite/canDelete and always
    // showed the controls, this assertion is what fails.
    expect(find.widgetWithText(FilledButton, l10n.uploadFile), findsNothing);
    expect(find.widgetWithText(OutlinedButton, l10n.newFolder), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('a Write link shows Upload + New folder but no delete',
      (tester) async {
    whenListen(
      cubit,
      const Stream<ShareLinkState>.empty(),
      initialState: ShareLinkLoaded(
        root: folder,
        path: const [],
        children: [child],
        canWrite: true,
      ),
    );

    await tester.pumpWidget(build());
    final l10n = AppLocalizations.of(tester.element(find.byType(ShareLinkView)))!;

    expect(find.widgetWithText(FilledButton, l10n.uploadFile), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, l10n.newFolder), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('a Write + allowDelete link shows upload, new folder, and delete',
      (tester) async {
    whenListen(
      cubit,
      const Stream<ShareLinkState>.empty(),
      initialState: ShareLinkLoaded(
        root: folder,
        path: const [],
        children: [child],
        canWrite: true,
        canDelete: true,
      ),
    );

    await tester.pumpWidget(build());
    final l10n = AppLocalizations.of(tester.element(find.byType(ShareLinkView)))!;

    expect(find.widgetWithText(FilledButton, l10n.uploadFile), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, l10n.newFolder), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('deleting a child asks for confirmation before calling the cubit',
      (tester) async {
    whenListen(
      cubit,
      const Stream<ShareLinkState>.empty(),
      initialState: ShareLinkLoaded(
        root: folder,
        path: const [],
        children: [child],
        canWrite: true,
        canDelete: true,
      ),
    );
    when(() => cubit.deleteItem(child.id)).thenAnswer((_) async {});

    await tester.pumpWidget(build());
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    // Teeth check 2: if the confirm dialog were skipped, deleteItem would
    // already have been called by this point — the dialog assertion below
    // proves it hasn't been.
    expect(find.byType(AlertDialog), findsOneWidget);
    verifyNever(() => cubit.deleteItem(child.id));

    final l10n = AppLocalizations.of(tester.element(find.byType(ShareLinkView)))!;
    await tester.tap(find.widgetWithText(FilledButton, l10n.delete));
    await tester.pumpAndSettle();

    verify(() => cubit.deleteItem(child.id)).called(1);
  });

  testWidgets(
    'no overflow at a narrow width with text scaled to 200% — actions row shown',
    (tester) async {
      whenListen(
        cubit,
        const Stream<ShareLinkState>.empty(),
        initialState: ShareLinkLoaded(
          root: folder,
          path: const [],
          children: [child],
          canWrite: true,
          canDelete: true,
        ),
      );
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(build());
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Tap_SharedFileRow_OpensPreviewFromGrantStream', (tester) async {
    whenListen(
      cubit,
      const Stream<ShareLinkState>.empty(),
      initialState: ShareLinkLoaded(root: folder, path: const [], children: [child]),
    );
    when(() => cubit.openPreviewStream(child))
        .thenAnswer((_) => Stream.value(Uint8List.fromList(utf8.encode('hello'))));

    await tester.pumpWidget(build());
    await tester.tap(find.text('child.txt'));
    await tester.pumpAndSettle();

    expect(find.byType(FilePreviewPage), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
    verify(() => cubit.openPreviewStream(child)).called(1);
  });

  testWidgets('SingleFileCard_UnsupportedType_HasNoPreviewButton', (tester) async {
    final docx = FileDto(
      id: 'd1',
      name: 'report.docx',
      isFolder: false,
      sizeBytes: 2048,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    whenListen(
      cubit,
      const Stream<ShareLinkState>.empty(),
      initialState: ShareLinkLoaded(root: docx, path: const [], children: null),
    );

    await tester.pumpWidget(build());

    expect(find.text('Preview'), findsNothing);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('SingleFileCard_PreviewableType_ShowsPreviewButton', (tester) async {
    whenListen(
      cubit,
      const Stream<ShareLinkState>.empty(),
      initialState: ShareLinkLoaded(root: file, path: const [], children: null),
    );

    await tester.pumpWidget(build());

    expect(find.text('Preview'), findsOneWidget);
  });

  group('download from the preview', () {
    testWidgets('Download_FromPreviewOfShareRow_ShowsErrorSnackBarAboveThePreview',
        (tester) async {
      whenListen(
        cubit,
        const Stream<ShareLinkState>.empty(),
        initialState: ShareLinkLoaded(
          root: folder,
          path: const [],
          children: [child],
          downloadErrors: {child.id: Exception('boom')},
        ),
      );
      when(() => cubit.openPreviewStream(child))
          .thenAnswer((_) => Stream.value(Uint8List.fromList(utf8.encode('hello'))));
      when(() => cubit.download(child, loadedBytes: any(named: 'loadedBytes')))
          .thenAnswer((_) async {});

      await tester.pumpWidget(build());
      await tester.tap(find.text('child.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.download));
      await tester.pumpAndSettle();

      // The loaded preview's bytes are handed over, not re-downloaded.
      verify(() => cubit.download(child,
          loadedBytes: Uint8List.fromList(utf8.encode('hello')))).called(1);
      expect(find.byType(FilePreviewPage), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Download_FromPreviewWhileAlreadyRunning_DoesNotStartAnother',
        (tester) async {
      whenListen(
        cubit,
        const Stream<ShareLinkState>.empty(),
        initialState: ShareLinkLoaded(
          root: folder,
          path: const [],
          children: [child],
          downloadProgress: {child.id: 0.5},
        ),
      );
      when(() => cubit.openPreviewStream(child))
          .thenAnswer((_) => Stream.value(Uint8List.fromList(utf8.encode('hello'))));

      await tester.pumpWidget(build());
      await tester.tap(find.text('child.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.download).last);
      await tester.pumpAndSettle();

      verifyNever(() => cubit.download(child, loadedBytes: any(named: 'loadedBytes')));
    });
  });

  testWidgets('Tap_UnsupportedSharedFileRow_DownloadsInsteadOfPreviewing', (tester) async {
    final docx = FileDto(
      id: 'd1',
      name: 'report.docx',
      isFolder: false,
      sizeBytes: 5,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    whenListen(
      cubit,
      const Stream<ShareLinkState>.empty(),
      initialState: ShareLinkLoaded(root: folder, path: const [], children: [docx]),
    );
    when(() => cubit.download(docx)).thenAnswer((_) async {});

    await tester.pumpWidget(build());
    await tester.tap(find.text('report.docx'));
    await tester.pumpAndSettle();

    verify(() => cubit.download(docx)).called(1);
    expect(find.byType(FilePreviewPage), findsNothing);
  });
}


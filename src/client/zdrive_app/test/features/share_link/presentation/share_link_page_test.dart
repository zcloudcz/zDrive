import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/files/data/file_dtos.dart';
import 'package:zdrive_app/features/share_link/presentation/pages/share_link_page.dart';
import 'package:zdrive_app/features/share_link/presentation/share_link_cubit.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';
import 'package:zdrive_app/shared/theme/app_theme.dart';
import 'package:zdrive_app/shared/widgets/brand_lockup.dart';

class MockShareLinkCubit extends MockCubit<ShareLinkState> implements ShareLinkCubit {}

void main() {
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
}

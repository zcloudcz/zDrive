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

class MockShareLinkCubit extends MockCubit<ShareLinkState> implements ShareLinkCubit {}

void main() {
  late MockShareLinkCubit cubit;

  setUp(() {
    cubit = MockShareLinkCubit();
  });

  Widget build() {
    return MaterialApp(
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
}

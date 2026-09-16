import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/di/injection.dart';
import 'package:zdrive_app/features/files/domain/file_item.dart';
import 'package:zdrive_app/features/files/domain/file_repository.dart';
import 'package:zdrive_app/features/files/presentation/pages/trash_page.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

class _Repository extends Mock implements FileRepository {}

FileItem _file(int index) => FileItem(
  id: '$index',
  name: 'file-$index.txt',
  isFolder: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

PagedResult<FileItem> _page(List<FileItem> items, {int page = 1, int? total}) =>
    PagedResult(
      items: items,
      totalCount: total ?? items.length,
      page: page,
      pageSize: 50,
    );

Widget _app() => const MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: Locale('cs'),
  home: TrashPage(),
);

void main() {
  late _Repository repository;
  final offline = DioException(
    requestOptions: RequestOptions(path: '/trash'),
    type: DioExceptionType.connectionError,
  );

  setUp(() {
    repository = _Repository();
    getIt.registerSingleton<FileRepository>(repository);
  });
  tearDown(() => getIt.reset());

  testWidgets('Trash_LoadFails_ShowsLocalizedErrorAndRetry', (tester) async {
    when(
      () => repository.listTrash(page: any(named: 'page')),
    ).thenThrow(offline);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(TrashPage)))!;
    expect(find.text(l10n.errorNoConnection), findsOneWidget);
    when(
      () => repository.listTrash(page: any(named: 'page')),
    ).thenAnswer((_) async => _page([_file(1)]));
    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();
    expect(find.text('file-1.txt'), findsOneWidget);
  });

  for (final empty in [true, false]) {
    testWidgets('Trash_${empty ? 'Empty' : 'Short'}List_PullRefreshes', (
      tester,
    ) async {
      var calls = 0;
      when(() => repository.listTrash(page: any(named: 'page'))).thenAnswer((
        _,
      ) async {
        calls++;
        return _page(calls == 1 && empty ? [] : [_file(calls)]);
      });
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 350));
      await tester.pumpAndSettle();
      expect(find.text('file-2.txt'), findsOneWidget);
      expect(calls, 2);
    });
  }

  testWidgets('Trash_SecondPageFails_KeepsRowsAndRetriesSamePage', (
    tester,
  ) async {
    when(
      () => repository.listTrash(page: 1),
    ).thenAnswer((_) async => _page(List.generate(50, _file), total: 51));
    when(() => repository.listTrash(page: 2)).thenThrow(offline);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(TrashPage)))!;
    await tester.scrollUntilVisible(find.text('Načíst další'), 500);
    await tester.tap(find.text('Načíst další'));
    await tester.pumpAndSettle();
    expect(find.text('file-49.txt'), findsOneWidget);
    expect(find.text(l10n.errorNoConnection), findsOneWidget);
    when(
      () => repository.listTrash(page: 2),
    ).thenAnswer((_) async => _page([_file(50)], page: 2, total: 51));
    await tester.ensureVisible(find.text(l10n.retry));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('file-50.txt'), 200);
    expect(find.text('file-50.txt'), findsOneWidget);
    expect(find.text('Načíst další'), findsNothing);
  });

  testWidgets('Trash_RestorePending_DisablesConflictingActions', (
    tester,
  ) async {
    final pending = Completer<FileItem>();
    when(
      () => repository.listTrash(page: any(named: 'page')),
    ).thenAnswer((_) async => _page([_file(1)]));
    when(() => repository.restoreFile('1')).thenAnswer((_) => pending.future);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final button = tester.widget<IconButton>(find.byType(IconButton).last);
    button.onPressed!();
    button.onPressed!();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final l10n = AppLocalizations.of(tester.element(find.byType(TrashPage)))!;
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, l10n.emptyTrash))
          .onPressed,
      isNull,
    );
    verify(() => repository.restoreFile('1')).called(1);
    pending.completeError(offline);
    await tester.pumpAndSettle();
    expect(find.text('file-1.txt'), findsOneWidget);
    expect(find.text(l10n.errorNoConnection), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton).last).onPressed,
      isNotNull,
    );
  });

  testWidgets('Trash_EmptyPending_ShowsProgressAndSubmitsOnce', (tester) async {
    final pending = Completer<void>();
    when(
      () => repository.listTrash(page: any(named: 'page')),
    ).thenAnswer((_) async => _page([_file(1)]));
    when(() => repository.emptyTrash()).thenAnswer((_) => pending.future);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(TrashPage)))!;
    final action = tester.widget<TextButton>(
      find.widgetWithText(TextButton, l10n.emptyTrash),
    );
    action.onPressed!();
    action.onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l10n.emptyTrash),
    );
    confirm.onPressed!();
    confirm.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    verify(() => repository.emptyTrash()).called(1);
    when(
      () => repository.listTrash(page: any(named: 'page')),
    ).thenAnswer((_) async => _page([]));
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text(l10n.noFiles), findsOneWidget);
  });

  testWidgets('Trash_DisposedDuringLoad_DoesNotSetState', (tester) async {
    final pending = Completer<PagedResult<FileItem>>();
    when(
      () => repository.listTrash(page: any(named: 'page')),
    ).thenAnswer((_) => pending.future);
    await tester.pumpWidget(_app());
    await tester.pumpWidget(const SizedBox());
    pending.complete(_page([]));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

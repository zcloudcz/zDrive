import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/di/injection.dart';
import 'package:zdrive_app/features/files/domain/file_item.dart';
import 'package:zdrive_app/features/files/domain/file_repository.dart';
import 'package:zdrive_app/features/files/presentation/pages/search_page.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

class _Repository extends Mock implements FileRepository {}

PagedResult<FileItem> _page(String name, {int page = 1, int total = 1}) =>
    PagedResult(
      items: [
        FileItem(
          id: name,
          name: name,
          isFolder: false,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ],
      totalCount: total,
      page: page,
      pageSize: 50,
    );

const _app = MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: Locale('cs'),
  home: SearchPage(),
);

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  late _Repository repository;
  final offline = DioException(
    requestOptions: RequestOptions(path: '/search'),
    type: DioExceptionType.connectionError,
  );

  setUp(() {
    repository = _Repository();
    getIt.registerSingleton<FileRepository>(repository);
  });
  tearDown(() => getIt.reset());

  testWidgets('Search_OlderResponseFinishesLast_KeepsNewestResults', (
    tester,
  ) async {
    final old = Completer<PagedResult<FileItem>>();
    when(
      () => repository.searchFiles('old', page: 1),
    ).thenAnswer((_) => old.future);
    when(
      () => repository.searchFiles('new', page: 1),
    ).thenAnswer((_) async => _page('new.txt'));
    await tester.pumpWidget(_app);
    await _search(tester, 'old');
    await _search(tester, 'new');
    old.complete(_page('old.txt'));
    await tester.pumpAndSettle();
    expect(find.text('new.txt'), findsOneWidget);
    expect(find.text('old.txt'), findsNothing);
  });

  testWidgets('Search_QueryChanges_RejectsOldResponseDuringDebounce', (
    tester,
  ) async {
    final old = Completer<PagedResult<FileItem>>();
    when(
      () => repository.searchFiles('old', page: 1),
    ).thenAnswer((_) => old.future);
    when(
      () => repository.searchFiles('new', page: 1),
    ).thenAnswer((_) async => _page('new.txt'));
    await tester.pumpWidget(_app);
    await _search(tester, 'old');
    await tester.enterText(find.byType(TextField), 'new');
    old.complete(_page('old.txt'));
    await tester.pump();
    expect(find.text('old.txt'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('new.txt'), findsOneWidget);
  });

  testWidgets('Search_ClearBeforeDebounce_CancelsRequest', (tester) async {
    when(
      () => repository.searchFiles(any(), page: any(named: 'page')),
    ).thenAnswer((_) async => _page('unexpected.txt'));
    await tester.pumpWidget(_app);
    await tester.enterText(find.byType(TextField), 'query');
    await tester.pump();
    final clear = find.byTooltip('Vymazat hledání');
    expect(clear, findsOneWidget);
    await tester.tap(clear);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    verifyNever(() => repository.searchFiles(any(), page: any(named: 'page')));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('unexpected.txt'), findsNothing);
  });

  for (final fails in [false, true]) {
    testWidgets(
      'Search_ClearDuring${fails ? 'Failure' : 'Success'}_IgnoresCompletion',
      (tester) async {
        final pending = Completer<PagedResult<FileItem>>();
        when(
          () => repository.searchFiles('query', page: 1),
        ).thenAnswer((_) => pending.future);
        await tester.pumpWidget(_app);
        await _search(tester, 'query');
        await tester.tap(find.byIcon(Icons.clear));
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        if (fails) {
          pending.completeError(offline);
        } else {
          pending.complete(_page('stale.txt'));
        }
        await tester.pumpAndSettle();
        expect(find.text('stale.txt'), findsNothing);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(SearchPage)),
        )!;
        expect(find.text(l10n.errorNoConnection), findsNothing);
        expect(find.byIcon(Icons.search), findsOneWidget);
      },
    );
  }

  testWidgets('Search_Fails_ShowsLocalizedRetryForTrimmedQuery', (
    tester,
  ) async {
    when(() => repository.searchFiles('query', page: 1)).thenThrow(offline);
    await tester.pumpWidget(_app);
    await _search(tester, '  query  ');
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(SearchPage)))!;
    expect(find.text(l10n.errorNoConnection), findsOneWidget);
    expect(find.text(l10n.noFiles), findsNothing);
    when(
      () => repository.searchFiles('query', page: 1),
    ).thenAnswer((_) async => _page('recovered.txt'));
    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();
    expect(find.text('recovered.txt'), findsOneWidget);
    expect(find.text(l10n.errorNoConnection), findsNothing);
  });

  testWidgets('Search_SecondPageFails_KeepsRowsAndRetries', (tester) async {
    when(
      () => repository.searchFiles('query', page: 1),
    ).thenAnswer((_) async => _page('first.txt', total: 51));
    when(() => repository.searchFiles('query', page: 2)).thenThrow(offline);
    await tester.pumpWidget(_app);
    await _search(tester, 'query');
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(SearchPage)))!;
    await tester.tap(find.text(l10n.loadMore));
    await tester.pumpAndSettle();
    expect(find.text('first.txt'), findsOneWidget);
    expect(find.text(l10n.errorNoConnection), findsOneWidget);
    when(
      () => repository.searchFiles('query', page: 2),
    ).thenAnswer((_) async => _page('last.txt', page: 2, total: 51));
    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();
    expect(find.text('first.txt'), findsOneWidget);
    expect(find.text('last.txt'), findsOneWidget);
    expect(find.text(l10n.loadMore), findsNothing);
  });

  testWidgets('Search_DisposedBeforeResponse_DoesNotSetState', (tester) async {
    final pending = Completer<PagedResult<FileItem>>();
    when(
      () => repository.searchFiles('query', page: 1),
    ).thenAnswer((_) => pending.future);
    await tester.pumpWidget(_app);
    await _search(tester, 'query');
    await tester.pumpWidget(const SizedBox());
    pending.completeError(offline);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

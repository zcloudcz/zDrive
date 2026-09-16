import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/features/files/domain/file_version.dart';
import 'package:zdrive_app/features/files/presentation/widgets/version_history_dialog.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

FileVersion _version(int number) => FileVersion(
  id: '$number',
  fileId: 'file',
  versionNumber: number,
  blobVersionId: 'hash-$number',
  sizeBytes: 100,
  createdAt: DateTime(2026),
);

Widget _app({
  required Future<List<FileVersion>> Function(String) load,
  required Future<FileVersion> Function(String, String) restore,
  String fileId = 'file',
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('cs'),
  home: Scaffold(
    body: VersionHistoryDialog(
      fileId: fileId,
      fileName: 'notes.txt',
      onLoadVersions: load,
      onRestore: restore,
    ),
  ),
);

void main() {
  final offline = DioException(
    requestOptions: RequestOptions(path: '/versions'),
    type: DioExceptionType.connectionError,
  );

  testWidgets('Versions_LoadFails_LocalizedRetryLoadsVersions', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(
        load: (_) async {
          if (++calls == 1) throw offline;
          return [_version(2), _version(1)];
        },
        restore: (_, _) async => _version(3),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(VersionHistoryDialog)),
    )!;
    expect(find.text(l10n.errorNoConnection), findsOneWidget);
    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();
    expect(find.text(l10n.versionLabel(1)), findsOneWidget);
    expect(find.text(l10n.errorNoConnection), findsNothing);
  });

  testWidgets('Versions_RestoreFails_KeepsVersionsAndAllowsRetry', (
    tester,
  ) async {
    final pending = Completer<FileVersion>();
    var restores = 0;
    await tester.pumpWidget(
      _app(
        load: (_) async => [_version(2), _version(1)],
        restore: (_, _) {
          restores++;
          return pending.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(VersionHistoryDialog)),
    )!;
    final action = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.restore),
        matching: find.byType(IconButton),
      ),
    );
    action.onPressed!();
    action.onPressed!();
    await tester.pumpAndSettle();
    expect(find.text(l10n.confirmRestoreVersion), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l10n.restoreVersion),
    );
    confirm.onPressed!();
    confirm.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(restores, 1);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.restore),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    pending.completeError(offline);
    await tester.pumpAndSettle();
    expect(find.text(l10n.errorNoConnection), findsOneWidget);
    expect(find.text(l10n.versionLabel(1)), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.restore),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('Versions_DisposedDuringRestore_DoesNotReload', (tester) async {
    final pending = Completer<FileVersion>();
    var loads = 0;
    await tester.pumpWidget(
      _app(
        load: (_) async {
          loads++;
          return [_version(2), _version(1)];
        },
        restore: (_, _) => pending.future,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.restore));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(_version(3));
    await tester.pump();
    expect(loads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Versions_FileChanges_IgnoresStaleLoad', (tester) async {
    final first = Completer<List<FileVersion>>();
    Future<List<FileVersion>> load(String id) =>
        id == 'file' ? first.future : Future.value([_version(9)]);
    await tester.pumpWidget(
      _app(load: load, restore: (_, _) async => _version(3)),
    );
    await tester.pumpWidget(
      _app(fileId: 'other', load: load, restore: (_, _) async => _version(3)),
    );
    await tester.pump();
    first.complete([_version(1)]);
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(VersionHistoryDialog)),
    )!;
    expect(find.text(l10n.versionLabel(9)), findsOneWidget);
    expect(find.text(l10n.versionLabel(1)), findsNothing);
  });
}

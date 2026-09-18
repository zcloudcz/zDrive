import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/core/network/api_constants.dart';
import 'package:zdrive_app/features/files/domain/file_item.dart';
import 'package:zdrive_app/features/files/presentation/widgets/share_dialog.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

void main() {
  testWidgets(
      'ShareLink_Generated_UsesTheWebAppHashRoute — the link must open the '
      'Drive web UI (a hash route, so it survives GitHub Pages having no SPA '
      'fallback), never the API base URL', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: ShareDialog(
          fileId: 'f1',
          onShare: (fileId, permission, expiresAt, {allowDelete = false}) async =>
              const ShareInfo(
            id: 's1',
            fileId: 'f1',
            permission: SharePermission.read,
            linkToken: 'abc123',
          ),
        ),
      ),
    ));

    final l10n = AppLocalizations.of(tester.element(find.byType(ShareDialog)))!;
    await tester.tap(find.widgetWithText(FilledButton, l10n.shareLink));
    await tester.pumpAndSettle();

    expect(
      find.text('${ApiConstants.webBaseUrl}/#/s/abc123'),
      findsOneWidget,
    );
    expect(find.text('https://drive.zcloud.cz/#/s/abc123'), findsOneWidget);
  });

  testWidgets(
      'AllowDeleteCheckbox_Toggled_PassedToOnShare — the checkbox is '
      'independent of the Permission dropdown, so a Read link with deletion '
      'allowed must still reach onShare', (tester) async {
    bool? capturedAllowDelete;

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: ShareDialog(
          fileId: 'f1',
          onShare: (fileId, permission, expiresAt, {allowDelete = false}) async {
            capturedAllowDelete = allowDelete;
            return ShareInfo(
              id: 's1',
              fileId: 'f1',
              permission: permission,
              linkToken: 'abc123',
              allowDelete: allowDelete,
            );
          },
        ),
      ),
    ));

    final l10n = AppLocalizations.of(tester.element(find.byType(ShareDialog)))!;
    await tester.tap(find.text(l10n.allowDelete));
    await tester.tap(find.widgetWithText(FilledButton, l10n.shareLink));
    await tester.pumpAndSettle();

    expect(capturedAllowDelete, isTrue);
  });
}

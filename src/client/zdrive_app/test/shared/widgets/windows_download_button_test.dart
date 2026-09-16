import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';
import 'package:zdrive_app/shared/widgets/windows_download_button.dart';

void main() {
  for (final compact in [false, true]) {
    testWidgets('download button is web-only on Windows (compact: $compact)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: WindowsDownloadButton(compact: compact)),
      ));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.desktop_windows_outlined), kIsWeb ? findsOneWidget : findsNothing);
      expect(find.byType(compact ? IconButton : TextButton), kIsWeb ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }
}

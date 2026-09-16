import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';
import 'package:zdrive_app/shared/widgets/app_settings_menu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'zDrive',
      packageName: 'cz.zcloud.zdrive',
      version: '7.8.9',
      buildNumber: '42',
      buildSignature: '',
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('zdrive/windows_lifecycle'),
          null,
        );
  });

  Future<void> pumpMenu(WidgetTester tester, String locale) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(appBar: AppBar(actions: const [AppSettingsMenu()])),
      ),
    );
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  }

  for (final locale in ['cs', 'en']) {
    testWidgets('About_${locale}_ShowsActualVersionAndBuild', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await pumpMenu(tester, locale);
      expect(find.text(locale == 'cs' ? 'Ukončit' : 'Exit'), findsOneWidget);
      await tester.tap(find.text(locale == 'cs' ? 'O programu' : 'About'));
      await tester.pumpAndSettle();
      expect(find.textContaining('7.8.9+42'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  }

  testWidgets('Exit_Windows_InvokesExplicitQuit', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('zdrive/windows_lifecycle'),
          (call) async {
            calls.add(call.method);
            return null;
          },
        );
    await pumpMenu(tester, 'en');
    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();
    expect(calls, ['quit']);
  });

  testWidgets('Exit_FailedQuit_ShowsLocalizedError', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('zdrive/windows_lifecycle'),
          (_) async => throw PlatformException(code: 'quit_failed'),
        );
    await pumpMenu(tester, 'cs');
    await tester.tap(find.text('Ukončit'));
    await tester.pumpAndSettle();
    expect(
      find.text('Aplikaci se nepodařilo ukončit. Zkuste to znovu.'),
      findsOneWidget,
    );
  });

  testWidgets('Menu_UnsupportedPlatform_HidesExit', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpMenu(tester, 'en');
    expect(find.text('Exit'), findsNothing);
    expect(find.text('About'), findsOneWidget);
  });
}

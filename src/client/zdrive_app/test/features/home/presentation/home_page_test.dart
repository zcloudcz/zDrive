import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/features/home/presentation/home_page.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

void main() {
  // buildHomeDestinations takes photosEnabled as a parameter (default:
  // kPhotosEnabled, a compile-time bool.fromEnvironment) instead of reading
  // it directly, so this drives both branches without a `--dart-define` per
  // test run — the same reason app_router_test.dart drives
  // buildSyncShellProvider/buildHomeBranches directly rather than through a
  // real router.
  Future<AppLocalizations> loadL10n(WidgetTester tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Builder(builder: (context) {
        l10n = AppLocalizations.of(context)!;
        return const SizedBox();
      }),
    ));
    await tester.pump();
    return l10n;
  }

  testWidgets('photosEnabled: false omits the Photos destination', (tester) async {
    final l10n = await loadL10n(tester);

    final destinations = buildHomeDestinations(l10n, photosEnabled: false);

    expect(destinations, hasLength(2));
    expect(destinations.map((d) => d.label), isNot(contains(l10n.photos)));
  });

  testWidgets('photosEnabled: true includes the Photos destination', (tester) async {
    final l10n = await loadL10n(tester);

    final destinations = buildHomeDestinations(l10n, photosEnabled: true);

    expect(destinations, hasLength(3));
    expect(destinations.map((d) => d.label), contains(l10n.photos));
  });
}

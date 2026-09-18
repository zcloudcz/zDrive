import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zdrive_app/features/home/presentation/home_page.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';
import 'package:zdrive_app/shared/l10n/app_localizations_en.dart';
import 'package:zdrive_app/shared/router/app_router.dart';
import 'package:zdrive_app/shared/widgets/brand_lockup.dart';

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

  // StatefulNavigationShell matches branches to destinations POSITIONALLY
  // (goBranch(index)), so home_page.dart's destination list and
  // app_router.dart's branch list must always be the same length under both
  // flag values, or tapping a tab throws a RangeError. buildHomeDestinations
  // and buildHomeBranches are each gated by the same kPhotosEnabled
  // independently, so this compares them directly rather than
  // re-implementing the gate here.
  test(
      'destination count matches the real router\'s branch count, '
      'for both values of the Photos flag', () {
    final l10n = AppLocalizationsEn();

    for (final photosEnabled in [false, true]) {
      expect(
        buildHomeDestinations(l10n, photosEnabled: photosEnabled).length,
        buildHomeBranches(photosEnabled: photosEnabled).length,
        reason: 'photosEnabled: $photosEnabled',
      );
    }
  });

  // --- Adaptive shell: NavigationBar (<840px) vs NavigationRail (>=840px) ---
  //
  // A real StatefulNavigationShell needs a real GoRouter, so this builds a
  // minimal one with trivial branch pages — no DI/getIt, unlike the app's
  // own router (app_router_test.dart already avoids the same weight by
  // driving buildHomeBranches/buildSyncShellProvider directly rather than
  // through a real router).
  //
  // HomePage itself calls buildHomeDestinations(l10n) with the compile-time
  // kPhotosEnabled default, so the branch count here is derived from that
  // same call rather than hardcoded — hardcoding it silently drifted from
  // the real destination count under --dart-define=PHOTOS_ENABLED=true,
  // where HomePage renders 3 destinations over what used to be 2 branches
  // and goBranch(2) threw a RangeError (review round 2, finding 2).
  Widget buildHomeApp() {
    final branchCount =
        buildHomeDestinations(AppLocalizationsEn()).length;
    final router = GoRouter(
      initialLocation: '/home/0',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) =>
              HomePage(navigationShell: shell),
          branches: [
            for (var i = 0; i < branchCount; i++)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/home/$i',
                    builder: (_, _) => _BranchScreen('$i'),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    return MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
    );
  }

  // tester.view.physicalSize leaks into later tests in the same file unless
  // reset — same gotcha PR4's login/register responsive tests hit.
  void setTestSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('below 840px: NavigationBar, no NavigationRail', (tester) async {
    setTestSize(tester, const Size(600, 900));

    await tester.pumpWidget(buildHomeApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('at/above 840px: NavigationRail with BrandLockup, no NavigationBar',
      (tester) async {
    setTestSize(tester, const Size(1200, 900));

    await tester.pumpWidget(buildHomeApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byType(BrandLockup),
      ),
      findsOneWidget,
    );
  });

  testWidgets('same destination labels, in the same order, at both widths',
      (tester) async {
    for (final size in [const Size(600, 900), const Size(1200, 900)]) {
      setTestSize(tester, size);

      await tester.pumpWidget(buildHomeApp());
      await tester.pumpAndSettle();

      expect(find.text('Files'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    }
  });

  testWidgets('tapping a rail destination navigates like the bar does',
      (tester) async {
    setTestSize(tester, const Size(1200, 900));
    // Settings is always the last destination/branch (buildHomeDestinations
    // puts Photos, when present, between Files and Settings).
    final lastIndex = buildHomeDestinations(AppLocalizationsEn()).length - 1;

    await tester.pumpWidget(buildHomeApp());
    await tester.pumpAndSettle();

    expect(find.text('branch-0'), findsOneWidget);
    expect(find.text('branch-$lastIndex'), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('branch-$lastIndex'), findsOneWidget);
    expect(find.text('branch-0'), findsNothing);
  });
}

class _BranchScreen extends StatelessWidget {
  final String label;

  const _BranchScreen(this.label);

  @override
  Widget build(BuildContext context) => Center(child: Text('branch-$label'));
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zdrive_app/features/home/presentation/home_page.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';
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

  // --- Adaptive shell: NavigationBar (<840px) vs NavigationRail (>=840px) ---
  //
  // A real StatefulNavigationShell needs a real GoRouter, so this builds a
  // minimal one with trivial branch pages — no DI/getIt, unlike the app's
  // own router (app_router_test.dart already avoids the same weight by
  // driving buildHomeBranches/buildSyncShellProvider directly rather than
  // through a real router).
  //
  // HomePage itself calls buildHomeDestinations(l10n) with the compile-time
  // kPhotosEnabled default (false unless run with
  // --dart-define=PHOTOS_ENABLED=true) — it has no per-instance override, so
  // these branches are fixed at two (files, settings) to match what the
  // widget actually renders. The Photos-gate assertion from PR5's acceptance
  // criteria ("destination count still matches buildHomeDestinations(...) in
  // both") is exactly the two tests above, which already drive both flag
  // values directly.
  Widget buildHomeApp() {
    final router = GoRouter(
      initialLocation: '/home/a',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) =>
              HomePage(navigationShell: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home/a',
                  builder: (_, _) => const _BranchScreen('a'),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home/c',
                  builder: (_, _) => const _BranchScreen('c'),
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

    await tester.pumpWidget(buildHomeApp());
    await tester.pumpAndSettle();

    expect(find.text('branch-a'), findsOneWidget);
    expect(find.text('branch-c'), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('branch-c'), findsOneWidget);
    expect(find.text('branch-a'), findsNothing);
  });
}

class _BranchScreen extends StatelessWidget {
  final String label;

  const _BranchScreen(this.label);

  @override
  Widget build(BuildContext context) => Center(child: Text('branch-$label'));
}

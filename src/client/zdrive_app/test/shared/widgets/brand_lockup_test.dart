import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/shared/theme/app_theme.dart';
import 'package:zdrive_app/shared/widgets/brand_lockup.dart';

import '../theme/app_theme_test.dart' show contrastRatio;

void main() {
  testWidgets('BrandLockup renders the zDrive wordmark and its semantics label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BrandLockup())));

    expect(find.text('zDrive'), findsOneWidget);
    expect(find.bySemanticsLabel('zDrive'), findsOneWidget);
    expect(tester.takeException(), isNull);

    handle.dispose();
  });

  testWidgets('BrandLockup mark image is excluded from semantics', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BrandLockup())));

    // The Image is wrapped in ExcludeSemantics, so only one semantics node
    // (the Semantics(label: 'zDrive') wrapper) should carry the label —
    // the image contributes no separate node.
    expect(find.bySemanticsLabel('zDrive'), findsOneWidget);

    handle.dispose();
  });

  testWidgets(
    'monochrome (on-dark) paints the wordmark white regardless of the '
    'ambient TextStyle — titleLarge carries its own explicit colour that '
    'would otherwise beat AppBar.foregroundColor (PR review BLOCKER)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            backgroundColor: AppTheme.brandPetrol,
            body: BrandLockup(monochrome: true),
          ),
        ),
      );

      final style = tester.widget<Text>(find.text('zDrive')).style!;
      expect(style.color, Colors.white);
      expect(contrastRatio(style.color!, AppTheme.brandPetrol), greaterThanOrEqualTo(4.5));
    },
  );

  testWidgets('the default (non-monochrome) variant follows colorScheme.onSurface',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const Scaffold(body: BrandLockup())),
    );

    final style = tester.widget<Text>(find.text('zDrive')).style!;
    expect(style.color, AppTheme.light.colorScheme.onSurface);
  });

  testWidgets(
    'monochrome does not tint the mark image — the source asset is an opaque '
    'tile, so tinting it paints every pixel solid white (regression: mark '
    'rendered as a blank white square on the petrol header/login panel)',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BrandLockup(monochrome: true))),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.color, isNull);
      expect(image.colorBlendMode, isNull);
      expect(find.ancestor(of: find.byType(Image), matching: find.byType(ColorFiltered)),
          findsNothing);
      expect(find.ancestor(of: find.byType(Image), matching: find.byType(ShaderMask)),
          findsNothing);
    },
  );
}

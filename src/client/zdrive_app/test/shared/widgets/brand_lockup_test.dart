import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/shared/widgets/brand_lockup.dart';

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
}

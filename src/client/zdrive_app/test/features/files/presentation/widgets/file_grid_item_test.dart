import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/features/files/domain/file_item.dart';
import 'package:zdrive_app/features/files/presentation/widgets/file_grid_item.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';
import 'package:zdrive_app/shared/theme/app_theme.dart';

void main() {
  final testFile = FileItem(
    id: 'file-1',
    name: 'report.pdf',
    isFolder: false,
    sizeBytes: 1024,
    mimeType: 'application/pdf',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  Widget build() {
    return MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: FileGridItem(
          file: testFile,
          onTap: () {},
          onRename: () {},
          onDelete: () {},
          onShare: () {},
          onVersions: () {},
        ),
      ),
    );
  }

  testWidgets('icon tile is a solid surfaceContainerHighest fill, not a wash',
      (tester) async {
    await tester.pumpWidget(build());

    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(FileGridItem),
        matching: find.byType(Container),
      ),
    );
    final color = container.color!;

    expect(color, AppTheme.light.colorScheme.surfaceContainerHighest);
    // The bug this guards against: `.withValues(alpha: 0.3)` on the same
    // role, which kept the hex but dropped the alpha channel to 0.3.
    expect(color.a, 1.0);
  });

  testWidgets('overflow menu hit box is at least 48x48 despite the small glyph',
      (tester) async {
    await tester.pumpWidget(build());

    final size = tester.getSize(find.byType(IconButton));

    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });
}

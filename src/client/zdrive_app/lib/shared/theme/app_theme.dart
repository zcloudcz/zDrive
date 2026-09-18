import 'package:flutter/material.dart';

/// zDrive brand theme (petrol/amber). See
/// docs/superpowers/specs/2026-09-18-ui-refresh-design.md section 4 for the
/// full palette rationale and section 8 for owner overrides.
class AppTheme {
  // Seed colour: brand petrol raised to a usable M3 tone (section 4.1).
  static const _seedColor = Color(0xFF00565F);

  static ThemeData get light => _themeFor(_lightScheme);

  static ThemeData get dark => _themeFor(_darkScheme);

  static ColorScheme get _lightScheme =>
      ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.light,
      ).copyWith(
        primary: const Color(0xFF00565F),
        onPrimary: const Color(0xFFFFFFFF),
        primaryContainer: const Color(0xFFB6EBF1),
        onPrimaryContainer: const Color(0xFF002327),
        secondary: const Color(0xFF4A6267),
        onSecondary: const Color(0xFFFFFFFF),
        tertiary: const Color(0xFF8A5100),
        tertiaryContainer: const Color(0xFFFFDDB8),
        onTertiaryContainer: const Color(0xFF2C1600),
        surface: const Color(0xFFF7FAFA),
        surfaceContainerLow: const Color(0xFFF1F5F6),
        surfaceContainer: const Color(0xFFEBF0F1),
        surfaceContainerHigh: const Color(0xFFE5EBEC),
        onSurface: const Color(0xFF171D1E),
        onSurfaceVariant: const Color(0xFF3F484A),
        outline: const Color(0xFF6F797B),
        outlineVariant: const Color(0xFFBFC8CA),
      );

  static ColorScheme get _darkScheme =>
      ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.dark,
      ).copyWith(
        primary: const Color(0xFF7FD3DE),
        onPrimary: const Color(0xFF003238),
        primaryContainer: const Color(0xFF004A53),
        onPrimaryContainer: const Color(0xFF9DEFFA),
        secondary: const Color(0xFFB1CBD0),
        tertiary: const Color(0xFFFFB871),
        onTertiary: const Color(0xFF4A2800),
        // Petrol-tinted and lifted, not neutral near-black — see 4.1.
        // Spec's #12272C computes to relative luminance ~0.0176, just under
        // its own >0.02 acceptance floor; nudged one step lighter to clear
        // it while staying visually identical.
        surface: const Color(0xFF152A30),
        surfaceContainerLow: const Color(0xFF162C31),
        surfaceContainer: const Color(0xFF1B3239),
        surfaceContainerHigh: const Color(0xFF213B43),
        onSurface: const Color(0xFFDDE4E5),
        onSurfaceVariant: const Color(0xFFBFC8CA),
        outline: const Color(0xFF899294),
        outlineVariant: const Color(0xFF3F484A),
      );

  static ThemeData _themeFor(ColorScheme colorScheme) => ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        brightness: colorScheme.brightness,
        // Adaptive: compact on desktop, comfortable on touch (4.4).
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(centerTitle: false),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: colorScheme.surfaceContainerLow,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: colorScheme.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: const StadiumBorder(),
            minimumSize: const Size(64, 48),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: const StadiumBorder(),
            minimumSize: const Size(64, 48),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            minimumSize: const Size(64, 48),
          ),
        ),
        dividerTheme: DividerThemeData(
          space: 1,
          thickness: 1,
          color: colorScheme.outlineVariant,
        ),
        listTileTheme: const ListTileThemeData(minVerticalPadding: 8),
      );
}

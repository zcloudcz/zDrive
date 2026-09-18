import 'package:flutter/material.dart';

/// zDrive brand theme (petrol/amber). See
/// docs/superpowers/specs/2026-09-18-ui-refresh-design.md section 4 for the
/// full palette rationale and section 8 for owner overrides.
class AppTheme {
  // Seed colour: brand petrol raised to a usable M3 tone (section 4.1).
  static const _seedColor = Color(0xFF00565F);

  // The literal brand petrol (section 8.1) — for brand surfaces (header
  // bands, splash) that must stay on-brand regardless of scheme, as opposed
  // to colorScheme.primary above, which is the lighter usable-tone seed.
  static const Color brandPetrol = Color(0xFF003840);

  static ThemeData get light => _themeFor(_lightScheme);

  static ThemeData get dark => _themeFor(_darkScheme);

  // Light surface ramp, dimmest to brightest (section 4.1's three named
  // tiers extended so surfaceContainerHighest/Lowest, surfaceDim and
  // surfaceBright stay on the same petrol-tinted ramp instead of falling
  // back to fromSeed's neutral grey — that neutral/petrol mismatch was a
  // visible hue break in grid tiles etc):
  //   surfaceDim             #D9E1E2
  //   surfaceContainerHighest #DFE6E7
  //   surfaceContainerHigh    #E5EBEC  (spec)
  //   surfaceContainer        #EBF0F1  (spec)
  //   surfaceContainerLow     #F1F5F6  (spec)
  //   surface                 #F7FAFA  (spec)
  //   surfaceContainerLowest  #FBFDFD
  //   surfaceBright           #FEFFFF
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
        surfaceDim: const Color(0xFFD9E1E2),
        surfaceContainerHighest: const Color(0xFFDFE6E7),
        surfaceContainerHigh: const Color(0xFFE5EBEC),
        surfaceContainer: const Color(0xFFEBF0F1),
        surfaceContainerLow: const Color(0xFFF1F5F6),
        surface: const Color(0xFFF7FAFA),
        surfaceContainerLowest: const Color(0xFFFBFDFD),
        surfaceBright: const Color(0xFFFEFFFF),
        onSurface: const Color(0xFF171D1E),
        onSurfaceVariant: const Color(0xFF3F484A),
        outline: const Color(0xFF6F797B),
        outlineVariant: const Color(0xFFBFC8CA),
      );

  // Dark surface ramp, dimmest to brightest — petrol-tinted and lifted
  // throughout, never neutral near-black (see 4.1). Spec's #12272C computes
  // to relative luminance ~0.0176, just under its own >0.02 acceptance
  // floor for `surface`; nudged one step lighter to clear it, and reused
  // as-is for surfaceContainerLowest (fine there — only `surface` itself
  // was luminance-floor-tested). surfaceContainerHighest/Lowest, surfaceDim
  // and surfaceBright extend the same ramp instead of falling back to
  // fromSeed's neutral grey:
  //   surfaceDim              #102429
  //   surfaceContainerLowest  #12272C  (spec's literal surface hex)
  //   surface                 #152A30  (adjusted, see above)
  //   surfaceContainerLow     #162C31  (spec)
  //   surfaceContainer        #1B3239  (spec)
  //   surfaceContainerHigh    #213B43  (spec)
  //   surfaceContainerHighest #27444D
  //   surfaceBright           #2D4D57
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
        surfaceDim: const Color(0xFF102429),
        surfaceContainerLowest: const Color(0xFF12272C),
        surface: const Color(0xFF152A30),
        surfaceContainerLow: const Color(0xFF162C31),
        surfaceContainer: const Color(0xFF1B3239),
        surfaceContainerHigh: const Color(0xFF213B43),
        surfaceContainerHighest: const Color(0xFF27444D),
        surfaceBright: const Color(0xFF2D4D57),
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
          // surfaceContainerLow is ~1.02:1 against surface — effectively
          // invisible as a fill. surfaceContainerHigh gives a visible fill
          // in both modes while keeping text/hint contrast on it >= 4.5.
          fillColor: colorScheme.surfaceContainerHigh,
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
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: const StadiumBorder(),
            minimumSize: const Size(64, 48),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            shape: const StadiumBorder(),
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

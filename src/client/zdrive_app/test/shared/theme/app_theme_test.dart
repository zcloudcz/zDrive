import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/shared/theme/app_theme.dart';

/// WCAG 2.1 relative luminance, see
/// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
double _relativeLuminance(Color color) {
  double channel(double c) {
    return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = channel(color.r);
  final g = channel(color.g);
  final b = channel(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  final light = AppTheme.light.colorScheme;
  final dark = AppTheme.dark.colorScheme;

  group('AppTheme palette (section 4.1)', () {
    test('light primary matches brand petrol', () {
      expect(light.primary, const Color(0xFF00565F));
    });

    test('light roles match the 4.1 table exactly', () {
      expect(light.onPrimary, const Color(0xFFFFFFFF));
      expect(light.primaryContainer, const Color(0xFFB6EBF1));
      expect(light.onPrimaryContainer, const Color(0xFF002327));
      expect(light.secondary, const Color(0xFF4A6267));
      expect(light.onSecondary, const Color(0xFFFFFFFF));
      expect(light.tertiary, const Color(0xFF8A5100));
      expect(light.tertiaryContainer, const Color(0xFFFFDDB8));
      expect(light.onTertiaryContainer, const Color(0xFF2C1600));
      expect(light.surface, const Color(0xFFF7FAFA));
      expect(light.surfaceContainerLow, const Color(0xFFF1F5F6));
      expect(light.surfaceContainer, const Color(0xFFEBF0F1));
      expect(light.surfaceContainerHigh, const Color(0xFFE5EBEC));
      expect(light.onSurface, const Color(0xFF171D1E));
      expect(light.onSurfaceVariant, const Color(0xFF3F484A));
      expect(light.outline, const Color(0xFF6F797B));
      expect(light.outlineVariant, const Color(0xFFBFC8CA));
    });

    test('dark roles match the 4.1 table exactly', () {
      expect(dark.primary, const Color(0xFF7FD3DE));
      expect(dark.onPrimary, const Color(0xFF003238));
      expect(dark.primaryContainer, const Color(0xFF004A53));
      expect(dark.onPrimaryContainer, const Color(0xFF9DEFFA));
      expect(dark.secondary, const Color(0xFFB1CBD0));
      expect(dark.tertiary, const Color(0xFFFFB871));
      expect(dark.onTertiary, const Color(0xFF4A2800));
      // Spec table lists #12272C, but that hex fails the spec's own
      // luminance floor (see comment in app_theme.dart) — adjusted
      // minimally to #152A30 to clear it.
      expect(dark.surface, const Color(0xFF152A30));
      expect(dark.surfaceContainerLow, const Color(0xFF162C31));
      expect(dark.surfaceContainer, const Color(0xFF1B3239));
      expect(dark.surfaceContainerHigh, const Color(0xFF213B43));
      expect(dark.onSurface, const Color(0xFFDDE4E5));
      expect(dark.onSurfaceVariant, const Color(0xFFBFC8CA));
      expect(dark.outline, const Color(0xFF899294));
      expect(dark.outlineVariant, const Color(0xFF3F484A));
    });

    test('dark surface is petrol-tinted, not near-black', () {
      // Regression guard: ColorScheme.fromSeed on this seed alone would
      // produce a neutral surface around L*~7% (relative luminance ~0.01).
      // #12272C must clear that floor.
      expect(_relativeLuminance(dark.surface), greaterThan(0.02));
    });
  });

  group('AppTheme contrast (WCAG 2.1, section 4.1/4.6)', () {
    void expectTextPair(String label, Color fg, Color bg) {
      final ratio = contrastRatio(fg, bg);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: '$label contrast is ${ratio.toStringAsFixed(2)}, need >= 4.5',
      );
    }

    void expectOutlinePair(String label, Color fg, Color bg) {
      final ratio = contrastRatio(fg, bg);
      expect(
        ratio,
        greaterThanOrEqualTo(3.0),
        reason: '$label contrast is ${ratio.toStringAsFixed(2)}, need >= 3.0',
      );
    }

    test('light mode text pairs', () {
      expectTextPair('L onSurface/surface', light.onSurface, light.surface);
      expectTextPair(
        'L onSurfaceVariant/surface',
        light.onSurfaceVariant,
        light.surface,
      );
      expectTextPair(
        'L onSurface/surfaceContainer',
        light.onSurface,
        light.surfaceContainer,
      );
      expectTextPair('L onPrimary/primary', light.onPrimary, light.primary);
      expectTextPair('L primary/surface', light.primary, light.surface);
      expectTextPair(
        'L onPrimaryContainer/primaryContainer',
        light.onPrimaryContainer,
        light.primaryContainer,
      );
      expectTextPair(
        'L onTertiaryContainer/tertiaryContainer',
        light.onTertiaryContainer,
        light.tertiaryContainer,
      );
      expectOutlinePair('L outline/surface', light.outline, light.surface);
    });

    test('dark mode text pairs', () {
      expectTextPair('D onSurface/surface', dark.onSurface, dark.surface);
      expectTextPair(
        'D onSurfaceVariant/surface',
        dark.onSurfaceVariant,
        dark.surface,
      );
      expectTextPair(
        'D onSurface/surfaceContainer',
        dark.onSurface,
        dark.surfaceContainer,
      );
      expectTextPair(
        'D onSurface/surfaceContainerHigh',
        dark.onSurface,
        dark.surfaceContainerHigh,
      );
      expectTextPair('D onPrimary/primary', dark.onPrimary, dark.primary);
      expectTextPair('D primary/surface', dark.primary, dark.surface);
      expectTextPair('D tertiary/surface', dark.tertiary, dark.surface);
      expectOutlinePair('D outline/surface', dark.outline, dark.surface);
    });
  });

  group('AppTheme component tokens (section 4.4)', () {
    test('filled buttons use a stadium shape', () {
      final shape = AppTheme.light.filledButtonTheme.style!.shape!
          .resolve(<WidgetState>{});
      expect(shape, isA<StadiumBorder>());
    });

    test('cards have a 16dp radius', () {
      final shape = AppTheme.light.cardTheme.shape as RoundedRectangleBorder;
      expect(
        shape.borderRadius,
        BorderRadius.circular(16),
      );
    });

    test('density is adaptive to platform', () {
      expect(
        AppTheme.light.visualDensity,
        VisualDensity.adaptivePlatformDensity,
      );
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/shared/l10n/app_locale.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';
import 'package:zdrive_app/shared/l10n/relative_time.dart';

void main() {
  const supported = AppLocalizations.supportedLocales;

  test('relative timestamps use the selected language including Slovak', () {
    final now = DateTime(2026, 9, 16, 12);
    final date = now.subtract(const Duration(minutes: 5));
    expect(formatRelativeTime(date, 'sk', clock: now), 'pred 5 minútami');
    expect(formatRelativeTime(date, 'cs', clock: now), 'před 5 minutami');
    expect(formatRelativeTime(date, 'en', clock: now), '5 minutes ago');
    for (final language in ['es', 'fi', 'sv', 'de', 'fr', 'nl', 'ja', 'zh']) {
      final formatted = formatRelativeTime(date, language, clock: now);
      expect(formatted, isNot('5 minutes ago'), reason: language);
      expect(formatted, isNotEmpty);
    }
  });

  test('unsupported or missing preferences fall back to English', () {
    for (final preferences in <List<Locale>?>[
      null,
      [],
      [const Locale('pt', 'BR')],
    ]) {
      expect(resolveAppLocale(preferences, supported), const Locale('en'));
    }
  });

  test('matches supported regional languages in device preference order', () {
    for (final language in [
      'cs',
      'sk',
      'es',
      'fi',
      'sv',
      'de',
      'fr',
      'nl',
      'ja',
    ]) {
      expect(
        resolveAppLocale([
          Locale(language, 'XX'),
          const Locale('en'),
        ], supported),
        Locale(language),
      );
    }
    expect(
      resolveAppLocale([
        const Locale('pt'),
        const Locale('fr', 'CH'),
        const Locale('de'),
      ], supported),
      const Locale('fr'),
    );
  });

  test(
    'Chinese script takes precedence over region and Hant is unsupported',
    () {
      for (final locale in [
        const Locale('zh'),
        const Locale('zh', 'CN'),
        const Locale('zh', 'SG'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
          countryCode: 'TW',
        ),
      ]) {
        expect(resolveAppLocale([locale], supported), const Locale('zh'));
      }
      for (final locale in [
        const Locale('zh', 'TW'),
        const Locale('zh', 'HK'),
        const Locale('zh', 'MO'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
          countryCode: 'CN',
        ),
      ]) {
        expect(resolveAppLocale([locale], supported), const Locale('en'));
        expect(
          resolveAppLocale([locale, const Locale('de')], supported),
          const Locale('de'),
        );
      }
    },
  );

  test('all languages have complete messages and preserve placeholders', () {
    final template =
        jsonDecode(File('lib/shared/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final keys = template.keys.where((key) => !key.startsWith('@')).toSet();
    final placeholder = RegExp(r'\{(\w+)\}');
    Set<String> placeholders(String text) =>
        placeholder.allMatches(text).map((match) => match[1]!).toSet();
    for (final locale in supported) {
      final messages =
          jsonDecode(
                File(
                  'lib/shared/l10n/app_${locale.languageCode}.arb',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(
        messages.keys.where((key) => !key.startsWith('@')).toSet(),
        keys,
        reason: '${locale.languageCode} message coverage',
      );
      for (final key in keys) {
        expect((messages[key] as String).trim(), isNotEmpty);
        expect(
          placeholders(messages[key] as String),
          placeholders(template[key] as String),
          reason: '$locale: $key',
        );
      }
    }
  });

  testWidgets('MaterialApp resolves device locales and responds to changes', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [
      const Locale('sv', 'SE'),
      const Locale('en'),
    ];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: supported,
        localeListResolutionCallback: resolveAppLocale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => Text(AppLocalizations.of(context)!.settings),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Inställningar'), findsOneWidget);
    tester.binding.platformDispatcher.localesTestValue = [const Locale('pt')];
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
  });
}

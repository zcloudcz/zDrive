import 'package:flutter/widgets.dart';

/// Selects the first supported browser/OS language, with English as fallback.
Locale resolveAppLocale(
  List<Locale>? preferredLocales,
  Iterable<Locale> supportedLocales,
) {
  for (final preferred in preferredLocales ?? const <Locale>[]) {
    if (preferred.languageCode == 'zh') {
      // Our Chinese translation is simplified. An explicit script overrides
      // the region; TW/HK/MO imply traditional Chinese when no script is given.
      final script = preferred.scriptCode;
      if ((script != null && script != 'Hans') ||
          (script == null &&
              const ['TW', 'HK', 'MO'].contains(preferred.countryCode))) {
        continue;
      }
    }
    for (final supported in supportedLocales) {
      if (supported.languageCode == preferred.languageCode) return supported;
    }
  }
  return const Locale('en');
}

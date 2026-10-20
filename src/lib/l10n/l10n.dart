import 'package:flutter/widgets.dart';

import 'app_localizations.dart';
import 'ui_messages.dart';
export 'app_localizations.dart';

const supportedUiLocales = <Locale>[
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  Locale('en'),
  Locale('ja'),
];

/// Explicit script wins over region. Unsupported system languages fall back to English.
Locale resolveUiLocale(List<Locale>? locales) {
  for (final locale in locales ?? const <Locale>[]) {
    if (locale.languageCode == 'zh') {
      final traditional =
          locale.scriptCode == 'Hant' ||
          (locale.scriptCode != 'Hans' &&
              const {'TW', 'HK', 'MO'}.contains(locale.countryCode));
      return supportedUiLocales[traditional ? 1 : 0];
    }
    if (locale.languageCode == 'en') return const Locale('en');
    if (locale.languageCode == 'ja') return const Locale('ja');
  }
  return const Locale('en');
}

Locale? uiLocaleFromSetting(String value) => switch (value) {
  'zh-Hans' => supportedUiLocales[0],
  'zh-Hant' => supportedUiLocales[1],
  'en' => const Locale('en'),
  'ja' => const Locale('ja'),
  _ => null,
};

String localizedText(
  Locale locale,
  String zhHans,
  String zhHant,
  String en,
  String ja,
) => switch (resolveUiLocale([locale])) {
  Locale(languageCode: 'zh', scriptCode: 'Hant') => zhHant,
  Locale(languageCode: 'zh') => zhHans,
  Locale(languageCode: 'ja') => ja,
  _ => en,
};

extension UiLocalization on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      lookupAppLocalizations(
        resolveUiLocale([
          Localizations.maybeLocaleOf(this) ?? const Locale('en'),
        ]),
      );
  String ui(String message) => localizedUiMessage(this, message);
  String tr(String zhHans, String zhHant, String en, String ja) =>
      localizedText(
        Localizations.maybeLocaleOf(this) ?? const Locale('en'),
        zhHans,
        zhHant,
        en,
        ja,
      );
}

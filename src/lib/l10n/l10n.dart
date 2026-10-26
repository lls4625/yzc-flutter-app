import 'package:flutter/widgets.dart';

import 'app_localizations.dart';
import 'inline_ko_messages.dart';
import 'ui_messages.dart';
export 'app_localizations.dart';

const supportedUiLocales = <Locale>[
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  Locale('ja'),
  Locale('ko'),
  Locale('en'),
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
    if (locale.languageCode == 'ja') return const Locale('ja');
    if (locale.languageCode == 'ko') return const Locale('ko');
    if (locale.languageCode == 'en') return const Locale('en');
  }
  return const Locale('en');
}

Locale? uiLocaleFromSetting(String value) => switch (value) {
  'zh-Hans' => supportedUiLocales[0],
  'zh-Hant' => supportedUiLocales[1],
  'ja' => const Locale('ja'),
  'ko' => const Locale('ko'),
  'en' => const Locale('en'),
  _ => null,
};

String localizedText(
  Locale locale,
  String zhHans,
  String zhHant,
  String en,
  String ja, [
  String? ko,
]) => switch (resolveUiLocale([locale])) {
  Locale(languageCode: 'zh', scriptCode: 'Hant') => zhHant,
  Locale(languageCode: 'zh') => zhHans,
  Locale(languageCode: 'ja') => ja,
  Locale(languageCode: 'ko') => ko ?? localizedKoreanInlineText(zhHans, en),
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
  String tr(String zhHans, String zhHant, String en, String ja, [String? ko]) =>
      localizedText(
        Localizations.maybeLocaleOf(this) ?? const Locale('en'),
        zhHans,
        zhHant,
        en,
        ja,
        ko,
      );
}

import 'dart:convert';

/// User preferences and package language identity deliberately have no coupling.
const uiLocaleValues = {'system', 'zh-Hans', 'zh-Hant', 'en', 'ja'};
const learningTargetValues = {'ja', 'en'};
String normalizedUiLocale(Object? value) =>
    uiLocaleValues.contains(value) ? value as String : 'system';
String normalizedLearningTarget(Object? value) =>
    learningTargetValues.contains(value) ? value as String : 'ja';

/// Frozen legacy identities verified against the 2026-10-19 repository catalog
/// and shipped textbook databases. Never infer compatibility from a title/path.
const legacyJapaneseTextbookIds = {
  '894847224435970048',
  '3671170190440280002',
  '1971170190440288258',
  '1971170190440288259',
  '1971170190440288260',
  '1971170190440288261',
  '1971170190440288262',
  '1971170190440288263',
  '894735640166453248',
  '894735640166457344',
  '2671170190440280001',
};

class ContentLanguage {
  const ContentLanguage(this.sourceLanguage, this.explanationLanguage);
  final String sourceLanguage, explanationLanguage;

  /// UI entry guards can show a configuration error without guessing a language.
  static ContentLanguage? tryFromTextbook(Map<String, Object?> row) {
    try {
      return ContentLanguage.fromTextbook(row);
    } on FormatException {
      return null;
    }
  }

  factory ContentLanguage.fromTextbook(Map<String, Object?> row) {
    final legacy = legacyJapaneseTextbookIds.contains(row['id']);
    String field(String key, Set<String> allowed, String fallback) {
      final raw = row[key];
      if (raw == null || (raw is String && raw.trim().isEmpty)) {
        if (legacy) return fallback;
        throw FormatException('Missing package language: $key');
      }
      if (raw is! String || !allowed.contains(raw)) {
        throw FormatException('Invalid package language: $key');
      }
      return raw;
    }

    return ContentLanguage(
      field('source_language', learningTargetValues, 'ja'),
      field('explanation_language', {
        'zh-Hans',
        'zh-Hant',
        'en',
        'ja',
      }, 'zh-Hans'),
    );
  }
  String get ttsLocale => sourceLanguage == 'en' ? 'en-US' : 'ja-JP';
  String get cacheKey => '$sourceLanguage:$explanationLanguage';
  Map<String, Object?> get columns => {
    'source_language': sourceLanguage,
    'explanation_language': explanationLanguage,
  };
  void requireSame(ContentLanguage other) {
    if (cacheKey != other.cacheKey) {
      throw const FormatException('Package language identity mismatch');
    }
  }
}

/// Preserve whitespace and punctuation as tokens so joining is lossless;
/// apostrophes and hyphens internal to words remain inside the word token.
List<String> englishContentTokens(String source) => RegExp(
  r"[A-Za-z0-9]+(?:['’\-][A-Za-z0-9]+)*|\s+|[^A-Za-z0-9\s]",
  unicode: true,
).allMatches(source).map((m) => m.group(0)!).toList();

/// Includes package identity/version so different packages never share a cache.
String contentSessionKey(Map<String, Object?> textbook) => jsonEncode([
  textbook['id'],
  textbook['ver'],
  textbook['sha256'],
  ContentLanguage.fromTextbook(textbook).cacheKey,
]);

/// Japanese legacy markup is removed only for Japanese content. English
/// punctuation, including exclamation marks, is part of the learning material.
String plainContentText(String text, String sourceLanguage) =>
    sourceLanguage == 'ja'
    ? text
          .replaceAllMapped(RegExp(r'!([^!\s()]+)\([^)]*\)'), (m) => m[1]!)
          .replaceAll('!', '')
          .trim()
    : text.trim();

/// Language follows the field, never the UI or selected learning target.
String grammarFieldLanguage(
  ContentLanguage language,
  String field, {
  String type = '',
  String content = '',
}) {
  if (const {
    'definition',
    'example_definition',
    'tip',
    'lookup_meaning',
    'lookup_usage',
  }.contains(field)) {
    return language.explanationLanguage;
  }
  if (field == 'content' || field == 'lookup_match_title') {
    return type == '1' || type == '3' || type == '41' || content.contains('▶∫')
        ? language.sourceLanguage
        : language.explanationLanguage;
  }
  return language.sourceLanguage;
}

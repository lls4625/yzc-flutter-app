import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import 'knowledge_translations.g.dart';
import 'knowledge_translations_ko.g.dart';

/// Lookup is evaluated on every build, not stored in the learning session.
/// Sources remain immutable so Japanese examples, ruby and IDs are preserved.
String knowledgeText(BuildContext context, String source) {
  final locale = resolveUiLocale([
    Localizations.maybeLocaleOf(context) ?? const Locale('en'),
  ]);
  if (locale.languageCode == 'ko') {
    return knowledgeTranslationsKo[source] ?? source;
  }
  final values = knowledgeTranslations[source];
  if (values == null) return source;
  return context.tr(source, values[0], values[1], values[2]);
}

class KnowledgeText extends Text {
  const KnowledgeText(
    super.data, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
  });

  @override
  Widget build(BuildContext context) => Text(
    knowledgeText(context, data!),
    style: style,
    strutStyle: strutStyle,
    textAlign: textAlign,
    textDirection: textDirection,
    locale: locale,
    softWrap: softWrap,
    overflow: overflow,
    textScaler: textScaler,
    maxLines: maxLines,
    semanticsLabel: semanticsLabel == null
        ? null
        : knowledgeText(context, semanticsLabel!),
    textWidthBasis: textWidthBasis,
    textHeightBehavior: textHeightBehavior,
    selectionColor: selectionColor,
  );
}

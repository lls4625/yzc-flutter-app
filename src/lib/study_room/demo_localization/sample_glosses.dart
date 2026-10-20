import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';

/// Auxiliary translations only. Never use for flashcard prompts/answers or TTS.
/// Original assets, provenance, Japanese source, and media references stay intact.
const demoSampleGlosses = <String, List<String>>{
  '2096511198060085248': ['中国人', '中國人', 'Chinese person', '中国の人'],
  '2096511198060085249': ['日本人', '日本人', 'Japanese person', '日本の人'],
  '1973685560434880514': [
    '小李是中国人。',
    '小李是中國人。',
    'Li is Chinese.',
    '李さんは中国の人です。',
  ],
  '1973685560476823554': [
    '森先生不是学生。',
    '森先生不是學生。',
    'Mori is not a student.',
    '森さんは学生ではありません。',
  ],
};

String demoSampleGloss(BuildContext context, Object? id, String original) {
  final text = demoSampleGlosses[id?.toString()];
  return text == null
      ? original
      : context.tr(text[0], text[1], text[2], text[3]);
}

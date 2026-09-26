import 'package:flutter/material.dart';

/// Language comes from the content field where available. Unmarked Han text
/// stays Chinese; kana alone cannot identify the language of adjacent Han.
TextSpan contentTextSpan(String text, {bool japanese = false}) {
  const chineseStyle = TextStyle(
    fontFamily: 'PingFang SC', locale: Locale('zh', 'CN'));
  const japaneseStyle = TextStyle(
    fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'));
  if (japanese) return TextSpan(text: text, style: japaneseStyle);
  final spans = <InlineSpan>[];
  final pattern = RegExp(r'[「『“"][^「」『』“”"\n]*[」』”"]|[\u3040-\u30ff\uff66-\uff9f]+');
  var offset = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > offset) {
      spans.add(TextSpan(text: text.substring(offset, match.start)));
    }
    final part = match.group(0)!;
    spans.add(TextSpan(text: part,
      style: RegExp(r'[\u3040-\u30ff\uff66-\uff9f]').hasMatch(part)
        ? japaneseStyle : chineseStyle));
    offset = match.end;
  }
  if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
  return TextSpan(style: chineseStyle, children: spans);
}

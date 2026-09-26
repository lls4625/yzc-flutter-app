import 'package:flutter/material.dart';
import '../../../glass_ui.dart';
import 'models.dart';

class QuestionView extends StatelessWidget {
  const QuestionView({super.key, required this.question, this.answer,
    this.onAnswer, this.review = false, this.showTranscript = true,
    this.showPrompt = true, this.showOptions = true});
  final Question question;
  final String? answer;
  final ValueChanged<String>? onAnswer;
  final bool review, showTranscript, showPrompt, showOptions;

  @override
  Widget build(BuildContext context) {
    final q = question;
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.8);
    final japaneseStyle = textStyle?.copyWith(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'));
    final material = q.material;
    final scene = material['scene_description'] as String?;
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = dark ? const Color(0xFF252525) : Colors.white;
    final correctColor = dark ? const Color(0xFF81C995) : const Color(0xFF247A46);
    final incorrectColor = dark ? const Color(0xFFFFB4AB) : const Color(0xFFB53D35);
    Widget practiceOption(Json option) {
      final isCorrect = review && option['id'] == q.correct;
      final isIncorrect = review && !isCorrect && option['id'] == answer;
      final isSelected = option['id'] == answer;
      final accent = isCorrect ? correctColor : isIncorrect ? incorrectColor : isSelected ? colors.primary : colors.onSurfaceVariant;
      final emphasized = isCorrect || isIncorrect || isSelected;
      final background = emphasized ? Color.alphaBlend(accent.withValues(alpha: .10), cardColor) : cardColor;
      return Padding(padding: const EdgeInsets.only(bottom: 10), child: StudyButton.outlined(
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: const Size(double.infinity, 56),
          padding: const EdgeInsets.all(16),
          backgroundColor: background,
          disabledBackgroundColor: background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: emphasized ? accent : colors.outlineVariant, width: emphasized ? 1.5 : 1),
        ),
        onPressed: onAnswer == null ? null : () => onAnswer!(option['id'] as String),
        child: Row(children: [
          Container(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: accent.withValues(alpha: .10), borderRadius: BorderRadius.circular(9)),
            child: Text(option['id'].toString(), textAlign: TextAlign.center, style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(option['text'].toString(), style: TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'), color: colors.onSurface, height: 1.5))),
          if (isCorrect || isIncorrect) ...[
            const SizedBox(width: 8),
            Icon(isCorrect ? Icons.check_circle_outline : Icons.cancel_outlined, color: accent, size: 22,
              semanticLabel: isCorrect ? '正确答案' : '所选答案错误'),
          ],
        ]),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(q.presentation['instruction_ja'] as String? ?? '',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'), height: 1.6)),
      const SizedBox(height: 16),
      if (scene != null && scene.isNotEmpty) ...[
        const Text('场景（文字代图）'), SelectableText(scene, style: textStyle),
        const SizedBox(height: 12),
      ],
      for (final block in (material['blocks'] as List? ?? []).cast<Json>()) ...[
        if (block['title'] != null) Text(block['title'].toString(), style: japaneseStyle),
        if (block['text'] != null) SelectableText(block['text'].toString(), style: japaneseStyle),
        if (block['type'] == 'table') SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [for (final c in block['columns'] as List) DataColumn(label: Text('$c', style: japaneseStyle))],
            rows: [for (final row in block['rows'] as List)
              DataRow(cells: [for (final cell in row as List) DataCell(Text('$cell', style: japaneseStyle))])],
          ),
        ),
        const SizedBox(height: 16),
      ],
      if (q.listening && showTranscript) ...[
        const Text('听力文字稿 · 当前资源无录音'),
        const SizedBox(height: 8),
        SelectableText(q.transcript, style: japaneseStyle),
        const SizedBox(height: 20),
      ],
      if (showPrompt || review)
        SelectableText(q.stem, style: japaneseStyle?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 20),
      if (showOptions || review)
        for (final option in q.options) practiceOption(option),
      if (review) Container(
        margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('你的答案：${answer ?? '未答'}　正确答案：${q.correct}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10), SelectableText.rich(_contentTextSpan(q.explanation), style: textStyle),
        ]),
      ),
    ]);
  }
}

/// Language comes from the content field where available. Unmarked Han text
/// stays Chinese; kana alone cannot identify the language of adjacent Han.
TextSpan _contentTextSpan(String text, {bool japanese = false}) {
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

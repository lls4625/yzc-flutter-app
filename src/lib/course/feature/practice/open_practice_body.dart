import 'package:flutter/material.dart';

import '../../../content_typography.dart';

/// Typography for display-only course exercises. Keep the source in one text
/// flow, including its line breaks, tables, numbering and answer blanks.
/// This deliberately does not use the scored-question format parser.
class OpenPracticeBody extends StatelessWidget {
  const OpenPracticeBody(this.text, {super.key});

  final String text;

  static final _heading = RegExp(r'^\s*【[^【】\r\n]+】\s*$');
  static final _kana = RegExp(r'[\u3040-\u30ff\uff66-\uff9f]');
  static final _quotation = RegExp(r'[「『“"][^」』”"\r\n]*[」』”"]');
  static final _instruction = RegExp(
    r'请|根据|中文|日语|读音|填写|选择|写出|回答|补充|说明|提示|参考|正确|'
    r'下列|完成|意思|表达|句型|练习|答案|注意|判断|仿照|找出|口头|纸笔|'
    r'从.+选|每.+次|^\s*(?:例|注释|注)[：:]',
  );

  TextSpan _line(String line) {
    final heading = _heading.hasMatch(line);
    final blank = line.trim().isEmpty;
    // An instruction quoting Japanese stays Chinese; only typography is
    // inferred. No text is removed, relabelled, answered or reordered.
    final prose = line.replaceAll(_quotation, '');
    final japanese =
        !heading && _kana.hasMatch(prose) && !_instruction.hasMatch(prose);
    return TextSpan(
      style: TextStyle(
        fontSize: blank
            ? 10
            : heading
            ? 18
            : japanese
            ? 17
            : 16,
        fontWeight: heading ? FontWeight.w600 : FontWeight.w400,
        height: blank
            ? 1
            : heading
            ? 1.65
            : 1.55,
      ),
      children: [contentTextSpan(line, japanese: japanese)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            _line(lines[i]),
            if (i < lines.length - 1)
              TextSpan(
                text: '\n',
                style: lines[i].trim().isEmpty
                    ? const TextStyle(fontSize: 10, height: 1)
                    : null,
              ),
          ],
        ],
      ),
      style: const TextStyle(fontSize: 16, height: 1.55),
    );
  }
}

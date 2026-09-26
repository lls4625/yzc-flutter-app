import 'package:flutter/material.dart';

Widget keepSpace(bool visible, Widget child) => Visibility(
  visible: visible,
  maintainState: true,
  maintainAnimation: true,
  maintainSize: true,
  child: child,
);

String plainJapanese(String text) => text
    .replaceAllMapped(
      RegExp(r'!([^!\s()]+)\([^)]*\)'),
      (match) => match.group(1)!,
    )
    .replaceAll('!', '')
    .trim();

class ListeningRubyText extends StatelessWidget {
  const ListeningRubyText(
    this.text, {
    required this.ruby,
    this.source = true,
    this.centered = false,
    this.active = false,
    this.fontSize = 19,
    this.color,
    super.key,
  });
  final String text;
  final bool ruby, source, centered, active;
  final double fontSize;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = <Widget>[];
    void add(String surface, String reading) {
      final highlighted = active && surface.trim().isNotEmpty;
      tokens.add(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            keepSpace(
              ruby,
              Text(
                reading.isEmpty ? ' ' : reading,
                style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'),
                  fontSize: 12,
                  height: 1.3,
                  color: Color(0xFF32AA43),
                ),
              ),
            ),
            keepSpace(
              source,
              Text(
                surface,
                style: TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'),
                  fontSize: fontSize,
                  height: 1.5,
                  fontWeight: FontWeight.normal,
                  color: highlighted
                      ? (dark
                            ? const Color(0xFFFFB366)
                            : const Color(0xFFB85C00))
                      : color,
                ),
              ),
            ),
          ],
        ),
      );
    }

    var offset = 0;
    for (final match in RegExp(r'!([^!\s()]+)\(([^)]*)\)').allMatches(text)) {
      for (final rune in text.substring(offset, match.start).runes) {
        add(String.fromCharCode(rune), '');
      }
      add(match.group(1)!, match.group(2)!);
      offset = match.end;
    }
    for (final rune in text.substring(offset).runes) {
      add(String.fromCharCode(rune), '');
    }
    return Wrap(
      alignment: centered ? WrapAlignment.center : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: tokens,
    );
  }
}

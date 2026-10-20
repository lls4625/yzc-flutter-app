import 'content_typography.dart';

import 'package:flutter/material.dart';

import 'ai_question.dart';
import 'glass_ui.dart';

class PracticeQuestionBody extends StatelessWidget {
  const PracticeQuestionBody(
    this.text, {
    super.key,
    this.headingFontSize = 22,
    this.bodyFontSize = 22,
    this.footerFontSize = 22,
    this.secondaryFontSize,
    this.highlightBodySection = false,
    this.sourceLanguage = 'ja',
    this.explanationLanguage = 'zh-Hans',
  });
  final String text;
  final String sourceLanguage, explanationLanguage;
  final double headingFontSize, bodyFontSize, footerFontSize;
  final double? secondaryFontSize;
  final bool highlightBodySection;

  @override
  Widget build(BuildContext context) {
    final body = questionBody(text);
    final headingStyle = TextStyle(fontSize: headingFontSize, height: 1.5);
    final bodyStyle = contentTextStyle(sourceLanguage)
        .copyWith(fontSize: bodyFontSize, height: 1.5);
    final footerStyle = TextStyle(fontSize: footerFontSize, height: 1.5);
    final headingEnd = secondaryFontSize != null && body.parts.isNotEmpty
        ? RegExp(r'^【[^\n]+】\n').firstMatch(body.heading)?.end
        : null;
    final noteStart = secondaryFontSize != null
        ? RegExp(
            r'^[ \t]*(?:注释|注釋|注釈|注|備考|说明|說明|説明|Note|Notes)[：:]',
            multiLine: true,
          ).firstMatch(body.footer)?.start
        : null;
    final bodyText = Text.rich(
      TextSpan(
        children: [for (final part in body.parts) TextSpan(text: part.text)],
      ),
      style: bodyStyle,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (body.heading.isNotEmpty)
          if (headingEnd != null)
            Text.rich(
              TextSpan(
                children: [
                  contentTextSpan(
                    body.heading.substring(0, headingEnd),
                    language: explanationLanguage,
                  ),
                  TextSpan(
                    children: [
                      contentTextSpan(
                        body.heading.substring(headingEnd),
                        language: explanationLanguage,
                      ),
                    ],
                    style: TextStyle(fontSize: secondaryFontSize),
                  ),
                ],
              ),
              style: headingStyle,
            )
          else
            Text.rich(
              contentTextSpan(body.heading, language: explanationLanguage),
              style: headingStyle,
            ),
        if (body.parts.isNotEmpty) ...[
          if (highlightBodySection && body.heading.isNotEmpty)
            StudyDivider(
              height: 24,
              thickness: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            )
          else if (!highlightBodySection)
            const SizedBox(height: 16),
          bodyText,
        ],
        if (body.footer.isNotEmpty) ...[
          if (highlightBodySection &&
              (body.heading.isNotEmpty || body.parts.isNotEmpty))
            StudyDivider(
              height: 24,
              thickness: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            )
          else if (!highlightBodySection)
            const SizedBox(height: 12),
          if (noteStart != null)
            Text.rich(
              TextSpan(
                children: [
                  contentTextSpan(
                    body.footer.substring(0, noteStart),
                    language: explanationLanguage,
                  ),
                  TextSpan(
                    children: [
                      contentTextSpan(
                        body.footer.substring(noteStart),
                        language: explanationLanguage,
                      ),
                    ],
                    style: TextStyle(fontSize: secondaryFontSize),
                  ),
                ],
              ),
              style: footerStyle,
            )
          else
            Text.rich(
              contentTextSpan(body.footer, language: explanationLanguage),
              style: footerStyle,
            ),
        ],
      ],
    );
  }
}

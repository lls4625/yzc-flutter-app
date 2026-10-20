import '../lib/study_room/dictation/feature/controller.dart'
    show dictationPlainText;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/content_language.dart';
import '../lib/study_room/listening/feature/text.dart';
import '../lib/study_room/flashcards/feature/models.dart';

void main() {
  test(
    'dictation snapshot cleanup does not parse English punctuation as ruby',
    () {
      expect(
        dictationPlainText('!Stop(now)', sourceLanguage: 'en'),
        '!Stop(now)',
      );
      expect(dictationPlainText('!日本(にほん)', sourceLanguage: 'ja'), '日本');
    },
  );
  test('grammar source and explanation retain independent punctuation', () {
    const language = ContentLanguage('ja', 'en');
    for (final type in ['2', '4']) {
      expect(
        plainContentText(
          'Say Hello!',
          grammarFieldLanguage(
            language,
            'content',
            type: type,
            content: 'Say Hello!',
          ),
        ),
        'Say Hello!',
      );
    }
    for (final field in [
      'definition',
      'example_definition',
      'tip',
      'lookup_meaning',
    ]) {
      expect(
        plainContentText('Say Hello!', grammarFieldLanguage(language, field)),
        'Say Hello!',
      );
    }
    expect(
      plainContentText('!日本(にほん)', grammarFieldLanguage(language, 'example')),
      '日本',
    );
  });
  test('English punctuation is content, not Japanese markup', () {
    expect(plainContentText("Don't stop!", 'en'), "Don't stop!");
    expect(plainContentText('!日本(にほん)へ！', 'ja'), '日本へ！');
  });
  testWidgets(
    'English listening uses a single natural text flow at large text scale',
    (tester) async {
      const source = "Don't stop! A well-known traveller's plan takes time.";
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: const SizedBox(
              width: 280,
              child: ListeningRubyText(
                source,
                sourceLanguage: 'en',
                ruby: true,
              ),
            ),
          ),
        ),
      );
      expect(find.text(source), findsOneWidget);
      expect(find.byType(Wrap), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('ja'),
          home: ListeningRubyText(source, sourceLanguage: 'en', ruby: true),
        ),
      );
      expect(find.text(source), findsOneWidget);
    },
  );
  testWidgets('Japanese listening retains ruby segments', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ListeningRubyText('!日本(にほん)へ', sourceLanguage: 'ja', ruby: true),
      ),
    );
    expect(find.text('日本'), findsOneWidget);
    expect(find.text('にほん'), findsOneWidget);
    expect(find.byType(Wrap), findsOneWidget);
  });
  test('Flashcard snapshots retain legacy keys and actual language independent of UI', () {
    const word = FlashWord(
      bookId: '9007199254740993123',
      lessonId: 'lesson',
      id: '9007199254740993124',
      japanese: 'Hello!',
      kana: '',
      chinese: '你好！',
      pos: '',
      source: 'English · 1',
      sourceLanguage: 'en',
      explanationLanguage: 'zh-Hant',
    );
    final copy = FlashWord.fromJson(Map<String, dynamic>.from(word.toJson()));
    expect(copy.japanese, 'Hello!');
    expect(copy.sourceLanguage, 'en');
    expect(copy.explanationLanguage, 'zh-Hant');
    expect(copy.id, word.id);
    expect(copy.toJson().containsKey('japanese'), isTrue);
    expect(copy.toJson().containsKey('chinese'), isTrue);
  });
  test('Only known historical flashcard snapshots use Japanese defaults', () {
    final old = <String, dynamic>{
      'book': legacyJapaneseTextbookIds.first,
      'lesson': 'lesson',
      'id': 'word',
      'japanese': '日本',
      'kana': 'にほん',
      'chinese': '日本',
      'pos': '',
      'source': 'legacy',
    };
    expect(FlashWord.fromJson(old).sourceLanguage, 'ja');
    expect(
      () => FlashWord.fromJson({...old, 'book': 'unknown'}),
      throwsFormatException,
    );
  });
}

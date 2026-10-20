import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/basic_knowledge/feature/basic_knowledge.dart';
import '../lib/basic_knowledge/feature/knowledge_localization.dart';
import '../lib/content_copyright_page.dart';
import '../lib/glass_ui.dart';
import '../lib/l10n/l10n.dart';
import '../lib/legal_document_page.dart';
import '../lib/privacy_policy_page.dart';

class LocaleHost extends StatefulWidget {
  const LocaleHost({super.key, required this.child});
  final Widget child;
  @override
  State<LocaleHost> createState() => LocaleHostState();
}

class LocaleHostState extends State<LocaleHost> {
  Locale locale = supportedUiLocales.first;
  void select(Locale value) => setState(() => locale = value);
  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: locale,
    supportedLocales: supportedUiLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    builder: (context, child) => studyGlassRoot(child!),
    home: widget.child,
  );
}

void main() {
  test('locale selects script before region, with English fallback', () {
    expect(legalLocaleTag(const Locale('zh', 'TW')), 'zh-Hant');
    expect(
      legalLocaleTag(
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
          countryCode: 'HK',
        ),
      ),
      'zh-Hans',
    );
    expect(legalLocaleTag(const Locale('fr')), 'en');
  });
  test(
    'English categories are independent and retain Japanese kana routes',
    () {
      final japanese = basicKnowledgeCategoriesFor('ja');
      final english = basicKnowledgeCategoriesFor('en');
      expect(japanese, hasLength(5));
      expect(english, hasLength(5));
      expect(
        japanese.expand((c) => c.topics).any((t) => t.id == 'kana'),
        isTrue,
      );
      expect(english.every((c) => c.id.startsWith('en.')), isTrue);
      expect(
        english.expand((c) => c.topics).every((t) => t.id.startsWith('en.')),
        isTrue,
      );
      expect(
        english
            .expand((c) => c.topics)
            .expand((t) => t.sections)
            .expand((s) => s.items),
        hasLength(54),
      );
      expect(identical(japanese, basicKnowledgeCategories), isTrue);
    },
  );
  for (final entry in <String, Widget>{
    'privacy_policy': const PrivacyPolicyPage(),
    'content_copyright': const ContentCopyrightPage(),
  }.entries) {
    testWidgets(
      '${entry.key} reloads full offline body while same page stays open',
      (tester) async {
        final key = GlobalKey<LocaleHostState>();
        await tester.pumpWidget(LocaleHost(key: key, child: entry.value));
        for (final locale in supportedUiLocales) {
          key.currentState!.select(locale);
          await tester.pumpAndSettle();
          final actual = tester
              .widget<SelectableText>(find.byType(SelectableText))
              .data!;
          final expected = File(
            'assets/legal/${entry.key}.${legalLocaleTag(locale)}.txt',
          ).readAsStringSync();
          expect(actual, expected);
          expect(find.byType(LegalDocumentPage), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
  testWidgets(
    'same English topic updates explanations and leaves source examples unchanged',
    (tester) async {
      final key = GlobalKey<LocaleHostState>();
      final topic = basicKnowledgeCategoriesFor('en').first.topics.first;
      await tester.pumpWidget(
        LocaleHost(
          key: key,
          child: BasicKnowledgeTopicPage(topic: topic),
        ),
      );
      for (final locale in supportedUiLocales) {
        key.currentState!.select(locale);
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(BasicKnowledgeTopicPage));
        expect(find.text(knowledgeText(context, topic.title)), findsWidgets);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w.runtimeType == Text &&
                (w as Text).data!.contains('cat /kæt/'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'Japanese explanations localize without changing Japanese examples',
    (tester) async {
      final key = GlobalKey<LocaleHostState>();
      const text =
          '日语以「あ・い・う・え・お」五个元音为基础。发音时口形和音质要保持稳定，不要像汉语复韵母那样在一个元音内明显滑动。例如「え」从开始到结束都保持同一音色。';
      await tester.pumpWidget(
        LocaleHost(
          key: key,
          child: const Scaffold(body: KnowledgeText(text)),
        ),
      );
      final values = <String>[];
      for (final locale in supportedUiLocales) {
        key.currentState!.select(locale);
        await tester.pumpAndSettle();
        final rendered = tester
            .widgetList<Text>(find.byType(Text))
            .single
            .data!;
        values.add(rendered);
        expect(rendered, contains('あ・い・う・え・お'));
      }
      expect(values.toSet(), hasLength(4));
    },
  );
  testWidgets(
    'five categories remain readable in four locales and two targets at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final target in ['ja', 'en']) {
        for (final category in basicKnowledgeCategoriesFor(target)) {
          final key = GlobalKey<LocaleHostState>();
          await tester.pumpWidget(
            LocaleHost(
              key: key,
              child: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: BasicKnowledgeCategoryPage(
                    category: category,
                    learningTarget: target,
                    onOpenKana: () {},
                  ),
                ),
              ),
            ),
          );
          for (final locale in supportedUiLocales) {
            key.currentState!.select(locale);
            await tester.pumpAndSettle();
            final context = tester.element(
              find.byType(BasicKnowledgeCategoryPage),
            );
            expect(find.text(category.localizedTitle(context)), findsWidgets);
            expect(
              tester.takeException(),
              isNull,
              reason: '$target / ${category.id} / $locale',
            );
          }
        }
      }
    },
  );

  testWidgets(
    'ruby learning objects never pass through UI lookup a second time',
    (tester) async {
      const topic = BasicKnowledgeTopic(
        id: 'ruby-regression',
        title: 'Ruby regression',
        subtitle: '',
        icon: Icons.book,
        sections: [
          BasicKnowledgeSection('Examples', [
            BasicKnowledgeItem(
              'Objects',
              '!祖父(そふ) !祖母(そぼ) !手(て) !黄色(きいろ) !三角形(さんかくけい) !正方形(せいほうけい) !立方体(りっぽうたい) !居酒屋(いざかや)',
            ),
          ]),
        ],
      );
      final key = GlobalKey<LocaleHostState>();
      await tester.pumpWidget(
        LocaleHost(
          key: key,
          child: const BasicKnowledgeTopicPage(topic: topic),
        ),
      );
      for (final locale in supportedUiLocales) {
        key.currentState!.select(locale);
        await tester.pumpAndSettle();
        for (final source in [
          '祖父',
          '祖母',
          '手',
          '黄色',
          '三角形',
          '正方形',
          '立方体',
          '居酒屋',
          'そふ',
          'そぼ',
          'て',
          'きいろ',
          'さんかくけい',
          'せいほうけい',
          'りっぽうたい',
          'いざかや',
        ]) {
          expect(
            find.byWidgetPredicate(
              (w) => w.runtimeType == Text && (w as Text).data == source,
            ),
            findsOneWidget,
            reason: '$locale / $source',
          );
        }
      }
    },
  );
  testWidgets('grammar highlights translate individually before joining', (
    tester,
  ) async {
    final topic = basicKnowledgeCategoriesFor('ja')
        .expand((c) => c.topics)
        .firstWhere((t) => t.id == 'noun_sentences');
    final key = GlobalKey<LocaleHostState>();
    await tester.pumpWidget(
      LocaleHost(
        key: key,
        child: BasicKnowledgeTopicPage(topic: topic),
      ),
    );
    key.currentState!.select(const Locale('en'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(BasicKnowledgeTopicPage));
    final expected = [
      '非过去',
      '过去',
      '普通体与礼貌体',
    ].map((s) => knowledgeText(context, s)).join('  ·  ');
    expect(expected, isNot('非过去  ·  过去  ·  普通体与礼貌体'));
    expect(find.text(expected), findsWidgets);
  });
}

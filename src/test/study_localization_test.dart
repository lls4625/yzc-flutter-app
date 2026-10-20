import '../lib/study_room/jlpt_practice/feature/models.dart' as formal;
import '../lib/study_room/jlpt_practice/feature/question_view.dart'
    as formal_view;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/glass_ui.dart';
import '../lib/l10n/l10n.dart';
import '../lib/study_room/access/purchase.dart';
import '../lib/study_room/access/purchase_messages.dart';
import '../lib/study_room/access/purchase_section.dart';
import '../lib/study_room/demo_localization/explanations.dart';
import '../lib/study_room/demo_localization/ui.dart';
import '../lib/study_room/jlpt_practice/demo/samples.dart' as practice;
import '../lib/study_room/jlpt_test/demo/samples.dart' as exam;
import '../lib/study_room/jlpt_test/demo/models.dart' as exam_models;
import '../lib/study_room/jlpt_practice/demo/question_view.dart'
    as practice_view;
import '../lib/study_room/jlpt_test/demo/question_view.dart' as exam_view;

class _Purchase extends StudyRoomPurchaseController {
  bool owned = false;
  bool ready = true;
  bool processing = false;
  String? status;
  String? productPrice = 'US\$9.99';
  bool platformSupported = true;
  bool productLoading = false;
  @override
  bool get unlocked => owned;
  @override
  bool get initialized => ready;
  @override
  bool get busy => processing;
  @override
  bool get supported => platformSupported;
  @override
  bool get canPurchase => ready && !owned && !processing;
  @override
  String? get price => productPrice;
  @override
  bool get loadingProduct => productLoading;
  @override
  String? get message => status;
}

Widget _app(Locale locale, Widget child) => MaterialApp(
  locale: locale,
  supportedLocales: supportedUiLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  builder: (_, child) => studyGlassRoot(child!),
  home: child,
);

void main() {
  test('all 11 demo explanations have four complete stable-ID overlays', () {
    final p = practice.demoBank();
    final e = exam.demoBank();
    expect(p.byType.values.expand((q) => q).length, 8);
    expect(
      e.papers
          .expand(
            (paper) => (paper['questions'] as List)
                .cast<exam_models.Json>()
                .map(exam_models.Question.new),
          )
          .length,
      3,
    );
    for (final q in p.byType.values.expand((q) => q)) {
      expect(demoExplanations['practice:${q.id}:1'], hasLength(4));
      expect(
        demoExplanations['practice:${q.id}:1']!.every((v) => v.isNotEmpty),
        isTrue,
      );
    }
    for (final q in e.papers.expand(
      (paper) => (paper['questions'] as List).cast<exam_models.Json>().map(
        exam_models.Question.new,
      ),
    )) {
      expect(demoExplanations['test:${q.id}:1'], hasLength(4));
      expect(
        demoExplanations['test:${q.id}:1']!.every((v) => v.isNotEmpty),
        isTrue,
      );
    }
  });

  testWidgets(
    'all 11 question views switch explanation without changing source or answer',
    (tester) async {
      final p = practice.demoBank();
      final e = exam.demoBank();
      final beforeP = jsonEncode(p.data);
      final beforeE = jsonEncode(e.data);
      for (final locale in supportedUiLocales) {
        for (final q in p.byType.values.expand((q) => q)) {
          await tester.pumpWidget(
            _app(
              locale,
              Scaffold(
                body: SingleChildScrollView(
                  child: practice_view.QuestionView(
                    question: q,
                    answer: q.correct,
                    review: true,
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.text(q.stem), findsOneWidget);
          expect(
            find.text(q.presentation['instruction_ja'] as String),
            findsOneWidget,
          );
          final index = locale.languageCode == 'ja'
              ? 3
              : locale.languageCode == 'en'
              ? 2
              : locale.scriptCode == 'Hant'
              ? 1
              : 0;
          expect(
            find.text(
              demoExplanations['practice:${q.id}:1']![index],
              findRichText: true,
            ),
            findsOneWidget,
          );
        }
        for (final q in e.papers.expand(
          (paper) => (paper['questions'] as List).cast<exam_models.Json>().map(
            exam_models.Question.new,
          ),
        )) {
          await tester.pumpWidget(
            _app(
              locale,
              Scaffold(
                body: SingleChildScrollView(
                  child: exam_view.QuestionView(
                    question: q,
                    answer: q.correct,
                    review: true,
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.text(q.stem), findsOneWidget);
        }
      }
      expect(jsonEncode(p.data), beforeP);
      expect(jsonEncode(e.data), beforeE);
    },
  );

  testWidgets(
    'purchase notice precedes controls in every locale, target and state',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p = _Purchase();
      addTearDown(p.dispose);
      const headings = ['内容范围说明', '內容範圍說明', 'Content availability', '提供内容について'];
      const statuses = <String?>[
        null,
        'pending',
        'cancelled',
        'restore_empty',
        'restore',
        'verification',
        'purchase',
        'product',
        'unsupported',
      ];
      for (var i = 0; i < supportedUiLocales.length; i++) {
        for (final target in ['ja', 'en']) {
          for (final owned in [false, true]) {
            p.owned = owned;
            for (final status in statuses) {
              p.status = status;
              await tester.pumpWidget(
                _app(
                  supportedUiLocales[i],
                  StudyRoomPurchasePage(p, learningTarget: () => target),
                ),
              );
              await tester.pump();
              expect(find.text(headings[i]), findsOneWidget);
              final context = tester.element(
                find.byType(StudyRoomPurchasePage),
              );
              if (status != null)
                expect(
                  find.text(purchaseMessage(context, status)),
                  findsOneWidget,
                );
              if (!owned) {
                final button = find.textContaining('US\$9.99');
                expect(button, findsOneWidget);
                expect(
                  tester.getTopLeft(find.text(headings[i])).dy,
                  lessThan(tester.getTopLeft(button).dy),
                );
              }
            }
          }
        }
      }
    },
  );

  testWidgets(
    'purchase disclosure remains usable on small screens with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p = _Purchase();
      addTearDown(p.dispose);
      for (final locale in supportedUiLocales) {
        await tester.pumpWidget(
          _app(
            locale,
            MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                textScaler: TextScaler.linear(2),
              ),
              child: StudyRoomPurchasePage(p, learningTarget: () => 'en'),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.textContaining('US\$9.99'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'notice survives loading, no price and unsupported payment with large text',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p = _Purchase();
      addTearDown(p.dispose);
      for (final ready in [false, true]) {
        for (final supported in [false, true]) {
          p.ready = ready;
          p.platformSupported = supported;
          p.productPrice = null;
          p.productLoading = !ready;
          await tester.pumpWidget(
            _app(
              const Locale('en'),
              MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: StudyRoomPurchasePage(p, learningTarget: () => 'en'),
              ),
            ),
          );
          await tester.pump();
          expect(find.text('Content availability'), findsOneWidget);
          expect(
            find.textContaining('English practice or test question banks.'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'formal content is never replaced by demo overlays or UI labels',
    (tester) async {
      final originals =
          practice
              .demoBank()
              .byType
              .values
              .expand((q) => q)
              .map((q) => q.data)
              .toList()
            ..addAll(
              exam.demoBank().papers.expand(
                (paper) =>
                    (paper['questions'] as List).cast<Map<String, dynamic>>(),
              ),
            );
      for (final locale in supportedUiLocales) {
        for (final original in originals) {
          final data = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
          data['explanation_json'] = {'summary': '单词'};
          data['stem_json'] = {'text': '全部'};
          final before = jsonEncode(data);
          await tester.pumpWidget(
            _app(
              locale,
              Scaffold(
                body: SingleChildScrollView(
                  child: formal_view.QuestionView(
                    question: formal.Question(data),
                    review: true,
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.text('全部'), findsOneWidget);
          expect(find.text('单词', findRichText: true), findsOneWidget);
          expect(jsonEncode(data), before);
        }
      }
    },
  );

  testWidgets(
    'UI display lookup does not mutate canonical keys or generic tool names',
    (tester) async {
      String canonical = '错题与未答';
      await tester.pumpWidget(
        _app(
          const Locale('en'),
          Builder(builder: (context) => Text(studyUi(context, canonical))),
        ),
      );
      expect(find.text('Incorrect and unanswered'), findsOneWidget);
      expect(canonical, '错题与未答');
      final context = tester.element(find.byType(Builder).last);
      expect(studyUi(context, '磨耳朵'), 'Listening');
      expect(studyUi(context, '课程排序'), 'Lesson order');
      expect(
        studyUi(context, '第 2 题 · 本部分已答 1/3'),
        'Question 2 · Answered in this part 1/3',
      );
      expect(studyUi(context, '学校'), '学校');
    },
  );
}

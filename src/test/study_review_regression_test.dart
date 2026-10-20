import '../lib/study_room/listening/demo/controller.dart' as listening_demo;
import '../lib/study_room/dictation/demo/page.dart' as dictation_demo;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/glass_ui.dart';
import '../lib/l10n/l10n.dart';
import '../lib/study_room/host_contracts.dart';
import '../lib/study_room/access/access.dart';
import '../lib/study_room/home/page.dart';
import '../lib/study_room/demo_localization/ui.dart';
import '../lib/study_room/jlpt_practice/feature/models.dart' as practice;
import '../lib/study_room/jlpt_practice/feature/question_view.dart'
    as practice_view;
import '../lib/study_room/jlpt_test/feature/models.dart' as exam;
import '../lib/study_room/jlpt_test/feature/question_view.dart' as exam_view;

class _Host implements StudyRoomHost {
  _Host(this.learningTarget);
  @override
  final String learningTarget;
  @override
  final ChangeNotifier changes = ChangeNotifier();
  @override
  bool Function() get isUnlocked =>
      () => false;
  @override
  bool Function() get isPurchaseSaving =>
      () => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Locale locale, Widget child) => MaterialApp(
  locale: locale,
  supportedLocales: supportedUiLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: MediaQuery(
    data: const MediaQueryData(
      size: Size(320, 640),
      textScaler: TextScaler.linear(2),
    ),
    child: studyGlassRoot(child),
  ),
);

void main() {
  testWidgets(
    'four UI languages and both home targets fit 320x640 at 2x text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final target in ['ja', 'en']) {
        final host = _Host(target);
        for (final locale in supportedUiLocales) {
          await tester.pumpWidget(
            _app(locale, StudyRoomPage(host, StudyRoomAccess(host))),
          );
          await tester.pump();
          expect(
            find.text(target == 'en' ? 'Every Step Counts' : '為せば成る'),
            findsOneWidget,
          );
          expect(
            find.text(target == 'en' ? 'One small step today.' : '今日も、一歩'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        host.changes.dispose();
      }
    },
  );

  testWidgets(
    'formal answer choices that collide with UI labels remain original',
    (tester) async {
      final data = <String, dynamic>{
        'id': 'source-collision',
        'type_code': 'L_TASK',
        'stem_json': {'text': '开始练习'},
        'material_json': {
          'scene_description': '播放',
          'transcript': '返回',
          'blocks': [
            {'title': '取消', 'text': '下一题'},
          ],
        },
        'presentation_json': {
          'instruction_ja': '重新开始',
          'options_channel': 'written_text',
        },
        'options_json': [
          {'id': '1', 'text': '全部'},
          {'id': '2', 'text': '单词'},
          {'id': '3', 'text': '正确'},
        ],
        'answer_json': {
          'correct_option_ids': ['单词'],
        },
        'explanation_json': {'summary': '全部'},
      };
      for (final locale in supportedUiLocales) {
        for (final view in <Widget>[
          practice_view.QuestionView(
            question: practice.Question(data),
            answer: '正确',
            review: true,
          ),
          exam_view.QuestionView(
            question: exam.Question(data),
            answer: '正确',
            review: true,
          ),
        ]) {
          await tester.pumpWidget(
            _app(locale, Scaffold(body: SingleChildScrollView(child: view))),
          );
          await tester.pump();
          for (final source in [
            '单词',
            '正确',
            '开始练习',
            '播放',
            '返回',
            '取消',
            '下一题',
            '重新开始',
          ]) {
            expect(find.text(source), findsOneWidget);
          }
          expect(find.text('全部', findRichText: true), findsNWidgets(2));
          final answerRows = tester
              .widgetList<Text>(find.byType(Text))
              .map((widget) => widget.data ?? '')
              .where((text) => text.contains('正确') && text.contains('单词'));
          expect(answerRows.length, 1);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'cached error labels are translated at display time in every locale',
    (tester) async {
      const messages = <String>[
        "下载地址配置异常",
        "内容暂不可下载",
        "内容暂不可用",
        "内容正在处理，请稍后再试",
        "内容语言信息无效，请更新资源或联系维护者",
        "原课程已不在当前内容中",
        "听写准备或播放失败，请重试",
        "听写演示音频不可用",
        "处理超时，请重试",
        "存储空间不足",
        "存储空间不足，请释放空间后重试",
        "学习资源配置异常",
        "已取消",
        "当前内容语言的朗读声音不可用，请检查系统语音设置",
        "操作失败，请重试",
        "数据格式异常",
        "文件读写失败，请检查可用存储空间后重试",
        "暂无到期复习题",
        "暂无可播放的音频",
        "暂无错题",
        "暂时无法检查存储空间，请重试",
        "服务器请求失败",
        "本地数据处理失败",
        "本课可用题目不足",
        "演示数据处理失败，请重新播放。",
        "演示音频不可用",
        "磨耳朵音频准备失败",
        "练习记录暂不可用",
        "网络连接失败",
        "解压失败",
        "请先提交错题答案",
        "课程校验失败，请重新读取",
        "课程读取失败",
        "资源包与目录版本不一致，请刷新目录后重试",
        "资源包配置异常",
        "资源目录与其他教材冲突，原教材已保留，请联系内容维护者",
        "音频播放失败",
        "音频资源缺失",
        "题库已更新，请重新打开课程",
      ];
      for (final message in messages) {
        for (final locale in supportedUiLocales) {
          await tester.pumpWidget(
            _app(
              locale,
              Builder(
                builder: (context) => SingleChildScrollView(
                  child: Text(
                    studyUi(context, message),
                    key: const Key('error'),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          final text = tester
              .widget<Text>(find.byKey(const Key('error')))
              .data!;
          expect(text, isNotEmpty);
          if (locale.languageCode == 'en') {
            expect(
              text,
              isNot(message),
              reason: 'Untranslated cached error: $message',
            );
          }
        }
      }
    },
  );
  testWidgets(
    'open demo error snackbars retranslate without retrying the action',
    (tester) async {
      for (final perform in [
        listening_demo.demoPerform,
        dictation_demo.perform,
      ]) {
        var calls = 0;
        final page = Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => perform(context, () async {
                calls++;
                throw StateError('演示音频不可用');
              }),
              child: const Text('Trigger error'),
            ),
          ),
        );
        await tester.pumpWidget(_app(const Locale('en'), page));
        await tester.tap(find.text('Trigger error'));
        await tester.pumpAndSettle();
        expect(find.text('Demo audio unavailable'), findsOneWidget);
        await tester.pumpWidget(
          _app(
            const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
            page,
          ),
        );
        await tester.pump();
        expect(find.text('演示音訊不可用'), findsOneWidget);
        expect(calls, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/glass_ui.dart';
import '../lib/l10n/l10n.dart';
import '../lib/study_room/demo_guide_l10n.dart';
import '../lib/study_room/dictation/demo/page.dart' as dictation;
import '../lib/study_room/flashcards/demo/controller.dart' as flash;
import '../lib/study_room/flashcards/demo/guide.dart' as flash;
import '../lib/study_room/jlpt_practice/demo/guide.dart' as practice;
import '../lib/study_room/jlpt_practice/demo/page.dart' as practice;
import '../lib/study_room/jlpt_test/demo/guide.dart' as test_demo;
import '../lib/study_room/jlpt_test/demo/page.dart' as test_demo;
import '../lib/study_room/listening/demo/controller.dart' as listening;
import '../lib/study_room/listening/demo/guide.dart' as listening;

class _LocaleHost extends StatefulWidget {
  const _LocaleHost({required this.child, super.key});
  final Widget child;

  @override
  State<_LocaleHost> createState() => _LocaleHostState();
}

class _LocaleHostState extends State<_LocaleHost> {
  Locale locale = const Locale('en');

  void select(Locale next) => setState(() => locale = next);

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: supportedUiLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: studyGlassRoot(child!),
    ),
    home: widget.child,
  );
}

// Only the owned audio/data boundary is replaced. The real guide, overlay,
// lifecycle, localized strings, buttons, and step transitions run in the widget.
class _ListeningController extends listening.ListeningDemoController {
  _ListeningController() {
    ready = true;
    selectAllAction = () => selections++;
  }
  int resets = 0;
  int selections = 0;

  @override
  Future<void> resetDemo() async {
    resets++;
  }

  @override
  Future<void> stop() async {}
}

class _FlashController extends flash.FlashDemoController {
  _FlashController() {
    lessons = [
      {'id': 'demo-lesson'},
    ];
  }
  int resets = 0;

  @override
  Future<void> resetDemo() async {
    resets++;
  }

  @override
  Future<void> stopDemoPronunciation() async {}
}

Widget _targets(List<GlobalKey> keys) => SingleChildScrollView(
  child: Column(
    children: [
      for (final key in keys)
        SizedBox(key: key, width: 180, height: 44, child: const Text('Sample')),
    ],
  ),
);

Finder _header(int count, String title) => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      (widget.data?.startsWith('2/$count · ') ?? false) &&
      (widget.data?.contains(title) ?? false),
);

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 100 && !ready(); frame++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(
    ready(),
    isTrue,
    reason: 'The real guide did not reach the expected state',
  );
}

Future<void> _press(WidgetTester tester, String label) async {
  final button = find.ancestor(
    of: find.text(label),
    matching: find.byType(StudyButton),
  );
  await _until(
    tester,
    () =>
        button.evaluate().isNotEmpty &&
        tester.widget<StudyButton>(button.first).onPressed != null,
  );
  await tester.ensureVisible(button.first);
  await tester.tap(button.first);
  await tester.pump();
}

Future<void> _switchLocales(
  WidgetTester tester,
  GlobalKey<_LocaleHostState> host,
  Type guideType,
  int stepCount,
  List<String> titles,
) async {
  final state = tester.state(find.byType(guideType));
  for (var i = 0; i < supportedUiLocales.length; i++) {
    host.currentState!.select(supportedUiLocales[i]);
    await _until(
      tester,
      () => _header(stepCount, titles[i]).evaluate().isNotEmpty,
    );
    // Let the replacement highlight mount, then check that no restart or
    // automatic advance took place while translating the paused guide.
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(_header(stepCount, titles[i]), findsOneWidget);
    expect(tester.state(find.byType(guideType)), same(state));
    expect(tester.takeException(), isNull);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory scratch;

  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('demo-guide-locale-test-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => scratch.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('yuzhichu/lesson_playback'),
      (call) async => <String, Object?>{},
    );
    await initializeStudyGlass();
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('yuzhichu/lesson_playback'),
      null,
    );
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  testWidgets(
    'listening guide changes locale without resetting step or settings',
    (tester) async {
      final controller = _ListeningController();
      final targets = listening.ListeningDemoTargets();
      final host = GlobalKey<_LocaleHostState>();
      await tester.pumpWidget(
        _LocaleHost(
          key: host,
          child: listening.ListeningDemoGuide(
            controller: controller,
            targets: targets,
            automatic: false,
            child: _targets([
              targets.selection,
              targets.order,
              targets.start,
              targets.speed,
              targets.repeat,
              targets.interval,
              targets.playback,
            ]),
          ),
        ),
      );
      await _press(tester, 'Next step');
      await _until(
        tester,
        () => _header(7, 'Change the playback order').evaluate().isNotEmpty,
      );
      await controller.setting('playback_speed', 8);
      await _switchLocales(tester, host, listening.ListeningDemoGuide, 7, [
        '调整播放顺序',
        '調整播放順序',
        'Change the playback order',
        '再生順を変える',
      ]);
      expect(controller.resets, 1);
      expect(controller.selections, 1);
      expect(controller.speed, .8);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      controller.dispose();
    },
  );

  testWidgets('flashcard guide changes locale without resetting the round', (
    tester,
  ) async {
    final controller = _FlashController();
    final targets = flash.FlashDemoTargets();
    final host = GlobalKey<_LocaleHostState>();
    await tester.pumpWidget(
      _LocaleHost(
        key: host,
        child: flash.FlashDemoGuide(
          controller: controller,
          targets: targets,
          child: _targets([
            targets.lesson,
            targets.start,
            targets.card,
            targets.flip,
            targets.known,
            targets.weak,
            targets.next,
            targets.result,
            targets.retry,
          ]),
        ),
      ),
    );
    await _press(tester, 'Next step');
    await _until(
      tester,
      () => _header(11, 'Start a flashcard round').evaluate().isNotEmpty,
    );
    controller.onlyWeak = true;
    await _switchLocales(tester, host, flash.FlashDemoGuide, 11, [
      '开始一轮闪卡',
      '開始一輪閃卡',
      'Start a flashcard round',
      'フラッシュカードを始める',
    ]);
    expect(controller.resets, 1);
    expect(controller.onlyWeak, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    controller.dispose();
  });

  testWidgets(
    'dictation guide preserves its selection controller and rule on locale change',
    (tester) async {
      final host = GlobalKey<_LocaleHostState>();
      await tester.pumpWidget(
        _LocaleHost(key: host, child: const dictation.DictationDemoPage()),
      );
      // Bundled audio extraction performs real filesystem work, outside fake time.
      await tester.runAsync(() async {
        for (var retry = 0; retry < 100; retry++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump(const Duration(milliseconds: 30));
          if (find.text('Next step').evaluate().isNotEmpty) break;
        }
      });
      await _press(tester, 'Next step');
      await _until(
        tester,
        () => _header(12, 'Change the lesson order').evaluate().isNotEmpty,
      );
      final controller = tester
          .widget<dictation.DictationDemoSelectionPage>(
            find.byType(dictation.DictationDemoSelectionPage),
          )
          .controller;
      await controller.setting('interval', 7);
      await _switchLocales(tester, host, dictation.DictationDemoPage, 12, [
        '调整课程顺序',
        '調整課程順序',
        'Change the lesson order',
        '課の順序を変える',
      ]);
      expect(
        tester
            .widget<dictation.DictationDemoSelectionPage>(
              find.byType(dictation.DictationDemoSelectionPage),
            )
            .controller,
        same(controller),
      );
      expect(controller.interval, 7);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );

  testWidgets(
    'JLPT practice guide preserves repository and step when locale changes',
    (tester) async {
      final host = GlobalKey<_LocaleHostState>();
      await tester.pumpWidget(
        _LocaleHost(key: host, child: const practice.JlptDemoGuide()),
      );
      await _press(tester, 'Pause');
      await _press(tester, 'Next step');
      await _until(
        tester,
        () => _header(9, 'Start practice').evaluate().isNotEmpty,
      );
      final controller = tester
          .widget<practice.JlptPracticePage>(
            find.byType(practice.JlptPracticePage),
          )
          .controller;
      await controller.repository.saveLevel('N4');
      await _switchLocales(tester, host, practice.JlptDemoGuide, 9, [
        '开始练习',
        '開始練習',
        'Start practice',
        '練習を始める',
      ]);
      expect(
        tester
            .widget<practice.JlptPracticePage>(
              find.byType(practice.JlptPracticePage),
            )
            .controller,
        same(controller),
      );
      expect(await controller.repository.loadLevel(), 'N4');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );

  testWidgets(
    'JLPT test guide preserves repository and step when locale changes',
    (tester) async {
      final host = GlobalKey<_LocaleHostState>();
      await tester.pumpWidget(
        _LocaleHost(key: host, child: const test_demo.JlptDemoGuide()),
      );
      await _press(tester, 'Pause');
      await _press(tester, 'Next step');
      await _until(
        tester,
        () => _header(13, 'Start the test').evaluate().isNotEmpty,
      );
      final controller = tester
          .widget<test_demo.JlptTestPage>(find.byType(test_demo.JlptTestPage))
          .controller;
      await controller.repository.saveLevel('N4');
      await _switchLocales(tester, host, test_demo.JlptDemoGuide, 13, [
        '开始测试',
        '開始測試',
        'Start the test',
        'テストを始める',
      ]);
      expect(
        tester
            .widget<test_demo.JlptTestPage>(find.byType(test_demo.JlptTestPage))
            .controller,
        same(controller),
      );
      expect(await controller.repository.loadLevel(), 'N4');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );

  testWidgets('a stored guide failure is translated again in the new locale', (
    tester,
  ) async {
    final host = GlobalKey<_LocaleHostState>();
    await tester.pumpWidget(
      _LocaleHost(
        key: host,
        child: Builder(
          builder: (context) => Text(demoGuideError(context, '演示恢复失败，请重新播放。')),
        ),
      ),
    );
    expect(
      find.text('Could not resume the tour. Replay it to continue.'),
      findsOneWidget,
    );
    host.currentState!.select(const Locale('ja'));
    await tester.pumpAndSettle();
    expect(find.text('ガイドを再開できませんでした。再生し直してください。'), findsOneWidget);
    expect(
      find.text('Could not resume the tour. Replay it to continue.'),
      findsNothing,
    );
  });
}

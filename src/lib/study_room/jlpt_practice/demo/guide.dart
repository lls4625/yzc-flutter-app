import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../../glass_ui.dart';
import '../../../l10n/l10n.dart';
import '../../demo_guide_l10n.dart';
import '../../../system_errors.dart';
import 'controller.dart';
import 'page.dart';

class JlptDemoGuide extends StatefulWidget {
  const JlptDemoGuide({super.key});
  @override
  State<JlptDemoGuide> createState() => _JlptDemoGuideState();
}

class _JlptDemoGuideState extends State<JlptDemoGuide>
    with WidgetsBindingObserver {
  JlptDemoController c = JlptDemoController();
  GlobalKey<OverlayState> _overlay = GlobalKey<OverlayState>();
  late OverlayEntry _page;
  TutorialCoachMark? _coach;
  Timer? _timer;
  int _step = 0, _revision = 0;
  bool _guided = true, _paused = false, _working = false, _foreground = true;
  bool _reduced = false;
  String? _error;

  List<String> get _titles => [
    context.tr('选择题型', '選擇題型', 'Choose a question type', '問題形式を選ぶ'),
    context.tr('开始练习', '開始練習', 'Start practice', '練習を始める'),
    context.tr('准备作答', '準備作答', 'Get ready to answer', '回答の準備をする'),
    context.tr('选择答案', '選擇答案', 'Choose an answer', '答えを選ぶ'),
    context.tr('查看解析', '查看解析', 'View the explanation', '解説を見る'),
    context.tr('下一题', '下一題', 'Next question', '次の問題'),
    context.tr('继续作答', '繼續作答', 'Continue answering', '回答を続ける'),
    context.tr('提交练习', '提交練習', 'Submit practice', '練習を提出する'),
    context.tr('查看结果', '查看結果', 'View results', '結果を見る'),
  ];
  List<String> get _texts => [
    context.tr(
      '先用内置 N5 汉字读音两道样例，走一遍练习主流程。',
      '先用內建 N5 漢字讀音兩道範例，走一遍練習主要流程。',
      'Try the practice flow with two built-in N5 kanji-reading questions.',
      '内蔵のN5漢字の読み方のサンプル2問で、練習の流れを体験します。',
    ),
    context.tr(
      '点击右上角开始。正式练习可选择等级、题型和题数。',
      '點選右上角開始。正式練習可選擇級別、題型和題數。',
      'Tap start at the top right. Regular practice lets you choose a level, question type, and number of questions.',
      '右上から開始します。通常の練習では、レベル、問題形式、問題数を選べます。',
    ),
    context.tr(
      '准备好后开始计时，进入答题页。',
      '準備好後開始計時，進入答題頁。',
      'When you are ready, start the timer and open the questions.',
      '準備ができたら計測を開始し、回答画面に進みます。',
    ),
    context.tr(
      '先示范选择一个答案。作答后可以继续下一题，也可以核对解析。',
      '先示範選擇一個答案。作答後可以繼續下一題，也可以核對解析。',
      'First, choose an answer. You can then move to the next question or check the explanation.',
      'まず回答の選択を実演します。回答後は次の問題に進むことも、解説を確認することもできます。',
    ),
    context.tr(
      '查看正确答案与解析。看过解析的题目会标记为辅助作答。',
      '查看正確答案與解析。看過解析的題目會標記為輔助作答。',
      'View the correct answer and explanation. Questions whose explanations you view are marked as assisted.',
      '正解と解説を確認します。解説を見た問題には、補助ありの回答として印が付きます。',
    ),
    context.tr(
      '点击下一题，继续第二个样例。',
      '點選下一題，繼續第二個範例。',
      'Tap next question to try the second sample.',
      '「次の問題」で2問目のサンプルに進みます。',
    ),
    context.tr(
      '为第二道题选择答案，完成这一轮练习。',
      '為第二道題選擇答案，完成這一輪練習。',
      'Answer the second question to complete this round.',
      '2問目の答えを選んで、この練習を終えます。',
    ),
    context.tr(
      '提交这一轮练习，保存后查看结果。自己试用时还可体验交卷确认。',
      '提交這一輪練習，儲存後查看結果。自行試用時還可體驗交卷確認。',
      'Submit this round and view the results after it is saved. Free exploration also includes the submission confirmation.',
      'この練習を提出し、保存後に結果を確認します。自由に試すときは、提出の確認画面も体験できます。',
    ),
    context.tr(
      '结果展示正确率及辅助作答提示。演示完成后，可以展开解析或返回自己试试。',
      '結果顯示正確率及輔助作答提示。示範完成後，可以展開解析或返回自行試用。',
      'Results show your accuracy and any assisted answers. After the tour, expand explanations or return to try it yourself.',
      '結果には正答率と補助ありの回答が表示されます。ガイド終了後は解説を開いたり、戻って自由に試したりできます。',
    ),
  ];

  GlobalKey get _target => switch (_step) {
    0 => c.selection,
    1 => c.startTarget,
    2 => c.readyTarget,
    8 => c.resultTarget,
    _ => c.questionTarget,
  };

  OverlayEntry _makePage() => OverlayEntry(
    builder: (_) => ExcludeSemantics(
      excluding: _guided,
      child: AbsorbPointer(
        absorbing: _guided,
        child: Navigator(
          key: c.navigator,
          onGenerateRoute: (_) =>
              MaterialPageRoute<void>(builder: (_) => JlptPracticePage(c)),
        ),
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _page = _makePage();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _armTimer();
      unawaited(_focus());
    });
  }

  Locale? _guideLocale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    final localeChanged = _guideLocale != null && _guideLocale != locale;
    _guideLocale = locale;
    if (localeChanged) {
      // Rebuild translated content and its highlight, preserving tour state.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // The coach package starts its animation on a deferred timer. Let that
        // initialization finish before disposing and replacing its overlay.
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
        _page.markNeedsBuild();
        if (_guided && _foreground && _error == null) {
          unawaited(_focus());
        }
      });
    }
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    _reduced = reduced;
  }

  void _removeFocus() {
    removeDemoGuideOverlay(_coach);
    _coach = null;
  }

  void _armTimer() {
    _timer?.cancel();
    if (!mounted || !_guided || _paused || !_foreground || _error != null)
      return;
    _timer = Timer(
      const Duration(milliseconds: 3000),
      () => unawaited(_advance()),
    );
  }

  void _resumeGuide() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (!_foreground) return;
    setState(() {
      _paused = false;
      _error = null;
    });
    if (_step >= 3 && _step <= 7) c.resume?.call();
    _armTimer();
    unawaited(_focus());
  }

  Future<void> _focus() async {
    final revision = ++_revision;
    try {
      await _showFocus(revision).timeout(const Duration(seconds: 2));
    } on TimeoutException catch (error, stack) {
      if (!mounted || revision != _revision) return;
      ++_revision;
      _removeFocus();
      SystemErrors.record(
        error,
        stack,
        module: 'jlpt_practice_demo',
        operation: '演示高亮等待超时',
      );
    }
  }

  Future<void> _showFocus(int revision) async {
    _removeFocus();
    bool valid() => mounted && _guided && _foreground && revision == _revision;
    try {
      // Wait for a route transition or the in-memory sample load to mount its target.
      for (var retry = 0; retry < 30 && valid(); retry++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        final target = _target.currentContext;
        if (target != null) {
          final animation = ModalRoute.of(target)?.animation;
          if (animation == null ||
              animation.status == AnimationStatus.completed)
            break;
        }
      }
      if (!valid()) return;
      final target = _target.currentContext;
      if (target == null) throw StateError('演示位置暂不可用');
      final animation = ModalRoute.of(target)?.animation;
      if (animation != null && animation.status != AnimationStatus.completed) {
        throw StateError('演示页面仍在切换');
      }
      await Scrollable.ensureVisible(
        target,
        alignment: .5,
        duration: _reduced ? Duration.zero : const Duration(milliseconds: 250),
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!valid()) return;
      final overlay = _overlay.currentState;
      final box = target.findRenderObject();
      final parent = overlay?.context.findRenderObject();
      if (overlay == null ||
          box is! RenderBox ||
          parent is! RenderBox ||
          !box.hasSize) {
        throw StateError('演示位置尚未完成布局');
      }
      final coach = TutorialCoachMark(
        targets: [
          TargetFocus(
            targetPosition: TargetPosition(
              box.size,
              box.localToGlobal(Offset.zero, ancestor: parent),
            ),
            shape: ShapeLightFocus.RRect,
            radius: 18,
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 3,
            ),
            enableTargetTab: false,
            enableOverlayTab: false,
            contents: [],
          ),
        ],
        hideSkip: true,
        useSafeArea: false,
        opacityShadow: .62,
        paddingFocus: 4,
        pulseEnable: !_reduced && !_paused,
        focusAnimationDuration: Duration(milliseconds: _reduced ? 1 : 250),
        backgroundSemanticLabel: context.tr(
          'J练习演示高亮区域',
          'J練習示範反白區域',
          'JLPT practice demo highlighted area',
          'JLPT練習デモの強調領域',
        ),
      );
      _coach = coach;
      coach.showWithOverlayState(overlay: overlay);
      await Future<void>.delayed(Duration.zero);
      if (!valid() || _coach != coach) {
        removeDemoGuideOverlay(coach);
        return;
      }
    } catch (error, stack) {
      if (valid()) {
        _removeFocus();
        SystemErrors.record(
          error,
          stack,
          module: 'jlpt_practice_demo',
          operation: '演示高亮定位',
        );
      }
    }
  }

  Future<void> _advance() async {
    if (!_guided || _working || !_foreground) return;
    _timer?.cancel();
    ++_revision;
    _removeFocus();
    setState(() => _working = true);
    try {
      switch (_step) {
        case 1:
          c.start?.call();
          break;
        case 2:
          c.resume?.call();
          break;
        case 3:
          c.answerWrong?.call();
          break;
        case 4:
          c.reveal?.call();
          break;
        case 5:
          c.next?.call();
          break;
        case 6:
          c.answerCorrect?.call();
          break;
        case 7:
          await c.submit?.call();
          break;
        case 8:
          _explore();
          return;
        default:
          break;
      }
      if (!mounted) return;
      setState(() => _step++);
      await _focus();
    } catch (_) {
      if (mounted)
        setState(() {
          _error = '演示暂时中断，请重新播放或自己试试。';
          _paused = true;
        });
    } finally {
      if (mounted) {
        setState(() => _working = false);
        _armTimer();
      }
    }
  }

  void _pause() {
    _timer?.cancel();
    ++_revision;
    _removeFocus();
    if (mounted) setState(() => _paused = true);
  }

  void _explore() {
    _timer?.cancel();
    ++_revision;
    _removeFocus();
    setState(() {
      _guided = false;
      _working = false;
    });
    _page.markNeedsBuild();
  }

  void _restart() {
    _timer?.cancel();
    ++_revision;
    _removeFocus();
    final old = _page;
    old.remove();
    setState(() {
      c = JlptDemoController();
      _overlay = GlobalKey<OverlayState>();
      _guided = true;
      _paused = false;
      _working = false;
      _step = 0;
      _error = null;
      _page = _makePage();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
      if (mounted) {
        _armTimer();
        unawaited(_focus());
      }
    });
  }

  @override
  void didChangeMetrics() {
    if (!_guided || !_foreground) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _guided && _foreground) unawaited(_focus());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground)
      _pause();
    else if (_guided && !_paused) {
      _armTimer();
      unawaited(_focus());
    }
  }

  @override
  void dispose() {
    ++_revision;
    _timer?.cancel();
    _removeFocus();
    WidgetsBinding.instance.removeObserver(this);
    _page.remove();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: LayoutBuilder(
      builder: (context, bounds) => Column(
        children: [
          Expanded(
            child: Overlay(key: _overlay, initialEntries: [_page]),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: bounds.maxHeight * .42),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: StudyCard(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            !_guided
                                ? context.tr(
                                    '自由试用 · 内置样例',
                                    '自由試用 · 內建範例',
                                    'Explore · Built-in samples',
                                    '自由体験 · 内蔵サンプル',
                                  )
                                : '${_step + 1}/${_titles.length} · ${_titles[_step]}${_paused ? context.tr(' · 已暂停', ' · 已暫停', ' · Paused', ' · 一時停止中') : ''}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          !_guided
                              ? context.tr(
                                  '可以自由练习、看解析及重做错题。退出演示后记录清空。',
                                  '可以自由練習、看解析及重做錯題。退出示範後紀錄清空。',
                                  'Practice freely, view explanations, and retry mistakes. Records are cleared when you leave the demo.',
                                  '自由に練習し、解説を見たり、間違えた問題をやり直したりできます。デモを終了すると記録は消去されます。',
                                )
                              : _error != null
                              ? demoGuideError(context, _error!)
                              : _texts[_step],
                        ),
                        const SizedBox(height: 10),
                        if (_guided)
                          StudyLinearProgressIndicator(
                            value: (_step + 1) / _titles.length,
                          ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_guided && _error == null) ...[
                              StudyButton.filled(
                                onPressed: _working
                                    ? null
                                    : () {
                                        if (_paused) {
                                          _resumeGuide();
                                        } else {
                                          _pause();
                                          unawaited(_focus());
                                        }
                                      },
                                child: Text(
                                  _paused
                                      ? context.tr('继续', '繼續', 'Resume', '再開')
                                      : context.tr('暂停', '暫停', 'Pause', '一時停止'),
                                ),
                              ),
                              if (_paused)
                                StudyButton.text(
                                  onPressed: _working ? null : _advance,
                                  child: Text(
                                    context.tr(
                                      '下一步',
                                      '下一步',
                                      'Next step',
                                      '次のステップ',
                                    ),
                                  ),
                                ),
                            ],
                            if (!_guided || _error != null)
                              StudyButton.filled(
                                onPressed: _working ? null : _restart,
                                child: Text(
                                  context.tr(
                                    '重新播放',
                                    '重新播放',
                                    'Replay tour',
                                    'ガイドを再生し直す',
                                  ),
                                ),
                              ),
                            if (_guided)
                              StudyButton.text(
                                onPressed: _working ? null : _explore,
                                child: Text(
                                  context.tr(
                                    '跳过 · 自己试试',
                                    '略過 · 自己試試',
                                    'Skip · Try it yourself',
                                    'スキップ · 自由に試す',
                                  ),
                                ),
                              ),
                            StudyButton.text(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(
                                context.tr(
                                  '退出演示',
                                  '退出示範',
                                  'Exit demo',
                                  'デモを終了',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

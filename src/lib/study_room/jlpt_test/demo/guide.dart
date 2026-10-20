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
    context.tr('选择模拟卷', '選擇模擬卷', 'Choose a mock test', '模擬試験を選ぶ'),
    context.tr('开始测试', '開始測試', 'Start the test', 'テストを始める'),
    context.tr('前部准备', '前部準備', 'Prepare for part 1', '前半の準備'),
    context.tr('前部作答', '前部作答', 'Answer part 1', '前半に回答する'),
    context.tr('完成前部', '完成前部', 'Finish part 1', '前半を終える'),
    context.tr('中部准备', '中部準備', 'Prepare for part 2', '中盤の準備'),
    context.tr('中部作答', '中部作答', 'Answer part 2', '中盤に回答する'),
    context.tr('完成中部', '完成中部', 'Finish part 2', '中盤を終える'),
    context.tr('后部准备', '後部準備', 'Prepare for part 3', '後半の準備'),
    context.tr('听力文字稿', '聽力文字稿', 'Listening transcript', '聴解のスクリプト'),
    context.tr('后部作答', '後部作答', 'Answer part 3', '後半に回答する'),
    context.tr('交卷', '交卷', 'Submit the test', '答案を提出する'),
    context.tr('查看结果', '查看結果', 'View results', '結果を見る'),
  ];
  List<String> get _texts => [
    context.tr(
      '用内置 N5 三题演示卷走一遍测试主流程，每部分一道题。不是完整考试试卷。',
      '用內建 N5 三題示範卷走一遍測試主要流程，每部分一道題。這不是完整的考試試卷。',
      'Try the test flow with a built-in three-question N5 demo, one question per part. This is not a full exam.',
      '各パート1問、全3問の内蔵N5デモでテストの流れを体験します。完全な試験問題ではありません。',
    ),
    context.tr(
      '点击右上角开始测试，依次完成前、中、后三部分。',
      '點選右上角開始測試，依序完成前、中、後三部分。',
      'Start at the top right, then complete parts 1, 2, and 3 in order.',
      '右上からテストを開始し、前半、中盤、後半の3パートを順番に進めます。',
    ),
    context.tr(
      '先进入前部准备页，点击开始后才计时。',
      '先進入前部準備頁，點選開始後才計時。',
      'The part 1 preparation screen appears first. Timing starts only when you tap start.',
      '最初に前半の準備画面が表示されます。開始を押すまで時間は計測されません。',
    ),
    context.tr(
      '选择第一道词汇题的答案。测试交卷前不展示解析。',
      '選擇第一道詞彙題的答案。測試交卷前不顯示解析。',
      'Choose an answer for the first vocabulary question. Explanations stay hidden until you submit the test.',
      '最初の語彙問題の答えを選びます。解説は答案を提出するまで表示されません。',
    ),
    context.tr(
      '完成本部分，进入下一部分准备页，计时暂停。',
      '完成本部分，進入下一部分準備頁，計時暫停。',
      'Finish this part and open the next preparation screen. The timer pauses.',
      'このパートを終え、次の準備画面に進みます。時間計測は一時停止します。',
    ),
    context.tr(
      '中部为语法与阅读，这里用一道语法题示范。',
      '中部為文法與閱讀，這裡用一道文法題示範。',
      'Part 2 covers grammar and reading. This demo uses one grammar question.',
      '中盤は文法と読解です。ここでは文法問題を1問使って紹介します。',
    ),
    context.tr(
      '这次示范选错一道题，交卷后再查看解析。',
      '這次示範選錯一道題，交卷後再查看解析。',
      'This time, choose an incorrect answer. Review its explanation after submitting.',
      '今回は間違った答えを選ぶ例です。提出後に解説を確認します。',
    ),
    context.tr(
      '完成中部，进入听力准备页。',
      '完成中部，進入聽力準備頁。',
      'Finish part 2 and open the listening preparation screen.',
      '中盤を終えて、聴解の準備画面に進みます。',
    ),
    context.tr(
      '后部为听力适配。开始后可用合成朗读或文字稿作答。',
      '後部為聽力適配。開始後可用合成朗讀或文字稿作答。',
      'Part 3 is adapted for listening practice. After starting, use synthesized speech or the transcript to answer.',
      '後半は聴解用に調整した問題です。開始後、合成音声またはスクリプトを使って回答できます。',
    ),
    context.tr(
      '本次自动演示打开文字稿，不自动播放声音，并记录文字稿辅助。',
      '本次自動示範會開啟文字稿，不自動播放聲音，並記錄文字稿輔助。',
      'This automatic tour opens the transcript without playing audio and records transcript assistance.',
      'この自動ガイドでは音声を自動再生せず、スクリプトを開きます。スクリプトの補助を利用したことが記録されます。',
    ),
    context.tr(
      '根据对话选择答案，完成最后一题。',
      '根據對話選擇答案，完成最後一題。',
      'Choose an answer based on the dialogue to finish the last question.',
      '会話をもとに答えを選び、最後の問題を終えます。',
    ),
    context.tr(
      '提交演示卷，保存成功后显示结果。自由试用时会显示交卷确认和未答提醒。',
      '提交示範卷，儲存成功後顯示結果。自由試用時會顯示交卷確認和未答提醒。',
      'Submit the demo test. Results appear after it is saved. Free exploration includes submission confirmation and unanswered-question reminders.',
      'デモの答案を提出すると、保存後に結果が表示されます。自由体験では提出の確認や未回答のお知らせも表示されます。',
    ),
    context.tr(
      '查看正确率、分项表现和解析。可以自己展开回顾，也可以返回重新试用。',
      '查看正確率、分項表現和解析。可以自行展開回顧，也可以返回重新試用。',
      'Review accuracy, performance by section, and explanations. Expand items to review them, or go back and try again.',
      '正答率、パート別の成績、解説を確認します。項目を開いて振り返ったり、戻ってもう一度試したりできます。',
    ),
  ];

  GlobalKey get _target => switch (_step) {
    0 => c.selection,
    1 => c.startTarget,
    2 || 5 || 8 => c.readyTarget,
    12 => c.resultTarget,
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
              MaterialPageRoute<void>(builder: (_) => JlptTestPage(c)),
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
    if (const [3, 4, 6, 7, 9, 10, 11].contains(_step)) c.resume?.call();
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
        module: 'jlpt_test_demo',
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
          'J测试演示高亮区域',
          'J測試示範反白區域',
          'JLPT test demo highlighted area',
          'JLPTテストデモの強調領域',
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
          module: 'jlpt_test_demo',
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
        case 5:
        case 8:
          c.resume?.call();
          break;
        case 3:
        case 10:
          c.answerCorrect?.call();
          break;
        case 4:
        case 7:
          await c.nextPhase?.call();
          break;
        case 6:
          c.answerWrong?.call();
          break;
        case 9:
          c.showTranscript?.call();
          break;
        case 11:
          await c.submit?.call();
          break;
        case 12:
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
                                  '可以自由测试、交卷后查看解析。退出演示后记录清空。',
                                  '可以自由測試、交卷後查看解析。退出示範後紀錄清空。',
                                  'Try a test freely and view explanations after submitting. Records are cleared when you leave the demo.',
                                  '自由にテストを試し、提出後に解説を確認できます。デモを終了すると記録は消去されます。',
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

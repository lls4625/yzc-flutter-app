import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../../../glass_ui.dart';
import '../../../system_errors.dart';
import 'controller.dart';
import 'page.dart';

class JlptDemoGuide extends StatefulWidget {
  const JlptDemoGuide({super.key});
  @override
  State<JlptDemoGuide> createState() => _JlptDemoGuideState();
}

class _JlptDemoGuideState extends State<JlptDemoGuide> with WidgetsBindingObserver {
  JlptDemoController c = JlptDemoController();
  GlobalKey<OverlayState> _overlay = GlobalKey<OverlayState>();
  late OverlayEntry _page;
  TutorialCoachMark? _coach;
  Timer? _timer;
  int _step = 0, _revision = 0;
  bool _guided = true, _paused = false, _working = false, _foreground = true;
  bool _reduced = false;
  String? _error;

  static const _titles = ['选择模拟卷', '开始测试', '前部准备', '前部作答', '完成前部',
    '中部准备', '中部作答', '完成中部', '后部准备', '听力文字稿', '后部作答', '交卷', '查看结果'];
  static const _texts = [
    '用内置 N5 三题演示卷走一遍测试主流程，每部分一道题。不是完整考试试卷。',
    '点击右上角开始测试，依次完成前、中、后三部分。',
    '先进入前部准备页，点击开始后才计时。',
    '选择第一道词汇题的答案。测试交卷前不展示解析。',
    '完成本部分，进入下一部分准备页，计时暂停。',
    '中部为语法与阅读，这里用一道语法题示范。',
    '这次示范选错一道题，交卷后再查看解析。',
    '完成中部，进入听力准备页。',
    '后部为听力适配。开始后可用合成朗读或文字稿作答。',
    '本次自动演示打开文字稿，不自动播放声音，并记录文字稿辅助。',
    '根据对话选择答案，完成最后一题。',
    '提交演示卷，保存成功后显示结果。自由试用时会显示交卷确认和未答提醒。',
    '查看正确率、分项表现和解析。可以自己展开回顾，也可以返回重新试用。',
  ];

  GlobalKey get _target => switch (_step) {
    0 => c.selection, 1 => c.startTarget,
    2 || 5 || 8 => c.readyTarget, 12 => c.resultTarget, _ => c.questionTarget,
  };

  OverlayEntry _makePage() => OverlayEntry(builder: (_) => ExcludeSemantics(
    excluding: _guided,
    child: AbsorbPointer(absorbing: _guided, child: Navigator(
      key: c.navigator,
      onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => JlptTestPage(c)),
    )),
  ));

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context) || MediaQuery.accessibleNavigationOf(context);
    _reduced = reduced;
  }

  void _removeFocus() { _coach?.removeOverlayEntry(); _coach = null; }

  void _armTimer() {
    _timer?.cancel();
    if (!mounted || !_guided || _paused || !_foreground || _error != null) return;
    _timer = Timer(const Duration(milliseconds: 3000), () => unawaited(_advance()));
  }

  void _resumeGuide() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (!_foreground) return;
    setState(() { _paused = false; _error = null; });
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
      SystemErrors.record(error, stack, module: 'jlpt_test_demo', operation: '演示高亮等待超时');
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
          if (animation == null || animation.status == AnimationStatus.completed) break;
        }
      }
      if (!valid()) return;
      final target = _target.currentContext;
      if (target == null) throw StateError('演示位置暂不可用');
      final animation = ModalRoute.of(target)?.animation;
      if (animation != null && animation.status != AnimationStatus.completed) {
        throw StateError('演示页面仍在切换');
      }
      await Scrollable.ensureVisible(target, alignment: .5,
        duration: _reduced ? Duration.zero : const Duration(milliseconds: 250));
      await WidgetsBinding.instance.endOfFrame;
      if (!valid()) return;
      final overlay = _overlay.currentState;
      final box = target.findRenderObject();
      final parent = overlay?.context.findRenderObject();
      if (overlay == null || box is! RenderBox || parent is! RenderBox || !box.hasSize) {
        throw StateError('演示位置尚未完成布局');
      }
      final coach = TutorialCoachMark(
        targets: [TargetFocus(targetPosition: TargetPosition(box.size,
          box.localToGlobal(Offset.zero, ancestor: parent)),
          shape: ShapeLightFocus.RRect, radius: 18,
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 3),
          enableTargetTab: false, enableOverlayTab: false, contents: [])],
        hideSkip: true, useSafeArea: false, opacityShadow: .62, paddingFocus: 4,
        pulseEnable: !_reduced && !_paused,
        focusAnimationDuration: Duration(milliseconds: _reduced ? 1 : 250),
        backgroundSemanticLabel: 'J测试演示高亮区域',
      );
      _coach = coach;
      coach.showWithOverlayState(overlay: overlay);
      await Future<void>.delayed(Duration.zero);
      if (!valid() || _coach != coach) { coach.removeOverlayEntry(); return; }
    } catch (error, stack) {
      if (valid()) {
        _removeFocus();
        SystemErrors.record(error, stack, module: 'jlpt_test_demo', operation: '演示高亮定位');
      }
    }
  }

  Future<void> _advance() async {
    if (!_guided || _working || !_foreground) return;
    _timer?.cancel(); ++_revision; _removeFocus();
    setState(() => _working = true);
    try {
      switch (_step) {
        case 1: c.start?.call(); break;
        case 2: case 5: case 8: c.resume?.call(); break;
        case 3: case 10: c.answerCorrect?.call(); break;
        case 4: case 7: await c.nextPhase?.call(); break;
        case 6: c.answerWrong?.call(); break;
        case 9: c.showTranscript?.call(); break;
        case 11: await c.submit?.call(); break;
        case 12: _explore(); return;
        default: break;
      }
      if (!mounted) return;
      setState(() => _step++);
      await _focus();
    } catch (_) {
      if (mounted) setState(() { _error = '演示暂时中断，请重新播放或自己试试。'; _paused = true; });
    } finally {
      if (mounted) {
        setState(() => _working = false);
        _armTimer();
      }
    }
  }

  void _pause() {
    _timer?.cancel(); ++_revision; _removeFocus();
    if (mounted) setState(() => _paused = true);
  }

  void _explore() {
    _timer?.cancel(); ++_revision; _removeFocus();
    setState(() { _guided = false; _working = false; });
    _page.markNeedsBuild();
  }

  void _restart() {
    _timer?.cancel(); ++_revision; _removeFocus();
    final old = _page;
    old.remove();
    setState(() {
      c = JlptDemoController(); _overlay = GlobalKey<OverlayState>();
      _guided = true; _paused = false; _working = false; _step = 0; _error = null;
      _page = _makePage();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
      if (mounted) { _armTimer(); unawaited(_focus()); }
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
    if (!_foreground) _pause();
    else if (_guided && !_paused) { _armTimer(); unawaited(_focus()); }
  }
  @override
  void dispose() {
    ++_revision; _timer?.cancel(); _removeFocus();
    WidgetsBinding.instance.removeObserver(this);
    _page.remove();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: LayoutBuilder(builder: (context, bounds) => Column(children: [
      Expanded(child: Overlay(key: _overlay, initialEntries: [_page])),
      ConstrainedBox(constraints: BoxConstraints(maxHeight: bounds.maxHeight * .42),
        child: SafeArea(top: false, child: SingleChildScrollView(padding: const EdgeInsets.all(12),
          child: StudyCard(child: Padding(padding: const EdgeInsets.all(14), child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Semantics(liveRegion: true, child: Text(!_guided ? '自由试用 · 内置样例'
                : '${_step + 1}/${_titles.length} · ${_titles[_step]}${_paused ? ' · 已暂停' : ''}',
                style: Theme.of(context).textTheme.titleSmall)),
              const SizedBox(height: 8),
              Text(!_guided ? '可以自由测试、交卷后查看解析。退出演示后记录清空。'
                : _error ?? _texts[_step]),
              const SizedBox(height: 10),
              if (_guided) StudyLinearProgressIndicator(value: (_step + 1) / _titles.length),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (_guided && _error == null) ...[
                  StudyButton.filled(onPressed: _working ? null : () {
                    if (_paused) { _resumeGuide(); }
                    else { _pause(); unawaited(_focus()); }
                  }, child: Text(_paused ? '继续' : '暂停')),
                  if (_paused) StudyButton.text(onPressed: _working ? null : _advance, child: const Text('下一步')),
                ],
                if (!_guided || _error != null)
                  StudyButton.filled(onPressed: _working ? null : _restart, child: const Text('重新播放')),
                if (_guided) StudyButton.text(onPressed: _working ? null : _explore, child: const Text('跳过 · 自己试试')),
                StudyButton.text(onPressed: () => Navigator.of(context).pop(), child: const Text('退出演示')),
              ]),
            ],
          )))))),
    ])),
  );
}

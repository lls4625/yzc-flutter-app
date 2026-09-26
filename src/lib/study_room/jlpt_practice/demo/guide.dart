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

  static const _titles = ['选择题型', '开始练习', '准备作答', '选择答案', '查看解析',
    '下一题', '继续作答', '提交练习', '查看结果'];
  static const _texts = [
    '先用内置 N5 汉字读音两道样例，走一遍练习主流程。',
    '点击右上角开始。正式练习可选择等级、题型和题数。',
    '准备好后开始计时，进入答题页。',
    '先示范选择一个答案。作答后可以继续下一题，也可以核对解析。',
    '查看正确答案与解析。看过解析的题目会标记为辅助作答。',
    '点击下一题，继续第二个样例。',
    '为第二道题选择答案，完成这一轮练习。',
    '提交这一轮练习，保存后查看结果。自己试用时还可体验交卷确认。',
    '结果展示正确率及辅助作答提示。演示完成后，可以展开解析或返回自己试试。',
  ];

  GlobalKey get _target => switch (_step) {
    0 => c.selection, 1 => c.startTarget, 2 => c.readyTarget,
    8 => c.resultTarget, _ => c.questionTarget,
  };

  OverlayEntry _makePage() => OverlayEntry(builder: (_) => ExcludeSemantics(
    excluding: _guided,
    child: AbsorbPointer(absorbing: _guided, child: Navigator(
      key: c.navigator,
      onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => JlptPracticePage(c)),
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
      SystemErrors.record(error, stack, module: 'jlpt_practice_demo', operation: '演示高亮等待超时');
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
        backgroundSemanticLabel: 'J练习演示高亮区域',
      );
      _coach = coach;
      coach.showWithOverlayState(overlay: overlay);
      await Future<void>.delayed(Duration.zero);
      if (!valid() || _coach != coach) { coach.removeOverlayEntry(); return; }
    } catch (error, stack) {
      if (valid()) {
        _removeFocus();
        SystemErrors.record(error, stack, module: 'jlpt_practice_demo', operation: '演示高亮定位');
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
        case 2: c.resume?.call(); break;
        case 3: c.answerWrong?.call(); break;
        case 4: c.reveal?.call(); break;
        case 5: c.next?.call(); break;
        case 6: c.answerCorrect?.call(); break;
        case 7: await c.submit?.call(); break;
        case 8:
          _explore();
          return;
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
              Text(!_guided ? '可以自由练习、看解析及重做错题。退出演示后记录清空。'
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

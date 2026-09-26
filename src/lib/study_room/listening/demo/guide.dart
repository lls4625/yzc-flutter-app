import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../../glass_ui.dart';
import 'controller.dart';
import 'models.dart';

class ListeningDemoTargets {
  final selection = GlobalKey();
  final order = GlobalKey();
  final start = GlobalKey();
  final speed = GlobalKey();
  final repeat = GlobalKey();
  final interval = GlobalKey();
  final playback = GlobalKey();
}

enum _Step { selection, order, start, speed, repeat, interval, experience }

/// Owns the sample tour and uses only the independent demo controller.
class ListeningDemoGuide extends StatefulWidget {
  const ListeningDemoGuide({
    super.key,
    required this.controller,
    required this.targets,
    required this.child,
    this.automatic = true,
  });
  final ListeningDemoController controller;
  final ListeningDemoTargets targets;
  final Widget child;
  final bool automatic;

  @override
  State<ListeningDemoGuide> createState() => ListeningDemoGuideState();
}

class ListeningDemoGuideState extends State<ListeningDemoGuide>
    with WidgetsBindingObserver {
  final _overlayKey = GlobalKey<OverlayState>();
  late final OverlayEntry _page;
  TutorialCoachMark? _spotlight;
  Timer? _timer;
  _Step _step = _Step.selection;
  bool _guided = true, _paused = false, _ready = false, _working = false;
  bool _foreground = true, _complete = false, _resumePlayback = false;
  bool _reducedMotion = false;
  static const _stepDwellMilliseconds = 2500;
  int _revision = 0, _remaining = _stepDwellMilliseconds;
  int _focusRevision = 0;
  String? _failure;
  ListeningDemoController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    c.foreground = _foreground;
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_controllerChanged);
    _page = OverlayEntry(builder: (_) => ExcludeSemantics(
      excluding: _guided,
      child: AbsorbPointer(absorbing: _guided, child: widget.child),
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) => _controllerChanged());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (reduced && !_reducedMotion) {
      _paused = true;
      if (_ready) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _pause();
        });
      }
    }
    _reducedMotion = reduced;
  }

  @override
  void didUpdateWidget(covariant ListeningDemoGuide oldWidget) {
    super.didUpdateWidget(oldWidget);
    _page.markNeedsBuild();
  }

  void _controllerChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      if (_ready || c.busy || !_guided || _working || _failure != null) return;
      if (c.error != null) {
        _fail(c.error!);
      } else if (c.ready) {
        unawaited(_restart());
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  ({GlobalKey key, String title, String text}) get _description {
    final t = widget.targets;
    return switch (_step) {
      _Step.selection => (key: t.selection, title: '选择收听内容',
        text: '选入第1课的单词和课文，一共四段内置样例音频。'),
      _Step.order => (key: t.order, title: '调整播放顺序',
        text: '把课文排在单词前面。自己操作时可以长按课程卡片拖动排序。'),
      _Step.start => (key: t.start, title: '按顺序循环播放',
        text: '从课文开始播放，接着播放单词，按所选顺序循环。'),
      _Step.speed => (key: t.speed, title: '放慢到 0.8 倍速',
        text: '将速度设为 0.8，听清发音。自己试用时可以调节速度。'),
      _Step.repeat => (key: t.repeat, title: '同一条听两遍',
        text: '将每条音频设为循环两次，再继续播放下一条。'),
      _Step.interval => (key: t.interval, title: '留出两秒跟读',
        text: '将间隔设为两秒，利用停顿回忆和跟读。'),
      _Step.experience => (key: t.playback, title: '试听当前设置',
        text: '现在是 0.8、每条两次、间隔两秒。演示结束后可自己继续试听。'),
    };
  }

  bool _valid(int revision) => mounted && _guided && revision == _revision;

  void _removeSpotlight() {
    ++_focusRevision;
    _spotlight?.removeOverlayEntry();
    _spotlight = null;
  }

  Future<void> _focus(int revision) async {
    _removeSpotlight();
    final focusRevision = _focusRevision;
    bool current() => _valid(revision) && focusRevision == _focusRevision;
    await WidgetsBinding.instance.endOfFrame;
    if (!current() || !_foreground) return;
    final target = _description.key.currentContext;
    if (target == null) throw StateError('演示位置暂不可用，请重新播放。');
    await Scrollable.ensureVisible(target,
      alignment: .5,
      duration: _reducedMotion ? Duration.zero : const Duration(milliseconds: 250));
    await WidgetsBinding.instance.endOfFrame;
    if (!current() || !_foreground) return;
    final overlay = _overlayKey.currentState;
    if (overlay == null) return;
    final box = _description.key.currentContext?.findRenderObject();
    final overlayBox = overlay.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || overlayBox is! RenderBox) {
      throw StateError('演示位置尚未完成布局，请重新播放。');
    }
    final coach = TutorialCoachMark(
      targets: [TargetFocus(
        // The package's key positioning uses Navigator coordinates. This tour
        // has a smaller local overlay above its controls, so use its coordinates.
        targetPosition: TargetPosition(
          box.size, box.localToGlobal(Offset.zero, ancestor: overlayBox)),
        shape: ShapeLightFocus.RRect,
        radius: 18,
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 3),
        enableTargetTab: false,
        enableOverlayTab: false,
        contents: [],
      )],
      hideSkip: true,
      useSafeArea: false,
      opacityShadow: .62,
      paddingFocus: 6,
      pulseEnable: !_reducedMotion && !_paused,
      focusAnimationDuration: Duration(milliseconds: _reducedMotion ? 1 : 250),
      backgroundSemanticLabel: '磨耳朵演示高亮区域',
    );
    _spotlight = coach;
    coach.showWithOverlayState(overlay: overlay);
    // The package defers insertion. Remove that deferred
    // insertion too if the user exits, skips, or changes steps in the meantime.
    await Future<void>.delayed(Duration.zero);
    if (!current() || !_foreground || _spotlight != coach) {
      coach.removeOverlayEntry();
    }
  }

  Future<void> _restart() async {
    if (_working || c.busy || !_foreground) return;
    final revision = ++_revision;
    _timer?.cancel();
    _removeSpotlight();
    setState(() {
      _working = true;
      _guided = true;
      _complete = false;
      _failure = null;
      _ready = false;
      _paused = _reducedMotion || !widget.automatic;
      _step = _Step.selection;
      _resumePlayback = false;
    });
    _page.markNeedsBuild();
    try {
      await c.stop();
      if (!_valid(revision)) return;
      await c.resetDemo();
      if (!_valid(revision)) return;
      if (c.error != null) throw StateError(c.error!);
      setState(() => _ready = true);
      await _enter(revision);
    } catch (e) {
      if (_valid(revision)) _fail(_errorText(e));
    } finally {
      if (mounted && revision == _revision) setState(() => _working = false);
    }
  }

  Future<void> _enter(int revision) async {
    _remaining = _stepDwellMilliseconds;
    await _focus(revision);
    if (!_valid(revision)) return;
    _armTimer();
  }

  void _armTimer() {
    _timer?.cancel();
    if (!widget.automatic || !_guided || _paused || !_foreground || _failure != null) return;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_paused || !_foreground || !_guided) {
        _timer?.cancel();
        return;
      }
      if (_working || c.busy) return;
      if (ModalRoute.of(context)?.isCurrent == false) {
        _pause();
        return;
      }
      final error = c.error ?? c.playbackError;
      if (error != null) {
        _fail(error);
        return;
      }
      _remaining -= 100;
      if (_remaining > 0) return;
      _timer?.cancel();
      unawaited(_advance());
    });
  }

  Future<void> _advance() async {
    if (_working || !_ready || !_guided || !_foreground || c.busy) return;
    final revision = ++_revision;
    _timer?.cancel();
    _removeSpotlight();
    setState(() => _working = true);
    try {
      if (!_valid(revision) || !_foreground) return;
      switch (_step) {
        case _Step.selection:
          c.selectAll();
          break;
        case _Step.order:
          c.demonstrateOrder();
          break;
        case _Step.start:
          await c.start(index: 0);
          break;
        case _Step.speed:
          await c.setSpeed(.8);
          break;
        case _Step.repeat:
          await c.setRepeat(2);
          break;
        case _Step.interval:
          await c.setInterval(2);
          break;
        case _Step.experience:
          await c.stop();
          break;
      }
      if (!_valid(revision)) return;
      if (c.error != null) throw StateError(c.error!);
      if (_step == _Step.experience) {
        setState(() { _complete = true; _guided = false; });
        _page.markNeedsBuild();
        return;
      }
      setState(() => _step = _Step.values[_step.index + 1]);
      await _enter(revision);
    } catch (e) {
      if (_valid(revision)) _fail(_errorText(e));
    } finally {
      if (mounted && revision == _revision) setState(() => _working = false);
    }
  }

  String _errorText(Object error) => error is StateError
      ? error.message.toString() : '演示暂时中断，请重新播放或自己试试。';

  void _fail(String message) {
    if (!mounted) return;
    _timer?.cancel();
    _removeSpotlight();
    setState(() { _failure = message; _paused = true; });
    unawaited(_stopAudio());
  }

  Future<void> _stopAudio() async {
    try {
      await c.stop();
    } catch (e) {
      if (mounted) setState(() => _failure = '样例音频停止失败，请重试。');
    }
  }

  void _pause() {
    _timer?.cancel();
    if (c.playing || c.stage == ListeningDemoStage.player) _resumePlayback = true;
    setState(() => _paused = true);
    _removeSpotlight();
    unawaited(_stopAudio());
    if (_guided && _ready && _foreground && !_working) {
      unawaited(_refocus());
    }
  }

  Future<void> _refocus() async {
    final revision = _revision;
    try { await _focus(revision); }
    catch (e) { if (_valid(revision)) _fail(_errorText(e)); }
  }

  Future<void> _resume() async {
    if (_working || !_foreground) return;
    final revision = _revision;
    setState(() { _paused = false; _working = true; });
    try {
      await c.stop();
      if (!_valid(revision) || _paused || !_foreground) return;
      await _focus(revision);
      if (!_valid(revision) || _paused || !_foreground) return;
      if (_resumePlayback) {
        _resumePlayback = false;
        _remaining = _stepDwellMilliseconds;
        await c.start();
      }
      if (!_valid(revision)) return;
      if (c.error != null) throw StateError(c.error!);
      _armTimer();
    } catch (e) {
      if (_valid(revision)) _fail(_errorText(e));
    } finally {
      if (mounted && revision == _revision) setState(() => _working = false);
    }
  }

  Future<void> _explore() async {
    if (_working || c.busy) return;
    ++_revision;
    _timer?.cancel();
    _removeSpotlight();
    setState(() => _working = true);
    await _stopAudio();
    if (!mounted) return;
    setState(() { _guided = false; _working = false; });
    _page.markNeedsBuild();
  }

  @override
  void didChangeMetrics() {
    if (_guided && _ready && !_working) _pause();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    c.foreground = _foreground;
    if (!_foreground) {
      _pause();
    } else if (_guided && _ready && !_working) {
      unawaited(_refocus());
    } else {
      _controllerChanged();
    }
  }

  @override
  void dispose() {
    ++_revision;
    _timer?.cancel();
    _removeSpotlight();
    c.removeListener(_controllerChanged);
    WidgetsBinding.instance.removeObserver(this);
    // The owning listening demo page disposes its controller and stops owned audio.
    _page.remove();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: LayoutBuilder(builder: (context, constraints) => Column(
      children: [
        Expanded(child: Overlay(key: _overlayKey, initialEntries: [_page])),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * .42),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: StudyCard(child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(liveRegion: true, child: Text(
                        _failure != null ? '演示已暂停' : !_guided
                            ? (_complete ? '演示完成 · 现在自己试试' : '自由试用 · 内置样例')
                            : !_ready ? '正在准备样例…'
                            : '${_step.index + 1}/${_Step.values.length} · ${_description.title}${_paused ? ' · 已暂停' : ''}',
                        style: Theme.of(context).textTheme.titleSmall,
                      )),
                      const SizedBox(height: 8),
                      Text(_failure ?? (!_guided
                          ? '可以选课、排序、调速度和循环。设置仅在本次演示有效。'
                          : !_ready ? '正在载入第1课的四段样例录音。' : _description.text)),
                      const SizedBox(height: 10),
                      if (_guided && _ready) ...[
                        LinearProgressIndicator(value: (_step.index + 1) / _Step.values.length),
                        const SizedBox(height: 10),
                      ],
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (_guided && _ready && _failure == null) ...[
                          if (widget.automatic) StudyButton.filled(
                            onPressed: _working ? null : _paused ? _resume : _pause,
                            child: Text(_paused ? '继续' : '暂停'),
                          ),
                          if (_paused || !widget.automatic) StudyButton.text(
                            onPressed: _working || c.busy ? null : _advance,
                            child: const Text('下一步'),
                          ),
                        ],
                        if (!_guided || _failure != null) StudyButton.filled(
                          onPressed: _working || c.busy ? null : _restart,
                          child: const Text('重新播放'),
                        ),
                        if (_guided) StudyButton.text(
                          onPressed: _working || c.busy ? null : _explore,
                          child: const Text('跳过 · 自己试试'),
                        ),
                        StudyButton.text(
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: const Text('退出演示'),
                        ),
                      ]),
                    ],
                  ),
                )),
              )),
            ),
          ),
        ),
      ],
    )),
  );
}

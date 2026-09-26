import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../../glass_ui.dart';
import 'controller.dart';

class FlashDemoTargets {
  final lesson = GlobalKey();
  final start = GlobalKey();
  final card = GlobalKey();
  final flip = GlobalKey();
  final known = GlobalKey();
  final weak = GlobalKey();
  final next = GlobalKey();
  final result = GlobalKey();
  final retry = GlobalKey();
}

enum _Step {
  lesson, start, listen, flip, answer, known, weak, next, result, retry, practice,
}

/// Owns the sample tour and uses only the independent demo controller.
class FlashDemoGuide extends StatefulWidget {
  const FlashDemoGuide({
    super.key,
    required this.controller,
    required this.targets,
    required this.child,
  });
  final FlashDemoController controller;
  final FlashDemoTargets targets;
  final Widget child;

  @override
  State<FlashDemoGuide> createState() => FlashDemoGuideState();
}

class FlashDemoGuideState extends State<FlashDemoGuide>
    with WidgetsBindingObserver {
  final _overlayKey = GlobalKey<OverlayState>();
  late final OverlayEntry _page;
  TutorialCoachMark? _spotlight;
  Timer? _timer;
  _Step _step = _Step.lesson;
  bool _guided = true, _paused = false, _ready = false, _working = false;
  bool _foreground = true, _complete = false, _replayAudio = false;
  bool _reducedMotion = false;
  static const _stepDwellMilliseconds = 2500;
  int _revision = 0, _remaining = _stepDwellMilliseconds, _audioWait = 0;
  int _focusRevision = 0;
  String? _failure;
  FlashDemoController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
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
  void didUpdateWidget(covariant FlashDemoGuide oldWidget) {
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
      } else if (c.lessons.isNotEmpty) {
        unawaited(_restart());
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  ({GlobalKey key, String title, String text}) get _description {
    final t = widget.targets;
    return switch (_step) {
      _Step.lesson => (key: t.lesson, title: '先选一课',
        text: '已选中第1课，用“中国人、日本人”两个样例走一遍复习。'),
      _Step.start => (key: t.start, title: '开始一轮闪卡',
        text: '选好课程后点这里开始。接下来会自动替你操作。'),
      _Step.listen => (key: t.card, title: '点词卡，听读音',
        text: '正在播放“中国人”的读音。平时也可以点词卡反复听。'),
      _Step.flip => (key: t.flip, title: '想一想，再看答案',
        text: '先回忆中文意思，再点“查看答案”翻面核对。'),
      _Step.answer => (key: t.card, title: '核对你的答案',
        text: '翻面后能看到答案及词条信息，确认自己是否记住了。'),
      _Step.known => (key: t.known, title: '记住了，就选认识',
        text: '标记“认识”后会自动进入下一张卡片。'),
      _Step.weak => (key: t.weak, title: '想不起来，就选不熟',
        text: '这次直接把“日本人”标记为不熟，看看接下来会发生什么。'),
      _Step.next => (key: t.next, title: '先记住答案，再继续',
        text: '正面选“不熟”后会停留在答案，给你时间记忆，再进入结果。'),
      _Step.result => (key: t.result, title: '看看这一轮的结果',
        text: '刚才认识1词、不熟1词。结果会列出需要加强的词。'),
      _Step.retry => (key: t.retry, title: '集中复习不熟的词',
        text: '点这里，只重练本轮不熟的“日本人”，不用把全部单词再过一遍。'),
      _Step.practice => (key: t.card, title: '再想一次，加深记忆',
        text: '重练队列只剩1词。再听一次读音，这次会标记“认识”完成复习。'),
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
      backgroundSemanticLabel: '闪卡演示高亮区域',
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
      _paused = _reducedMotion;
      _step = _Step.lesson;
      _replayAudio = false;
    });
    _page.markNeedsBuild();
    try {
      await c.stopDemoPronunciation();
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
    _audioWait = 0;
    await _focus(revision);
    if (!_valid(revision)) return;
    if (_step == _Step.listen || _step == _Step.practice) {
      _replayAudio = true;
      if (!_paused && _foreground) {
        _replayAudio = false;
        await c.playPronunciation();
        if (!_valid(revision)) return;
        if (c.error != null) throw StateError(c.error!);
      }
    }
    _armTimer();
  }

  void _armTimer() {
    _timer?.cancel();
    if (!_guided || _paused || !_foreground || _failure != null) return;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_paused || !_foreground || !_guided) {
        _timer?.cancel();
        return;
      }
      if (_working || c.busy || c.advancing) return;
      if (ModalRoute.of(context)?.isCurrent == false) {
        _pause();
        return;
      }
      final error = c.error ?? c.demoPronunciationError;
      if (error != null) {
        _fail(error);
        return;
      }
      _remaining -= 100;
      if (_remaining > 0) return;
      if (c.demoPronunciationActive) {
        _audioWait += 100;
        if (_audioWait >= 20000) _fail('读音播放未结束，请重新播放或自己试试。');
        return;
      }
      _timer?.cancel();
      unawaited(_advance());
    });
  }

  Future<void> _advance() async {
    if (_working || !_ready || !_guided || !_foreground || c.busy || c.advancing) return;
    final revision = ++_revision;
    _timer?.cancel();
    _removeSpotlight();
    setState(() => _working = true);
    try {
      await c.stopDemoPronunciation();
      if (!_valid(revision) || !_foreground) return;
      switch (_step) {
        case _Step.start:
          await c.start();
          break;
        case _Step.flip:
          c.flip();
          break;
        case _Step.known:
        case _Step.practice:
          await c.mark(true);
          break;
        case _Step.weak:
          await c.mark(false);
          break;
        case _Step.next:
          c.next();
          break;
        case _Step.retry:
          await c.retryWeak();
          break;
        default:
          break;
      }
      if (!_valid(revision)) return;
      if (c.error != null) throw StateError(c.error!);
      if (_step == _Step.practice) {
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
      await c.stopDemoPronunciation();
    } catch (e) {
      if (mounted) setState(() => _failure = '样例音频停止失败，请重试。');
    }
  }

  void _pause() {
    _timer?.cancel();
    if (_step == _Step.listen || _step == _Step.practice) _replayAudio = true;
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
      await c.stopDemoPronunciation();
      if (!_valid(revision) || _paused || !_foreground) return;
      await _focus(revision);
      if (!_valid(revision) || _paused || !_foreground) return;
      if (_replayAudio) {
        _replayAudio = false;
        _remaining = _stepDwellMilliseconds;
        await c.playPronunciation();
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
    // The owning flashcard page disposes its controller and stops owned audio.
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
                          ? '可以自由选课、翻面和复习。记录仅保留在本次演示中。'
                          : !_ready ? '正在载入第1课和配套读音。' : _description.text)),
                      const SizedBox(height: 10),
                      if (_guided && _ready) ...[
                        LinearProgressIndicator(value: (_step.index + 1) / _Step.values.length),
                        const SizedBox(height: 10),
                      ],
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (_guided && _ready && _failure == null) ...[
                          StudyButton.filled(
                            onPressed: _working ? null : _paused ? _resume : _pause,
                            child: Text(_paused ? '继续' : '暂停'),
                          ),
                          if (_paused) StudyButton.text(
                            onPressed: _working || c.busy || c.advancing ? null : _advance,
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

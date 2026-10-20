import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../../glass_ui.dart';
import '../../../l10n/l10n.dart';
import '../../demo_guide_l10n.dart';
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
    _page = OverlayEntry(
      builder: (_) => ExcludeSemantics(
        excluding: _guided,
        child: AbsorbPointer(absorbing: _guided, child: widget.child),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _controllerChanged());
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
        if (_guided && _ready && _foreground && _failure == null) {
          unawaited(_refocus());
        }
      });
    }
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
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
      _Step.selection => (
        key: t.selection,
        title: context.tr(
          '选择收听内容',
          '選擇收聽內容',
          'Choose what to listen to',
          '聴く内容を選ぶ',
        ),
        text: context.tr(
          '选入第1课的单词和课文，一共四段内置样例音频。',
          '選入第1課的單詞和課文，一共四段內建範例音訊。',
          'Select Lesson 1 vocabulary and texts: four built-in sample recordings.',
          '第1課の単語と本文を選びます。内蔵のサンプル音声は全部で4つです。',
        ),
      ),
      _Step.order => (
        key: t.order,
        title: context.tr(
          '调整播放顺序',
          '調整播放順序',
          'Change the playback order',
          '再生順を変える',
        ),
        text: context.tr(
          '把课文排在单词前面。自己操作时可以长按课程卡片拖动排序。',
          '把課文排在單詞前面。自行操作時可以長按課程卡片拖曳排序。',
          'Put texts before vocabulary. When trying it yourself, hold and drag a lesson card to reorder it.',
          '本文を単語より先に並べます。自分で試すときは、課のカードを長押ししてドラッグすると順序を変えられます。',
        ),
      ),
      _Step.start => (
        key: t.start,
        title: context.tr(
          '按顺序循环播放',
          '按順序循環播放',
          'Repeat in the chosen order',
          '選んだ順序で繰り返す',
        ),
        text: context.tr(
          '从课文开始播放，接着播放单词，按所选顺序循环。',
          '從課文開始播放，接著播放單詞，按所選順序循環。',
          'Play texts first, then vocabulary, and repeat in the selected order.',
          '本文、単語の順に再生し、選んだ順序で繰り返します。',
        ),
      ),
      _Step.speed => (
        key: t.speed,
        title: context.tr(
          '放慢到 0.8 倍速',
          '放慢到 0.8 倍速',
          'Slow down to 0.8×',
          '0.8倍速にする',
        ),
        text: context.tr(
          '将速度设为 0.8，听清发音。自己试用时可以调节速度。',
          '將速度設為 0.8，聽清發音。自行試用時可以調節速度。',
          'Set the speed to 0.8× to hear the pronunciation clearly. You can adjust it when trying the demo yourself.',
          '発音を聞き取りやすいように0.8倍速にします。自由に試すときは速度を調整できます。',
        ),
      ),
      _Step.repeat => (
        key: t.repeat,
        title: context.tr(
          '同一条听两遍',
          '同一段聽兩遍',
          'Listen to each item twice',
          '各音声を2回聴く',
        ),
        text: context.tr(
          '将每条音频设为循环两次，再继续播放下一条。',
          '將每段音訊設為循環兩次，再繼續播放下一段。',
          'Repeat each recording twice before moving to the next one.',
          '各音声を2回繰り返してから、次の音声を再生します。',
        ),
      ),
      _Step.interval => (
        key: t.interval,
        title: context.tr(
          '留出两秒跟读',
          '留出兩秒跟讀',
          'Leave two seconds to repeat aloud',
          '復唱のために2秒空ける',
        ),
        text: context.tr(
          '将间隔设为两秒，利用停顿回忆和跟读。',
          '將間隔設為兩秒，利用停頓回憶和跟讀。',
          'Set a two-second gap to recall what you heard and repeat it aloud.',
          '間隔を2秒に設定します。間を使って思い出したり、声に出して繰り返したりしましょう。',
        ),
      ),
      _Step.experience => (
        key: t.playback,
        title: context.tr(
          '试听当前设置',
          '試聽目前設定',
          'Try the current settings',
          '現在の設定で試聴する',
        ),
        text: context.tr(
          '现在是 0.8、每条两次、间隔两秒。演示结束后可自己继续试听。',
          '目前是 0.8 倍速、每段兩次、間隔兩秒。示範結束後可自行繼續試聽。',
          'The settings are 0.8× speed, two repeats, and a two-second gap. Keep listening on your own after the tour.',
          '現在は0.8倍速、各2回、間隔2秒です。ガイド終了後も自由に試聴できます。',
        ),
      ),
    };
  }

  bool _valid(int revision) => mounted && _guided && revision == _revision;

  void _removeSpotlight() {
    ++_focusRevision;
    removeDemoGuideOverlay(_spotlight);
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
    await Scrollable.ensureVisible(
      target,
      alignment: .5,
      duration: _reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 250),
    );
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
      targets: [
        TargetFocus(
          // The package's key positioning uses Navigator coordinates. This tour
          // has a smaller local overlay above its controls, so use its coordinates.
          targetPosition: TargetPosition(
            box.size,
            box.localToGlobal(Offset.zero, ancestor: overlayBox),
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
      paddingFocus: 6,
      pulseEnable: !_reducedMotion && !_paused,
      focusAnimationDuration: Duration(milliseconds: _reducedMotion ? 1 : 250),
      backgroundSemanticLabel: context.tr(
        '磨耳朵演示高亮区域',
        '磨耳朵示範反白區域',
        'Listening demo highlighted area',
        'リスニングデモの強調領域',
      ),
    );
    _spotlight = coach;
    coach.showWithOverlayState(overlay: overlay);
    // The package defers insertion. Remove that deferred
    // insertion too if the user exits, skips, or changes steps in the meantime.
    await Future<void>.delayed(Duration.zero);
    if (!current() || !_foreground || _spotlight != coach) {
      removeDemoGuideOverlay(coach);
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
    if (!widget.automatic ||
        !_guided ||
        _paused ||
        !_foreground ||
        _failure != null)
      return;
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
        setState(() {
          _complete = true;
          _guided = false;
        });
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

  String _errorText(Object error) =>
      error is StateError ? error.message.toString() : '演示暂时中断，请重新播放或自己试试。';

  void _fail(String message) {
    if (!mounted) return;
    _timer?.cancel();
    _removeSpotlight();
    setState(() {
      _failure = message;
      _paused = true;
    });
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
    if (c.playing || c.stage == ListeningDemoStage.player)
      _resumePlayback = true;
    setState(() => _paused = true);
    _removeSpotlight();
    unawaited(_stopAudio());
    if (_guided && _ready && _foreground && !_working) {
      unawaited(_refocus());
    }
  }

  Future<void> _refocus() async {
    final revision = _revision;
    try {
      await _focus(revision);
    } catch (e) {
      if (_valid(revision)) _fail(_errorText(e));
    }
  }

  Future<void> _resume() async {
    if (_working || !_foreground) return;
    final revision = _revision;
    setState(() {
      _paused = false;
      _working = true;
    });
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
    setState(() {
      _guided = false;
      _working = false;
    });
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
    child: LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          Expanded(
            child: Overlay(key: _overlayKey, initialEntries: [_page]),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * .42),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: StudyCard(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _failure != null
                                    ? context.tr(
                                        '演示已暂停',
                                        '示範已暫停',
                                        'Demo paused',
                                        'デモを一時停止中',
                                      )
                                    : !_guided
                                    ? (_complete
                                          ? context.tr(
                                              '演示完成 · 现在自己试试',
                                              '示範完成 · 現在自己試試',
                                              'Tour complete · Try it yourself',
                                              'ガイド完了 · 自由に試してみましょう',
                                            )
                                          : context.tr(
                                              '自由试用 · 内置样例',
                                              '自由試用 · 內建範例',
                                              'Explore · Built-in samples',
                                              '自由体験 · 内蔵サンプル',
                                            ))
                                    : !_ready
                                    ? context.tr(
                                        '正在准备样例…',
                                        '正在準備範例…',
                                        'Preparing samples…',
                                        'サンプルを準備中…',
                                      )
                                    : '${_step.index + 1}/${_Step.values.length} · ${_description.title}${_paused ? context.tr(' · 已暂停', ' · 已暫停', ' · Paused', ' · 一時停止中') : ''}',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _failure != null
                                  ? demoGuideError(context, _failure!)
                                  : (!_guided
                                        ? context.tr(
                                            '可以选课、排序、调速度和循环。设置仅在本次演示有效。',
                                            '可以選課、排序、調整速度和循環。設定僅在本次示範有效。',
                                            'Choose lessons, reorder them, and adjust speed and repeats. Settings apply only to this demo.',
                                            '課の選択、並べ替え、速度や繰り返しの調整ができます。設定は今回のデモ内だけで有効です。',
                                          )
                                        : !_ready
                                        ? context.tr(
                                            '正在载入第1课的四段样例录音。',
                                            '正在載入第1課的四段範例錄音。',
                                            'Loading the four sample recordings for Lesson 1.',
                                            '第1課の4つのサンプル音声を読み込み中です。',
                                          )
                                        : _description.text),
                            ),
                            const SizedBox(height: 10),
                            if (_guided && _ready) ...[
                              LinearProgressIndicator(
                                value: (_step.index + 1) / _Step.values.length,
                              ),
                              const SizedBox(height: 10),
                            ],
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (_guided && _ready && _failure == null) ...[
                                  if (widget.automatic)
                                    StudyButton.filled(
                                      onPressed: _working
                                          ? null
                                          : _paused
                                          ? _resume
                                          : _pause,
                                      child: Text(
                                        _paused
                                            ? context.tr(
                                                '继续',
                                                '繼續',
                                                'Resume',
                                                '再開',
                                              )
                                            : context.tr(
                                                '暂停',
                                                '暫停',
                                                'Pause',
                                                '一時停止',
                                              ),
                                      ),
                                    ),
                                  if (_paused || !widget.automatic)
                                    StudyButton.text(
                                      onPressed: _working || c.busy
                                          ? null
                                          : _advance,
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
                                if (!_guided || _failure != null)
                                  StudyButton.filled(
                                    onPressed: _working || c.busy
                                        ? null
                                        : _restart,
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
                                    onPressed: _working || c.busy
                                        ? null
                                        : _explore,
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
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
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
            ),
          ),
        ],
      ),
    ),
  );
}

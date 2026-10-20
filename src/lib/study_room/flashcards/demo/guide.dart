import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../../glass_ui.dart';
import '../../../l10n/l10n.dart';
import '../../demo_guide_l10n.dart';
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
  lesson,
  start,
  listen,
  flip,
  answer,
  known,
  weak,
  next,
  result,
  retry,
  practice,
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
      _Step.lesson => (
        key: t.lesson,
        title: context.tr('先选一课', '先選一課', 'Choose a lesson first', 'まず課を選ぶ'),
        text: context.tr(
          '已选中第1课，用“中国人、日本人”两个样例走一遍复习。',
          '已選中第1課，用「中国人、日本人」兩個範例走一遍複習。',
          'Lesson 1 is selected. Review the two sample words, “中国人” and “日本人”.',
          '第1課を選択しています。「中国人」と「日本人」の2つのサンプルで復習の流れを体験します。',
        ),
      ),
      _Step.start => (
        key: t.start,
        title: context.tr(
          '开始一轮闪卡',
          '開始一輪閃卡',
          'Start a flashcard round',
          'フラッシュカードを始める',
        ),
        text: context.tr(
          '选好课程后点这里开始。接下来会自动替你操作。',
          '選好課程後點選這裡開始。接下來會自動替你操作。',
          'After selecting lessons, tap here to begin. The tour will demonstrate the following actions automatically.',
          '課を選んだら、ここを押して始めます。ここからの操作はガイドが自動で実演します。',
        ),
      ),
      _Step.listen => (
        key: t.card,
        title: context.tr(
          '点词卡，听读音',
          '點選詞卡，聽讀音',
          'Tap a card to hear it',
          'カードを押して発音を聴く',
        ),
        text: context.tr(
          '正在播放“中国人”的读音。平时也可以点词卡反复听。',
          '正在播放「中国人」的讀音。平時也可以點選詞卡反覆聽。',
          'The pronunciation of “中国人” is playing. Tap a card any time to hear its pronunciation again.',
          '「中国人」の発音を再生しています。普段もカードを押して繰り返し聴けます。',
        ),
      ),
      _Step.flip => (
        key: t.flip,
        title: context.tr(
          '想一想，再看答案',
          '想一想，再看答案',
          'Recall before revealing',
          '思い出してから答えを見る',
        ),
        text: context.tr(
          '先回忆中文意思，再点“查看答案”翻面核对。',
          '先回憶中文意思，再點選「查看答案」翻面核對。',
          'Recall the Chinese meaning, then tap “Show answer” to turn the card over and check.',
          'まず中国語の意味を思い出し、「答えを表示」で裏返して確認します。',
        ),
      ),
      _Step.answer => (
        key: t.card,
        title: context.tr(
          '核对你的答案',
          '核對你的答案',
          'Check your answer',
          '自分の答えを確認する',
        ),
        text: context.tr(
          '翻面后能看到答案及词条信息，确认自己是否记住了。',
          '翻面後能看到答案及詞條資訊，確認自己是否記住了。',
          'The reverse shows the answer and word details, so you can check whether you remembered.',
          '裏面には答えと単語の情報が表示されます。覚えていたかを確認しましょう。',
        ),
      ),
      _Step.known => (
        key: t.known,
        title: context.tr(
          '记住了，就选认识',
          '記住了，就選認識',
          'Remember it? Choose Known',
          '覚えていたら「覚えた」',
        ),
        text: context.tr(
          '标记“认识”后会自动进入下一张卡片。',
          '標記「認識」後會自動進入下一張卡片。',
          'Marking a word as “Known” automatically opens the next card.',
          '「覚えた」を選ぶと、自動で次のカードに進みます。',
        ),
      ),
      _Step.weak => (
        key: t.weak,
        title: context.tr(
          '想不起来，就选不熟',
          '想不起來，就選不熟',
          'Not sure? Choose Unfamiliar',
          '思い出せなければ「まだ」',
        ),
        text: context.tr(
          '这次直接把“日本人”标记为不熟，看看接下来会发生什么。',
          '這次直接把「日本人」標記為不熟，看看接下來會發生什麼。',
          'This time, mark “日本人” as “Unfamiliar” and see what happens next.',
          '今回は「日本人」を「まだ」にして、その後の流れを見てみましょう。',
        ),
      ),
      _Step.next => (
        key: t.next,
        title: context.tr(
          '先记住答案，再继续',
          '先記住答案，再繼續',
          'Learn the answer, then continue',
          '答えを覚えてから進む',
        ),
        text: context.tr(
          '正面选“不熟”后会停留在答案，给你时间记忆，再进入结果。',
          '正面選「不熟」後會停留在答案，給你時間記憶，再進入結果。',
          'Choosing “Unfamiliar” on the front keeps the answer visible so you can study it before viewing results.',
          '表面で「まだ」を選ぶと答えが表示されたままになります。覚える時間を取ってから結果に進みます。',
        ),
      ),
      _Step.result => (
        key: t.result,
        title: context.tr(
          '看看这一轮的结果',
          '看看這一輪的結果',
          'Review this round',
          '今回の結果を見る',
        ),
        text: context.tr(
          '刚才认识1词、不熟1词。结果会列出需要加强的词。',
          '剛才認識1詞、不熟1詞。結果會列出需要加強的詞。',
          'You marked one word as known and one as unfamiliar. The results list words to review.',
          '今回は「覚えた」が1語、「まだ」が1語でした。結果には復習が必要な単語が表示されます。',
        ),
      ),
      _Step.retry => (
        key: t.retry,
        title: context.tr(
          '集中复习不熟的词',
          '集中複習不熟的詞',
          'Focus on unfamiliar words',
          '要復習の単語を集中的に練習',
        ),
        text: context.tr(
          '点这里，只重练本轮不熟的“日本人”，不用把全部单词再过一遍。',
          '點選這裡，只重練本輪不熟的「日本人」，不用把全部單詞再過一遍。',
          'Tap here to retry only “日本人”, the word marked unfamiliar, without repeating all the words.',
          'ここを押すと、今回「まだ」にした「日本人」だけを練習できます。すべての単語をやり直す必要はありません。',
        ),
      ),
      _Step.practice => (
        key: t.card,
        title: context.tr(
          '再想一次，加深记忆',
          '再想一次，加深記憶',
          'Recall again to remember better',
          'もう一度思い出して定着させる',
        ),
        text: context.tr(
          '重练队列只剩1词。再听一次读音，这次会标记“认识”完成复习。',
          '重練佇列只剩1詞。再聽一次讀音，這次會標記「認識」完成複習。',
          'Only one word remains in the retry round. Listen again, then mark it as “Known” to finish.',
          '復習のカードは残り1語です。もう一度発音を聴き、今度は「覚えた」にして復習を終えます。',
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
        '闪卡演示高亮区域',
        '閃卡示範反白區域',
        'Flashcard demo highlighted area',
        'フラッシュカードデモの強調領域',
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
    if (_working ||
        !_ready ||
        !_guided ||
        !_foreground ||
        c.busy ||
        c.advancing)
      return;
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
                                            '可以自由选课、翻面和复习。记录仅保留在本次演示中。',
                                            '可以自由選課、翻面和複習。紀錄僅保留在本次示範中。',
                                            'Choose lessons, flip cards, and review freely. Records last only for this demo.',
                                            '自由に課を選び、カードを裏返して復習できます。記録は今回のデモ内だけに残ります。',
                                          )
                                        : !_ready
                                        ? context.tr(
                                            '正在载入第1课和配套读音。',
                                            '正在載入第1課和配套讀音。',
                                            'Loading Lesson 1 and its pronunciation audio.',
                                            '第1課と発音音声を読み込み中です。',
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
                                  if (_paused)
                                    StudyButton.text(
                                      onPressed:
                                          _working || c.busy || c.advancing
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

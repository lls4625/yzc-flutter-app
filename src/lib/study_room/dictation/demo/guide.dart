part of 'page.dart';

enum _TourStep {
  selection, order, rules, start, listen, wrong, correction, reset,
  answer, reveal, next, words,
}

class DictationDemoPage extends StatefulWidget {
  const DictationDemoPage({super.key});
  @override
  State<DictationDemoPage> createState() => _DictationDemoPageState();
}

class _DictationDemoPageState extends State<DictationDemoPage>
    with WidgetsBindingObserver {
  final c = DictationDemoController();
  final _overlayKey = GlobalKey<OverlayState>();
  late final OverlayEntry _page;
  TutorialCoachMark? _spotlight;
  Timer? _timer;
  Timer? _advanceTimer;
  _TourStep _step = _TourStep.selection;
  bool _ready = false, _paused = false, _busy = false, _complete = false;
  bool _foreground = true, _reducedMotion = false, _needsFocus = true;
  bool _focusing = false, _exiting = false;
  bool _lastCanAdvance = false;
  _DictationStage? _lastStage;
  int? _lastIndex;
  Future<void>? _suspension;
  int _revision = 0, _focusRevision = 0, _remaining = 2500;
  String? _failure;
  _DictationPageState? get p => c.practiceKey.currentState;
  _DictationDemoSelectionPageState? get s => c.selectionKey.currentState;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _page = OverlayEntry(builder: (_) => ExcludeSemantics(
      excluding: c.guided,
      child: AbsorbPointer(
        absorbing: c.guided,
        child: Navigator(
          key: c.navigator,
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            pageBuilder: (_, __, ___) => DictationDemoSelectionPage(
              c, key: c.selectionKey,
            ),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        ),
      ),
    ));
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (reduced && !_reducedMotion) {
      _paused = true;
      if (_ready) WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_pause());
      });
    }
    _reducedMotion = reduced;
  }

  ({GlobalKey key, String title, String text}) get _description => switch (_step) {
    _TourStep.selection => (key: c.selectionTarget, title: '选择听写内容',
      text: '选入内置第1课的单词和课文。下方也可分别选择全部单词、全部课文或取消。'),
    _TourStep.order => (key: c.orderTarget, title: '调整课程顺序',
      text: '将课文排到单词前面，先演示词组填答。自己试用时可长按课程卡片拖动排序。'),
    _TourStep.rules => (key: c.rulesTarget, title: '设置听写规则',
      text: '停顿方式、重复次数、间隔和顺序与正式听写一致。本次使用每句停顿、重复2次、间隔1秒、顺序播放。'),
    _TourStep.start => (key: c.startTarget, title: '开始听写',
      text: '点击右上角播放按钮，按照选定的课程顺序进入听写。'),
    _TourStep.listen => (key: c.audioTarget, title: '听音并回想',
      text: '原文先隐藏。实际录音播放及停顿结束后，课文会出现词组空格。自己试用时可点击这里重听。'),
    _TourStep.wrong => (key: c.choicesTarget, title: '示范选错词组',
      text: '先选择一个与当前空格不匹配的词组，观察真实的错误提示。'),
    _TourStep.correction => (key: c.choicesTarget, title: '纠正选择',
      text: '选错的词组显示红色叉号，空格保持不变。接下来选入第一个正确词组。'),
    _TourStep.reset => (key: c.resetTarget, title: '重新填写',
      text: '已填入第一个词组。点击“重新填写”清空答案；也可点击某个空格单独重填。'),
    _TourStep.answer => (key: c.choicesTarget, title: '按原文顺序填答',
      text: '逐个选入正确词组，填满后显示原文和翻译。引导会等待实际播放及填答状态，不跳过播放。'),
    _TourStep.reveal => (key: c.audioTarget, title: '核对答案',
      text: '课文全部填对后显示答案。正式流程和自由试用会在3秒后进入下一项；引导暂留此处方便查看。'),
    _TourStep.next => (key: c.nextTarget, title: '下一个',
      text: '已经进入下一条课文。“下一个”也可以略过当前题；接下来用它进入单词，展示单词的核对方式。'),
    _TourStep.words => (key: c.audioTarget, title: '单词听写与核对',
      text: '单词在播放与停顿后直接显示原文和翻译，不出现词组填空。引导结束后继续自由试用，设置仅在本次演示有效。'),
  };

  bool get _canAdvance {
    if (!_ready || _failure != null || !_foreground || _busy || _needsFocus || _focusing) return false;
    return switch (_step) {
      _TourStep.selection || _TourStep.order || _TourStep.rules || _TourStep.start =>
        s != null && !s!.loading && !s!.savingRule && !s!.choosingBook,
      _TourStep.listen || _TourStep.wrong || _TourStep.correction ||
      _TourStep.reset || _TourStep.answer => p?._canAnswer == true,
      _TourStep.reveal => p?._stage == _DictationStage.revealed,
      _TourStep.next => p != null && !p!._starting &&
          (p!._stage == _DictationStage.answering || p!._stage == _DictationStage.revealed),
      _TourStep.words => p?._stage == _DictationStage.revealed,
    };
  }

  void _tick() {
    if (!mounted || !c.guided || !_foreground || _exiting || _busy) return;
    final error = s?.error ??
        (p?._stage == _DictationStage.failed ? p?._message : null);
    if (error != null && _failure == null) {
      _fail(error);
      return;
    }
    if (_failure != null || _busy) return;
    if (!_ready) {
      if (s != null && !s!.loading) unawaited(_restart(preservePause: true));
      return;
    }
    final stage = p?._stage;
    final index = p?._index;
    if (stage != _lastStage || index != _lastIndex) {
      _lastStage = stage;
      _lastIndex = index;
      setState(() {
        _needsFocus = true;
        _remaining = 2500;
      });
    }
    if (_needsFocus && !_focusing) unawaited(_focus());
    final available = _canAdvance;
    if (available != _lastCanAdvance) {
      _lastCanAdvance = available;
      setState(() {});
    }
  }

  void _armAdvanceTimer() {
    _advanceTimer?.cancel();
    if (!mounted || !c.guided || _paused || !_foreground || _failure != null || _exiting) return;
    _advanceTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || !c.guided || _paused || !_foreground || _failure != null || _exiting) {
        _advanceTimer?.cancel();
        return;
      }
      if (!_canAdvance) return;
      _remaining -= 100;
      if (_remaining <= 0) {
        _advanceTimer?.cancel();
        unawaited(_advance());
      }
    });
  }

  void _removeSpotlight() {
    ++_focusRevision;
    _focusing = false;
    _spotlight?.removeOverlayEntry();
    _spotlight = null;
  }

  Future<void> _focus() async {
    if (_focusing || !c.guided || !_foreground) return;
    final target = _description.key.currentContext;
    if (target == null) return;
    _removeSpotlight();
    _focusing = true;
    final revision = _revision;
    final focusRevision = _focusRevision;
    bool current() => mounted && c.guided && _foreground &&
        revision == _revision && focusRevision == _focusRevision;
    try {
      await Scrollable.ensureVisible(target, alignment: .5,
        duration: _reducedMotion ? Duration.zero : const Duration(milliseconds: 250))
          .timeout(const Duration(seconds: 3));
      await WidgetsBinding.instance.endOfFrame;
      if (!current()) return;
      final overlay = _overlayKey.currentState;
      final box = _description.key.currentContext?.findRenderObject();
      final overlayBox = overlay?.context.findRenderObject();
      if (overlay == null || box is! RenderBox || !box.hasSize || overlayBox is! RenderBox) {
        throw StateError('演示位置尚未完成布局');
      }
      final coach = TutorialCoachMark(
        targets: [TargetFocus(
          targetPosition: TargetPosition(box.size,
            box.localToGlobal(Offset.zero, ancestor: overlayBox)),
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
        pulseEnable: !_paused && !_reducedMotion,
        focusAnimationDuration: Duration(milliseconds: _reducedMotion ? 1 : 250),
        backgroundSemanticLabel: '听写演示高亮区域',
      );
      _spotlight = coach;
      coach.showWithOverlayState(overlay: overlay);
      await Future<void>.delayed(Duration.zero);
      if (!current() || _spotlight != coach) {
        coach.removeOverlayEntry();
      } else {
        setState(() => _needsFocus = false);
      }
    } catch (_) {
      if (current()) _fail('演示高亮位置暂不可用，请重新播放。');
    } finally {
      if (focusRevision == _focusRevision) _focusing = false;
    }
  }

  Future<void> _restart({bool preservePause = false}) async {
    if (_busy || !_foreground) return;
    final revision = ++_revision;
    _advanceTimer?.cancel();
    _removeSpotlight();
    setState(() {
      _busy = true;
      _failure = null;
      _ready = false;
      _complete = false;
      c.guided = true;
      _paused = _reducedMotion || (preservePause && _paused);
      _step = _TourStep.selection;
    });
    _page.markNeedsBuild();
    try {
      await _stopPractice();
      if (!mounted || revision != _revision) return;
      c.navigator.currentState?.popUntil((route) => route.isFirst);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || revision != _revision) return;
      await c.reset();
      await s?._load();
      if (!mounted || revision != _revision) return;
      if (s?.error != null) throw StateError(s!.error!);
      setState(() {
        _ready = true;
        _remaining = 2500;
        _needsFocus = true;
      });
    } catch (e) {
      if (mounted && revision == _revision) _fail(featureError(e, fallback: '样例读取失败，请重新播放。'));
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted && revision == _revision) _armAdvanceTimer();
    }
  }

  Future<void> _advance() async {
    if (!_canAdvance) return;
    _advanceTimer?.cancel();
    final revision = _revision;
    _removeSpotlight();
    setState(() => _busy = true);
    try {
      var next = true;
      switch (_step) {
        case _TourStep.selection:
          s!._selectAll();
          break;
        case _TourStep.order:
          final content = s!.selected.firstWhere((card) => !card.words);
          s!._drop(content.key, s!.selected.first.key);
          break;
        case _TourStep.rules:
          await s!._saveRule('pause_each', true);
          await s!._saveRule('repeats', 2);
          await s!._saveRule('interval', 1);
          await s!._saveRule('random_order', false);
          break;
        case _TourStep.start:
          unawaited(s!._confirm());
          break;
        case _TourStep.listen:
          break;
        case _TourStep.wrong:
          final wrong = p!._choices.where((i) => p!._phrases[i] != p!._phrases[p!._slot]);
          if (wrong.isEmpty) throw StateError('当前样例无法演示错误词组，请检查演示课文。');
          p!._fill(wrong.first);
          break;
        case _TourStep.correction:
          p!._fill(p!._slot);
          break;
        case _TourStep.reset:
          p!._clearAnswer();
          break;
        case _TourStep.answer:
          p!._fill(p!._slot);
          next = p!._stage == _DictationStage.revealed;
          break;
        case _TourStep.reveal:
          unawaited(p!._next());
          break;
        case _TourStep.next:
          unawaited(p!._next());
          break;
        case _TourStep.words:
          await _explore(completed: true, fromAdvance: true);
          return;
      }
      if (!mounted || revision != _revision || !_foreground || _exiting) return;
      setState(() {
        if (next) _step = _TourStep.values[_step.index + 1];
        _remaining = next ? 2500 : 900;
        _needsFocus = true;
      });
    } catch (e) {
      if (mounted) _fail(featureError(e, fallback: '演示暂时中断，请重新播放。'));
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted && revision == _revision) _armAdvanceTimer();
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    _advanceTimer?.cancel();
    _removeSpotlight();
    setState(() { _failure = message; _paused = true; });
    unawaited(_stopPractice().catchError((Object _) {}));
  }

  Future<void> _stopPractice() async {
    final pending = _suspension ??= p?._suspend() ?? Future<void>.value();
    try {
      await pending;
    } finally {
      if (identical(_suspension, pending)) _suspension = null;
    }
  }

  Future<void> _pause() async {
    if (!mounted) return;
    ++_revision;
    _advanceTimer?.cancel();
    _removeSpotlight();
    setState(() { _paused = true; _needsFocus = true; });
    try {
      await _stopPractice();
    } catch (_) {
      if (mounted) _fail('样例音频停止失败，请重新播放。');
    }
  }

  Future<void> _resume() async {
    if (_busy || !_foreground || _exiting || !c.guided || _failure != null) return;
    final revision = ++_revision;
    _advanceTimer?.cancel();
    _removeSpotlight();
    setState(() { _busy = true; _needsFocus = true; });
    try {
      await _stopPractice();
      if (!mounted || revision != _revision || !_foreground || _exiting) return;
      p?._resumeDemo();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || revision != _revision || !_foreground || _exiting) return;
      await _focus();
      if (!mounted || revision != _revision || !_foreground || _exiting || _failure != null) return;
      final preparing = p?._stage == _DictationStage.loading ||
          p?._stage == _DictationStage.listening || p?._stage == _DictationStage.waiting;
      if (_needsFocus && !preparing) throw StateError('演示位置暂不可用，请重新播放');
      setState(() {
        _paused = false;
        // Removing the manual-step button changes the local overlay's height.
        _needsFocus = true;
      });
    } catch (_) {
      if (mounted && revision == _revision) _fail('演示恢复失败，请重新播放。');
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted && revision == _revision) _armAdvanceTimer();
    }
  }

  Future<void> _manualNext() async {
    if (_busy || !_foreground) return;
    try {
      if (_suspension != null) await _suspension;
    } catch (_) {
      if (mounted) _fail('样例音频停止失败，请重新播放。');
      return;
    }
    if (!mounted || !_foreground || _exiting) return;
    if (p?._stage == _DictationStage.paused) {
      p!._resumeDemo();
      setState(() => _needsFocus = true);
      return;
    }
    await _advance();
  }

  Future<void> _explore({bool completed = false, bool fromAdvance = false}) async {
    if ((_busy && !fromAdvance) || !_foreground) return;
    _advanceTimer?.cancel();
    final revision = _revision;
    _removeSpotlight();
    setState(() => _busy = true);
    try {
      await _stopPractice();
      if (!mounted || revision != _revision || !_foreground || _exiting) return;
      setState(() {
        c.guided = false;
        _failure = null;
        _complete = completed;
        _busy = false;
      });
      _page.markNeedsBuild();
      p?._resumeDemo();
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _fail('样例音频停止失败，请重试。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exit() async {
    if (_exiting) return;
    _exiting = true;
    _advanceTimer?.cancel();
    ++_revision;
    _removeSpotlight();
    try {
      await _stopPractice();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        _exiting = false;
        _fail('样例音频停止失败，请再次退出。');
      }
    }
  }

  @override
  void didChangeMetrics() {
    if (c.guided && _ready) {
      _removeSpotlight();
      setState(() => _needsFocus = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      unawaited(_pause());
    } else if (mounted) {
      setState(() => _needsFocus = true);
    }
  }

  @override
  void dispose() {
    ++_revision;
    _timer?.cancel();
    _advanceTimer?.cancel();
    _removeSpotlight();
    WidgetsBinding.instance.removeObserver(this);
    _page.remove();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) return;
      if (!c.guided && c.navigator.currentState?.canPop() == true) {
        c.navigator.currentState!.pop();
      } else {
        unawaited(_exit());
      }
    },
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(builder: (context, bounds) => Column(children: [
        Expanded(child: Overlay(key: _overlayKey, initialEntries: [_page])),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: bounds.maxHeight * .42),
          child: SafeArea(top: false, child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: StudyCard(child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Semantics(liveRegion: true, child: Text(
                    _failure != null ? '演示已暂停'
                        : !c.guided ? (_complete ? '演示完成 · 现在自己试试' : '自由试用 · 内置样例')
                        : !_ready ? '正在准备样例…'
                        : '${_step.index + 1}/${_TourStep.values.length} · ${_description.title}${_paused ? ' · 已暂停' : ''}',
                    style: Theme.of(context).textTheme.titleSmall,
                  )),
                  const SizedBox(height: 8),
                  Text(_failure ?? (!c.guided
                      ? '可以选课、排序、设置规则和练习听写。仅使用内置样例，不保存学习记录。'
                      : !_ready ? '正在读取内置内容与样例音频。' : _description.text)),
                  const SizedBox(height: 10),
                  if (c.guided && _ready) ...[
                    LinearProgressIndicator(value: (_step.index + 1) / _TourStep.values.length),
                    const SizedBox(height: 10),
                  ],
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (c.guided && _ready && _failure == null) ...[
                      StudyButton.filled(
                        onPressed: _busy ? null : _paused ? _resume : _pause,
                        child: Text(_paused ? '继续' : '暂停'),
                      ),
                      if (_paused) StudyButton.text(
                        onPressed: !_busy && (_canAdvance ||
                            p?._stage == _DictationStage.paused) ? _manualNext : null,
                        child: const Text('下一步'),
                      ),
                    ],
                    if (!c.guided || _failure != null) StudyButton.filled(
                      onPressed: _busy ? null : _restart,
                      child: const Text('重新播放'),
                    ),
                    if (c.guided) StudyButton.text(
                      onPressed: _busy ? null : () => _explore(),
                      child: const Text('跳过 · 自己试试'),
                    ),
                    StudyButton.text(onPressed: _exit, child: const Text('退出演示')),
                  ]),
                ]),
              )),
            )),
          )),
        ),
      ])),
    ),
  );
}

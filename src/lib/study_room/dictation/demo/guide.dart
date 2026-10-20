part of 'page.dart';

enum _TourStep {
  selection,
  order,
  rules,
  start,
  listen,
  wrong,
  correction,
  reset,
  answer,
  reveal,
  next,
  words,
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
    _page = OverlayEntry(
      builder: (_) => ExcludeSemantics(
        excluding: c.guided,
        child: AbsorbPointer(
          absorbing: c.guided,
          child: Navigator(
            key: c.navigator,
            onGenerateRoute: (_) => PageRouteBuilder<void>(
              pageBuilder: (_, __, ___) =>
                  DictationDemoSelectionPage(c, key: c.selectionKey),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
          ),
        ),
      ),
    );
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
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
        if (c.guided && _ready && _foreground && _failure == null) {
          _removeSpotlight();
          setState(() => _needsFocus = true);
          unawaited(_focus());
        }
      });
    }
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (reduced && !_reducedMotion) {
      _paused = true;
      if (_ready)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_pause());
        });
    }
    _reducedMotion = reduced;
  }

  ({GlobalKey key, String title, String text})
  get _description => switch (_step) {
    _TourStep.selection => (
      key: c.selectionTarget,
      title: context.tr(
        '选择听写内容',
        '選擇聽寫內容',
        'Choose dictation content',
        '書き取りの内容を選ぶ',
      ),
      text: context.tr(
        '选入内置第1课的单词和课文。下方也可分别选择全部单词、全部课文或取消。',
        '選入內建第1課的單詞和課文。下方也可分別選擇全部單詞、全部課文或取消。',
        'Select the built-in Lesson 1 vocabulary and texts. The controls below also select all vocabulary, all texts, or clear the selection.',
        '内蔵の第1課の単語と本文を選びます。下の操作で単語のみ、本文のみをすべて選択したり、選択を解除したりできます。',
      ),
    ),
    _TourStep.order => (
      key: c.orderTarget,
      title: context.tr(
        '调整课程顺序',
        '調整課程順序',
        'Change the lesson order',
        '課の順序を変える',
      ),
      text: context.tr(
        '将课文排到单词前面，先演示词组填答。自己试用时可长按课程卡片拖动排序。',
        '將課文排到單詞前面，先示範詞組填答。自行試用時可長按課程卡片拖曳排序。',
        'Put texts before vocabulary to demonstrate phrase completion first. Hold and drag lesson cards to reorder them when trying it yourself.',
        'まず語句の穴埋めを紹介するため、本文を単語より先にします。自由に試すときは課のカードを長押しして並べ替えられます。',
      ),
    ),
    _TourStep.rules => (
      key: c.rulesTarget,
      title: context.tr(
        '设置听写规则',
        '設定聽寫規則',
        'Set dictation rules',
        '書き取りのルールを設定する',
      ),
      text: context.tr(
        '停顿方式、重复次数、间隔和顺序与正式听写一致。本次使用每句停顿、重复2次、间隔1秒、顺序播放。',
        '停頓方式、重複次數、間隔和順序與正式聽寫一致。本次使用每句停頓、重複2次、間隔1秒、順序播放。',
        'The pause mode, repeat count, gap, and order match regular dictation. This demo pauses after each sentence, repeats twice, waits one second, and plays in order.',
        '通常の書き取りと同じ停止方法、繰り返し回数、間隔、順序を設定できます。今回は文ごとに停止、2回再生、間隔1秒、順番どおりの再生です。',
      ),
    ),
    _TourStep.start => (
      key: c.startTarget,
      title: context.tr('开始听写', '開始聽寫', 'Start dictation', '書き取りを始める'),
      text: context.tr(
        '点击右上角播放按钮，按照选定的课程顺序进入听写。',
        '點選右上角播放按鈕，按照選定的課程順序進入聽寫。',
        'Tap the play button at the top right to start dictation in the selected lesson order.',
        '右上の再生ボタンを押すと、選んだ課の順序で書き取りが始まります。',
      ),
    ),
    _TourStep.listen => (
      key: c.audioTarget,
      title: context.tr('听音并回想', '聽音並回想', 'Listen and recall', '聴いて思い出す'),
      text: context.tr(
        '原文先隐藏。实际录音播放及停顿结束后，课文会出现词组空格。自己试用时可点击这里重听。',
        '原文先隱藏。實際錄音播放及停頓結束後，課文會出現詞組空格。自行試用時可點選這裡重聽。',
        'The text is hidden at first. Phrase blanks appear after the recording and pause finish. Tap here to listen again when trying it yourself.',
        '最初は原文が隠れています。音声と待ち時間が終わると、本文の語句を埋める空欄が表示されます。自由に試すときは、ここを押してもう一度聴けます。',
      ),
    ),
    _TourStep.wrong => (
      key: c.choicesTarget,
      title: context.tr(
        '示范选错词组',
        '示範選錯詞組',
        'Try an incorrect phrase',
        '間違った語句を選んでみる',
      ),
      text: context.tr(
        '先选择一个与当前空格不匹配的词组，观察真实的错误提示。',
        '先選擇一個與目前空格不符的詞組，觀察實際的錯誤提示。',
        'First choose a phrase that does not fit the blank to see the actual error feedback.',
        'まず空欄に合わない語句を選び、間違えたときの表示を確認します。',
      ),
    ),
    _TourStep.correction => (
      key: c.choicesTarget,
      title: context.tr('纠正选择', '修正選擇', 'Correct the selection', '正しい語句を選び直す'),
      text: context.tr(
        '选错的词组显示红色叉号，空格保持不变。接下来选入第一个正确词组。',
        '選錯的詞組顯示紅色叉號，空格保持不變。接下來選入第一個正確詞組。',
        'The incorrect phrase shows a red cross and the blank stays empty. Next, select the first correct phrase.',
        '間違った語句には赤い×が付き、空欄はそのままです。次に最初の正しい語句を選びます。',
      ),
    ),
    _TourStep.reset => (
      key: c.resetTarget,
      title: context.tr('重新填写', '重新填寫', 'Try again', '入力し直す'),
      text: context.tr(
        '已填入第一个词组。点击“重新填写”清空答案；也可点击某个空格单独重填。',
        '已填入第一個詞組。點選「重新填寫」清空答案；也可點選某個空格單獨重填。',
        'The first phrase is filled in. Tap “Try again” to clear the answers, or tap one blank to change only that answer.',
        '最初の語句が入りました。「入力し直す」で回答を消せます。空欄を1つ押すと、その回答だけを入れ直せます。',
      ),
    ),
    _TourStep.answer => (
      key: c.choicesTarget,
      title: context.tr(
        '按原文顺序填答',
        '按原文順序填答',
        'Fill in the original order',
        '原文の順に埋める',
      ),
      text: context.tr(
        '逐个选入正确词组，填满后显示原文和翻译。引导会等待实际播放及填答状态，不跳过播放。',
        '逐一選入正確詞組，填滿後顯示原文和翻譯。引導會等待實際播放及填答狀態，不略過播放。',
        'Choose the correct phrases one by one. Completing them reveals the text and translation. The tour waits for playback and answer entry to finish.',
        '正しい語句を1つずつ選ぶと、すべて埋まった後に原文と訳が表示されます。ガイドは音声再生と回答の完了を待ち、再生を飛ばしません。',
      ),
    ),
    _TourStep.reveal => (
      key: c.audioTarget,
      title: context.tr('核对答案', '核對答案', 'Check the answer', '答えを確認する'),
      text: context.tr(
        '课文全部填对后显示答案。正式流程和自由试用会在3秒后进入下一项；引导暂留此处方便查看。',
        '課文全部填對後顯示答案。正式流程和自由試用會在3秒後進入下一項；引導暫留此處方便查看。',
        'The answer appears once every phrase is correct. Regular dictation and free exploration move on after three seconds; the tour stays here briefly for review.',
        'すべて正しく埋めると答えが表示されます。通常の練習と自由体験では3秒後に次へ進みますが、ガイドでは確認のため少し留まります。',
      ),
    ),
    _TourStep.next => (
      key: c.nextTarget,
      title: context.tr('下一个', '下一個', 'Next', '次へ'),
      text: context.tr(
        '已经进入下一条课文。“下一个”也可以略过当前题；接下来用它进入单词，展示单词的核对方式。',
        '已經進入下一段課文。「下一個」也可以略過目前題目；接下來用它進入單詞，展示單詞的核對方式。',
        'The next text is now open. “Next” can also skip an item. We will use it to reach vocabulary and show how to check individual words.',
        '次の本文に進みました。「次へ」で現在の問題を飛ばすこともできます。続いて単語に進み、単語の確認方法を紹介します。',
      ),
    ),
    _TourStep.words => (
      key: c.audioTarget,
      title: context.tr(
        '单词听写与核对',
        '單詞聽寫與核對',
        'Dictate and check vocabulary',
        '単語の書き取りと確認',
      ),
      text: context.tr(
        '单词在播放与停顿后直接显示原文和翻译，不出现词组填空。引导结束后继续自由试用，设置仅在本次演示有效。',
        '單詞在播放與停頓後直接顯示原文和翻譯，不出現詞組填空。引導結束後可繼續自由試用，設定僅在本次示範有效。',
        'For vocabulary, the word and translation appear after playback and the pause, without phrase blanks. Keep exploring after the tour; settings apply only to this demo.',
        '単語では音声と待ち時間の後に、単語と訳が直接表示されます。語句の穴埋めはありません。ガイド終了後も自由に試せます。設定は今回のデモ内だけで有効です。',
      ),
    ),
  };

  bool get _canAdvance {
    if (!_ready ||
        _failure != null ||
        !_foreground ||
        _busy ||
        _needsFocus ||
        _focusing)
      return false;
    return switch (_step) {
      _TourStep.selection ||
      _TourStep.order ||
      _TourStep.rules ||
      _TourStep.start =>
        s != null && !s!.loading && !s!.savingRule && !s!.choosingBook,
      _TourStep.listen ||
      _TourStep.wrong ||
      _TourStep.correction ||
      _TourStep.reset ||
      _TourStep.answer => p?._canAnswer == true,
      _TourStep.reveal => p?._stage == _DictationStage.revealed,
      _TourStep.next =>
        p != null &&
            !p!._starting &&
            (p!._stage == _DictationStage.answering ||
                p!._stage == _DictationStage.revealed),
      _TourStep.words => p?._stage == _DictationStage.revealed,
    };
  }

  void _tick() {
    if (!mounted || !c.guided || !_foreground || _exiting || _busy) return;
    final error =
        s?.error ?? (p?._stage == _DictationStage.failed ? p?._message : null);
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
    if (!mounted ||
        !c.guided ||
        _paused ||
        !_foreground ||
        _failure != null ||
        _exiting)
      return;
    _advanceTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted ||
          !c.guided ||
          _paused ||
          !_foreground ||
          _failure != null ||
          _exiting) {
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
    removeDemoGuideOverlay(_spotlight);
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
    bool current() =>
        mounted &&
        c.guided &&
        _foreground &&
        revision == _revision &&
        focusRevision == _focusRevision;
    try {
      await Scrollable.ensureVisible(
        target,
        alignment: .5,
        duration: _reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 250),
      ).timeout(const Duration(seconds: 3));
      await WidgetsBinding.instance.endOfFrame;
      if (!current()) return;
      final overlay = _overlayKey.currentState;
      final box = _description.key.currentContext?.findRenderObject();
      final overlayBox = overlay?.context.findRenderObject();
      if (overlay == null ||
          box is! RenderBox ||
          !box.hasSize ||
          overlayBox is! RenderBox) {
        throw StateError('演示位置尚未完成布局');
      }
      final coach = TutorialCoachMark(
        targets: [
          TargetFocus(
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
        pulseEnable: !_paused && !_reducedMotion,
        focusAnimationDuration: Duration(
          milliseconds: _reducedMotion ? 1 : 250,
        ),
        backgroundSemanticLabel: context.tr(
          '听写演示高亮区域',
          '聽寫示範反白區域',
          'Dictation demo highlighted area',
          '書き取りデモの強調領域',
        ),
      );
      _spotlight = coach;
      coach.showWithOverlayState(overlay: overlay);
      await Future<void>.delayed(Duration.zero);
      if (!current() || _spotlight != coach) {
        removeDemoGuideOverlay(coach);
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
      if (mounted && revision == _revision)
        _fail(featureError(e, fallback: '样例读取失败，请重新播放。'));
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
          final wrong = p!._choices.where(
            (i) => p!._phrases[i] != p!._phrases[p!._slot],
          );
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
    setState(() {
      _failure = message;
      _paused = true;
    });
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
    setState(() {
      _paused = true;
      _needsFocus = true;
    });
    try {
      await _stopPractice();
    } catch (_) {
      if (mounted) _fail('样例音频停止失败，请重新播放。');
    }
  }

  Future<void> _resume() async {
    if (_busy || !_foreground || _exiting || !c.guided || _failure != null)
      return;
    final revision = ++_revision;
    _advanceTimer?.cancel();
    _removeSpotlight();
    setState(() {
      _busy = true;
      _needsFocus = true;
    });
    try {
      await _stopPractice();
      if (!mounted || revision != _revision || !_foreground || _exiting) return;
      p?._resumeDemo();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || revision != _revision || !_foreground || _exiting) return;
      await _focus();
      if (!mounted ||
          revision != _revision ||
          !_foreground ||
          _exiting ||
          _failure != null)
        return;
      final preparing =
          p?._stage == _DictationStage.loading ||
          p?._stage == _DictationStage.listening ||
          p?._stage == _DictationStage.waiting;
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

  Future<void> _explore({
    bool completed = false,
    bool fromAdvance = false,
  }) async {
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
      child: LayoutBuilder(
        builder: (context, bounds) => Column(
          children: [
            Expanded(
              child: Overlay(key: _overlayKey, initialEntries: [_page]),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: bounds.maxHeight * .42),
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
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                      : !c.guided
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
                                      : '${_step.index + 1}/${_TourStep.values.length} · ${_description.title}${_paused ? context.tr(' · 已暂停', ' · 已暫停', ' · Paused', ' · 一時停止中') : ''}',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _failure != null
                                    ? demoGuideError(context, _failure!)
                                    : (!c.guided
                                          ? context.tr(
                                              '可以选课、排序、设置规则和练习听写。仅使用内置样例，不保存学习记录。',
                                              '可以選課、排序、設定規則和練習聽寫。僅使用內建範例，不儲存學習紀錄。',
                                              'Choose and reorder lessons, set rules, and practice dictation. Only built-in samples are used; study records are not saved.',
                                              '課の選択、並べ替え、ルール設定、書き取り練習ができます。内蔵サンプルのみを使い、学習記録は保存されません。',
                                            )
                                          : !_ready
                                          ? context.tr(
                                              '正在读取内置内容与样例音频。',
                                              '正在讀取內建內容與範例音訊。',
                                              'Loading built-in content and sample audio.',
                                              '内蔵コンテンツとサンプル音声を読み込み中です。',
                                            )
                                          : _description.text),
                              ),
                              const SizedBox(height: 10),
                              if (c.guided && _ready) ...[
                                LinearProgressIndicator(
                                  value:
                                      (_step.index + 1) /
                                      _TourStep.values.length,
                                ),
                                const SizedBox(height: 10),
                              ],
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (c.guided &&
                                      _ready &&
                                      _failure == null) ...[
                                    StudyButton.filled(
                                      onPressed: _busy
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
                                            !_busy &&
                                                (_canAdvance ||
                                                    p?._stage ==
                                                        _DictationStage.paused)
                                            ? _manualNext
                                            : null,
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
                                  if (!c.guided || _failure != null)
                                    StudyButton.filled(
                                      onPressed: _busy ? null : _restart,
                                      child: Text(
                                        context.tr(
                                          '重新播放',
                                          '重新播放',
                                          'Replay tour',
                                          'ガイドを再生し直す',
                                        ),
                                      ),
                                    ),
                                  if (c.guided)
                                    StudyButton.text(
                                      onPressed: _busy
                                          ? null
                                          : () => _explore(),
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
                                    onPressed: _exit,
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
    ),
  );
}

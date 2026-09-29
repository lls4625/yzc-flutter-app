part of 'page.dart';

String _dictationPlain(String text) => text
    .replaceAllMapped(RegExp(r'!([^!\s()]+)\([^)]*\)'), (m) => m.group(1)!)
    .replaceAll('!', '')
    .trim();

/// The bundled lesson supplies phrase boundaries in its original spacing.
/// Keep those exact boundaries; never route demo text through feature tokenization.
Future<List<String>> _dictationPhrases(String source) async {
  final phrases = _dictationPlain(source)
      .split(RegExp(r'[\s\u3000]+'))
      .where((phrase) => phrase.isNotEmpty)
      .toList();
  if (phrases.length < 2) {
    throw StateError('演示课文缺少词组分隔，请检查内置样例');
  }
  return phrases;
}

class _DictationQuestion {
  const _DictationQuestion(this.card, this.row, this.path, this.text);
  final _DictationCard card;
  final RowData row;
  final String path, text;
}

enum _DictationStage { loading, listening, waiting, answering, revealed, paused, failed, done }

class _DictationPage extends StatefulWidget {
  const _DictationPage(this.controller, this.book, this.queue, {super.key});
  final DictationDemoController controller;
  final RowData book;
  final List<_DictationCard> queue;

  @override
  State<_DictationPage> createState() => _DictationPageState();
}

class _DictationPageState extends State<_DictationPage> with WidgetsBindingObserver {
  final _audio = NativeAudioTransport.instance;
  late final String _identity = '${textOf(widget.book, 'id')}:dictation-demo:${DateTime.now().microsecondsSinceEpoch}';
  late final int _repeats = widget.controller.repeats;
  late final int _interval = widget.controller.interval;
  late final bool _pauseEach = widget.controller.pauseEach;
  late final bool _randomOrder = widget.controller.randomOrder;
  List<_DictationQuestion> _questions = [];
  List<String> _phrases = [];
  List<int> _choices = [];
  List<int?> _filled = [];
  int _index = 0, _epoch = 0, _round = 0, _remaining = 0, _skippedResources = 0;
  int _slot = 0;
  int? _wrongChoice;
  String? _version, _message, _expectedId;
  bool _seenActive = false, _starting = false, _replaying = false;
  Timer? _timer;
  Completer<bool>? _audioDone, _delayDone;
  Future<void>? _startOperation;
  _DictationStage _stage = _DictationStage.loading;

  String get _bookId => textOf(widget.book, 'id');
  bool get _owns => _audio.lesson == _identity;
  bool _current(int epoch) => mounted && epoch == _epoch;
  _DictationQuestion get _question => _questions[_index];
  bool get _canAnswer => _stage == _DictationStage.answering && !_replaying;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audio.addListener(_audioChanged);
    unawaited(_prepare());
  }

  void _cancel() {
    _wrongChoice = null;
    _epoch++;
    _timer?.cancel();
    _timer = null;
    if (_audioDone != null && !_audioDone!.isCompleted) _audioDone!.complete(false);
    if (_delayDone != null && !_delayDone!.isCompleted) _delayDone!.complete(false);
    _audioDone = null;
    _delayDone = null;
    _expectedId = null;
    _seenActive = false;
    _replaying = false;
  }

  Future<void> _stopOwned() async {
    final pending = _startOperation;
    if (pending != null) {
      try { await pending; } catch (_) { /* The playback caller reports errors. */ }
    }
    if (_owns) await _audio.stop();
  }

  void _audioChanged() {
    final done = _audioDone;
    if (done == null || done.isCompleted) return;
    if (_owns && _audio.completedId == _expectedId) {
      done.complete(true);
    } else if (_owns && _audio.error != null) {
      done.completeError(StateError(_audio.error!));
    } else if (_owns && _audio.active) {
      _seenActive = true;
    } else if (_seenActive) {
      done.completeError(StateError('播放已停止，请点击重听继续'));
    }
    if (mounted) setState(() {});
  }

  Future<void> _prepare() async {
    _cancel();
    final epoch = _epoch;
    setState(() { _stage = _DictationStage.loading; _message = null; });
    try {
      final catalog = widget.controller.catalog;
      final version = await catalog.version(_bookId);
      final questions = <_DictationQuestion>[];
      final paths = <String, String>{};
      var skipped = 0;
      for (final card in widget.queue) {
        final rows = await catalog.content(card.words ? 'yzc_words' : 'yzc_content', _bookId, textOf(card.lesson, 'id'));
        if (!_current(epoch)) return;
        for (final row in rows) {
          final text = _dictationPlain(
            textOf(row, card.words ? 'word' : 'content'),
          );
          final filename = textOf(row, 'phonetic');
          if (text.isEmpty || filename.isEmpty) { skipped++; continue; }
          final path = paths[filename] ?? await catalog.audioPath(_bookId, filename);
          if (!_current(epoch)) return;
          paths[filename] = path;
          questions.add(_DictationQuestion(card, row, path, text));
        }
      }
      if (questions.isEmpty) throw StateError('所选课程没有同时包含原文和音频的条目');
      if (version != await catalog.version(_bookId)) throw StateError('内容已更新，请重新读取');
      if (!_current(epoch)) return;
      if (_randomOrder) questions.shuffle(Random());
      _questions = questions;
      _version = version;
      _index = 0;
      _skippedResources = skipped;
      await _begin();
    } catch (e) { _fail(epoch, e); }
  }

  void _fail(int epoch, Object error) {
    if (!_current(epoch)) return;
    setState(() {
      _stage = _DictationStage.failed;
      _replaying = false;
      _message = featureError(error, fallback: '听写准备或播放失败，请重试');
    });
  }

  Future<bool> _play(int epoch) async {
    if (!_current(epoch)) return false;
    if (_version != await widget.controller.catalog.version(_bookId)) {
      throw StateError('内容已更新，请返回课程选择页重新开始');
    }
    if (!_current(epoch)) return false;
    final id = '$_identity:$epoch:$_round:${DateTime.now().microsecondsSinceEpoch}';
    final done = Completer<bool>();
    _audioDone = done;
    // Attach the error handler before the platform can publish an error event.
    final completion = done.future;
    unawaited(completion.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    _expectedId = id;
    _seenActive = false;
    _starting = true;
    Future<void>? start;
    try {
      start = _audio.start({
        'lesson': _identity,
        'title': '${_question.card.course} · 听写演示',
        'albumTitle': '听写演示',
        'words': _question.card.words,
        'batch': false,
        'speed': 1.0,
        'repeat': 1,
        'intervalSteps': 0,
        'clips': [{'id': id, 'path': _question.path}],
        'startIndex': 0,
      });
      _startOperation = start;
      await start;
      _starting = false;
      if (!_current(epoch)) return false;
      _audioChanged();
      return await completion.timeout(const Duration(seconds: 45),
        onTimeout: () => throw StateError('样例播放超时，请重试 / 重听'));
    } finally {
      if (identical(_startOperation, start)) _startOperation = null;
      _starting = false;
      if (identical(_audioDone, done)) { _audioDone = null; _expectedId = null; }
    }
  }

  Future<bool> _delay(int seconds, int epoch) {
    if (!_current(epoch)) return Future.value(false);
    if (seconds == 0) return Future.value(true);
    final done = Completer<bool>();
    _delayDone = done;
    setState(() => _remaining = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_current(epoch)) { timer.cancel(); if (!done.isCompleted) done.complete(false); return; }
      setState(() => _remaining--);
      if (_remaining <= 0) { timer.cancel(); if (!done.isCompleted) done.complete(true); }
    });
    return done.future;
  }

  Future<void> _begin() async {
    _cancel();
    final epoch = _epoch;
    setState(() {
      _stage = _DictationStage.listening;
      _message = null;
      _phrases = [];
      _choices = [];
      _filled = [];
      _slot = 0;
    });
    try {
      await _stopOwned();
      if (!_current(epoch)) return;
      for (var round = 1; round <= _repeats; round++) {
        setState(() { _stage = _DictationStage.listening; _round = round; });
        if (!await _play(epoch) || !_current(epoch)) return;
        if (_pauseEach || round == _repeats) {
          setState(() => _stage = _DictationStage.waiting);
          if (!await _delay(_interval, epoch) || !_current(epoch)) return;
        }
      }
      if (_question.card.words) {
        await _reveal(epoch);
      } else {
        final phrases = await _dictationPhrases(textOf(_question.row, 'content'));
        if (!_current(epoch)) return;
        final choices = List<int>.generate(phrases.length, (i) => i)..shuffle(Random());
        if (choices.length > 1 && choices.every((i) => choices[i] == i)) {
          choices.add(choices.removeAt(0));
        }
        setState(() {
          _phrases = phrases;
          _filled = List<int?>.filled(phrases.length, null);
          _choices = choices;
          _stage = _DictationStage.answering;
        });
      }
    } catch (e) { _fail(epoch, e); }
  }

  Future<void> _reveal(int epoch) async {
    if (!_current(epoch)) return;
    setState(() { _stage = _DictationStage.revealed; _message = null; });
    if (widget.controller.guided) return;
    if (await _delay(3, epoch) && _current(epoch)) await _next();
  }

  Future<void> _next() async {
    _cancel();
    final epoch = _epoch;
    try {
      await _stopOwned();
      if (!_current(epoch)) return;
      if (_index + 1 >= _questions.length) {
        setState(() => _stage = _DictationStage.done);
      } else {
        _index++;
        await _begin();
      }
    } catch (e) { _fail(epoch, e); }
  }

  Future<void> _replay() async {
    if (_starting || _replaying || _questions.isEmpty) return;
    if (_stage != _DictationStage.answering && _stage != _DictationStage.revealed && _filled.isEmpty) {
      await _begin();
      return;
    }
    final wasRevealed = _stage == _DictationStage.revealed ||
        (_filled.isNotEmpty && _filled.every((i) => i != null) &&
          List.generate(_filled.length, (i) => _phrases[_filled[i]!] == _phrases[i]).every((v) => v));
    _cancel();
    final epoch = _epoch;
    setState(() { _replaying = true; _message = null; });
    try {
      await _stopOwned();
      if (!await _play(epoch) || !_current(epoch)) return;
      setState(() { _replaying = false; _stage = wasRevealed ? _DictationStage.revealed : _DictationStage.answering; });
      if (wasRevealed) await _reveal(epoch);
    } catch (e) { _fail(epoch, e); }
  }

  void _fill(int choice) {
    if (!_canAnswer || _filled.contains(choice)) return;
    if (_phrases[choice] != _phrases[_slot]) {
      setState(() => _wrongChoice = choice);
      return;
    }
    setState(() {
      _wrongChoice = null;
      _filled[_slot] = choice;
      _message = null;
      final empty = _filled.indexOf(null);
      if (empty >= 0) _slot = empty;
    });
    if (_filled.any((i) => i == null)) return;
    unawaited(_reveal(_epoch));
  }

  Widget _fourColumns(List<Widget> children, {Key? key}) => LayoutBuilder(
    key: key,
    builder: (context, bounds) => Wrap(
      spacing: 8,
      runSpacing: 10,
      children: [
        for (final child in children)
          SizedBox(width: (bounds.maxWidth - 24) / 4, child: child),
      ],
    ),
  );

  Widget _choiceLabel(int choice) => Semantics(
    liveRegion: _wrongChoice == choice,
    label: _wrongChoice == choice ? '${_phrases[choice]}，选择错误' : null,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_phrases[choice], style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP')), textAlign: TextAlign.center),
      if (_wrongChoice == choice)
        Icon(Icons.cancel_rounded, size: 18, color: Theme.of(context).colorScheme.error),
    ]),
  );

  Future<void> _suspend() async {
    final running = _stage == _DictationStage.loading ||
        _stage == _DictationStage.listening || _stage == _DictationStage.waiting ||
        (_stage == _DictationStage.revealed && !widget.controller.guided) || _replaying;
    final wrongChoice = _wrongChoice;
    _cancel();
    if (_stage == _DictationStage.answering) _wrongChoice = wrongChoice;
    if (mounted && running) setState(() => _stage = _DictationStage.paused);
    await _stopOwned();
  }

  void _resumeDemo() {
    if (_stage == _DictationStage.paused) {
      unawaited(_questions.isEmpty ? _prepare() : _replay());
    } else if (_stage == _DictationStage.revealed && !widget.controller.guided) {
      unawaited(_reveal(_epoch));
    }
  }

  void _clearAnswer() => setState(() {
    _filled = List<int?>.filled(_phrases.length, null);
    _slot = 0;
    _message = null;
    _wrongChoice = null;
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_suspend().catchError((Object e) {
        if (mounted) _fail(_epoch, e);
      }));
    }
  }

  @override
  void dispose() {
    _cancel();
    WidgetsBinding.instance.removeObserver(this);
    _audio.removeListener(_audioChanged);
    unawaited(_stopOwned().catchError((Object _) {}));
    super.dispose();
  }

  String get _status {
    if (_replaying) return '正在重听原文';
    if (_owns && _audio.active && _audio.paused) return '播放已暂停，点击继续朗读';
    return switch (_stage) {
      _DictationStage.loading => '正在准备听写',
      _DictationStage.listening => '请仔细听 · 第 $_round / $_repeats 遍',
      _DictationStage.waiting => '请回想刚才的内容 · $_remaining 秒',
      _DictationStage.answering => '点击词组，按原文顺序填入空格',
      _DictationStage.revealed => widget.controller.guided
          ? (_question.card.words ? '核对单词' : '回答正确')
          : _question.card.words ? '核对单词 · $_remaining 秒后下一项' : '回答正确 · $_remaining 秒后下一项',
      _DictationStage.paused => '已暂停，点击重听继续',
      _DictationStage.failed => '当前题暂不可用',
      _DictationStage.done => '本次听写已完成',
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasQuestion = _questions.isNotEmpty && _stage != _DictationStage.done;
    return DictationDemoScaffold(
      controlledLesson: _identity,
      appBar: StudyAppBar(centerTitle: true, title: const Text('听写 · 演示')),
      body: _stage == _DictationStage.loading
          ? const Center(child: StudyCircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (hasQuestion) Text('${_question.card.course} · ${_question.card.label}　${_index + 1} / ${_questions.length}'),
                const SizedBox(height: 12),
                Text('${_pauseEach ? '每句停顿' : '整体停顿'} · 重复 $_repeats 次 · 间隔 $_interval 秒', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 24),
                Semantics(liveRegion: true, child: Text(_status, textAlign: TextAlign.center)),
                const SizedBox(height: 16),
                if (hasQuestion) StudyPanel(
                  key: widget.controller.audioTarget,
                  child: StudyInkWell(
                    onTap: _starting ? null : () {
                      if (_owns && _audio.active && _audio.paused) {
                        unawaited(perform(context, _audio.resume));
                      } else { unawaited(_replay()); }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _DictationSpeaker(identity: _identity),
                        const SizedBox(height: 12),
                        if (_stage == _DictationStage.revealed) ...[
                          Text(_question.text, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'), fontSize: 26)),
                          const SizedBox(height: 8),
                          Text(textOf(_question.row, 'definition'), style: const TextStyle(fontFamily: 'PingFang SC', locale: Locale('zh', 'CN')), textAlign: TextAlign.center),
                        ] else const Text('原文已隐藏 · 点击重听'),
                      ]),
                    ),
                  ),
                ),
                if (_stage == _DictationStage.answering) ...[
                  const SizedBox(height: 24),
                  _fourColumns([
                    for (var i = 0; i < _filled.length; i++) StudyButton.outlined(
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12)),
                      onPressed: !_canAnswer ? null : () => setState(() { _filled[i] = null; _slot = i; _message = null; _wrongChoice = null; }),
                      child: Text(_filled[i] == null ? '${i + 1} ${_slot == i ? '▸' : '＿'}' : _phrases[_filled[i]!], style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP')), textAlign: TextAlign.center),
                    ),
                  ], key: widget.controller.slotsTarget),
                  const SizedBox(height: 24),
                  _fourColumns([
                    for (final choice in _choices) StudyButton.filled(
                      onPressed: !_canAnswer || _filled.contains(choice) ? null : () => _fill(choice),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12)),
                      child: _choiceLabel(choice),
                    ),
                  ], key: widget.controller.choicesTarget),
                ],
                if (_message != null) Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Semantics(liveRegion: true, child: Text(_message!, style: TextStyle(color: scheme.error))),
                ),
                if (_stage == _DictationStage.failed || _stage == _DictationStage.paused) StudyButton.filled(
                  onPressed: () => _questions.isEmpty ? _prepare() : _replay(),
                  child: const Text('重试 / 重听'),
                ),
                if (_skippedResources > 0) Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text('已略过 $_skippedResources 条无原文或无音频的内容', style: Theme.of(context).textTheme.bodySmall),
                ),
                if (_stage == _DictationStage.done) StudyButton.filled(onPressed: () => Navigator.pop(context), child: const Text('返回课程选择')),
              ]),
            ),
      bottomNavigationBar: !hasQuestion ? null : SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: StudyButton.outlined(
                  key: widget.controller.nextTarget,
                  onPressed: () => unawaited(_next()),
                  child: const Text('下一个'),
                ),
              ),
              if (!_question.card.words) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: StudyButton.outlined(
                    key: widget.controller.resetTarget,
                    onPressed: !_canAnswer ? null : _clearAnswer,
                    child: const Text('重新填写'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DictationSpeaker extends StatefulWidget {
  const _DictationSpeaker({required this.identity});
  final String identity;

  @override
  State<_DictationSpeaker> createState() => _DictationSpeakerState();
}

class _DictationSpeakerState extends State<_DictationSpeaker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 750),
  );
  final _transport = NativeAudioTransport.instance;
  bool get _playing => _transport.lesson == widget.identity && _transport.isPlaying;

  @override
  void initState() {
    super.initState();
    _transport.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    if (_playing && !MediaQuery.disableAnimationsOf(context)) {
      if (!_animation.isAnimating) _animation.repeat();
    } else {
      _animation.stop();
      _animation.value = 0;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _transport.removeListener(_sync);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: _playing ? '正在朗读' : '朗读已停止或暂停',
    child: AnimatedBuilder(
      animation: _animation,
      builder: (context, _) => Icon(
        !_playing ? Icons.volume_up_rounded
            : _animation.value < 1 / 3 ? Icons.volume_mute_rounded
            : _animation.value < 2 / 3 ? Icons.volume_down_rounded
            : Icons.volume_up_rounded,
        size: 38,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

import '../../../system_errors.dart';
part of 'dictation.dart';

String _dictationPlain(String text) => text
    .replaceAllMapped(RegExp(r'!([^!\s()]+)\([^)]*\)'), (m) => m.group(1)!)
    .trim();

/// Keeps textbook spacing first; native tokens are only a fallback for unspaced text.
Future<List<String>> _dictationPhrases(String source) async {
  final text = _dictationPlain(source);
  // Ruby annotations describe intact textbook surfaces. Protect their internal
  // boundaries before adding particles, rather than losing them during cleanup.
  final protectedBoundaries = <int>{};
  for (final match in RegExp(r'!([^!\s()]+)\([^)]*\)').allMatches(source)) {
    final surface = match.group(1)!;
    var offset = text.indexOf(surface);
    while (offset >= 0) {
      for (var i = offset + 1; i < offset + surface.length; i++) {
        protectedBoundaries.add(i);
      }
      offset = text.indexOf(surface, offset + surface.length);
    }
  }
  final spaced = text.split(RegExp(r'[\s\u3000]+')).where((s) => s.isNotEmpty).toList();
  if (spaced.length > 1) return spaced;
  const channel = MethodChannel('yuzhichu/dictation_tokenizer');
  final tokens = await channel.invokeListMethod<String>('tokenize', text);
  if (tokens == null || tokens.isEmpty || tokens.join() != text) {
    throw StateError('日文拆分失败，请重试或跳过当前题');
  }
  final intactTokens = <String>[];
  var offset = 0;
  for (final token in tokens) {
    if (intactTokens.isNotEmpty && protectedBoundaries.contains(offset)) {
      intactTokens[intactTokens.length - 1] += token;
    } else {
      intactTokens.add(token);
    }
    offset += token.length;
  }
  const particles = {'は', 'が', 'を', 'に', 'へ', 'で', 'と', 'の', 'も', 'から', 'まで', 'より'};
  const endings = {'です', 'ます', 'でした', 'ました', 'ません', 'ない', 'たい'};
  final result = <String>[];
  for (final token in intactTokens) {
    final punctuation = RegExp(r'^[、。！？!?…」』）)]+$').hasMatch(token);
    final tail = {'か', 'ね', 'よ', 'た', 'ん', 'でした'}.contains(token) &&
        result.isNotEmpty && RegExp(r'(です|ます|でし|まし|ませ|ません|ない|たい)$').hasMatch(result.last);
    if (result.isNotEmpty && (particles.contains(token) || punctuation || tail)) {
      result[result.length - 1] += token;
    } else if (result.isNotEmpty && endings.contains(token) &&
        RegExp(r'(し|き|み|り|べ|び|い|っ)$').hasMatch(result.last) && token != 'です') {
      result[result.length - 1] += token;
    } else {
      result.add(token);
    }
  }
  return result;
}

// Sentence punctuation is visible scaffolding, never an answer choice.
// Keep Japanese long vowels (ー), iteration marks and word-internal middle dots.
final _dictationPunctuation = RegExp(r'''[、。，．,.！？!?：:；;…‥「」『』（）()［］\[\]｛｝{}〈〉《》【】〔〕“”‘’"'«»]''');

class _DictationBlankPart {
  const _DictationBlankPart.word(this.slot) : punctuation = '';
  const _DictationBlankPart.punctuation(this.punctuation) : slot = null;
  final int? slot;
  final String punctuation;
}

void _dictationSeparatePunctuation(
  List<String> chunks, List<String> phrases, List<_DictationBlankPart> body,
) {
  void addWord(String text) {
    final word = text.trim();
    if (word.isEmpty) return;
    body.add(_DictationBlankPart.word(phrases.length));
    phrases.add(word);
  }
  for (final chunk in chunks) {
    var offset = 0;
    for (final match in _dictationPunctuation.allMatches(chunk)) {
      addWord(chunk.substring(offset, match.start));
      body.add(_DictationBlankPart.punctuation(match.group(0)!));
      offset = match.end;
    }
    addWord(chunk.substring(offset));
  }
}

class _DictationQuestion {
  const _DictationQuestion(this.card, this.row, this.path, this.text);
  final _DictationCard card;
  final RowData row;
  final String path, text;
}

enum _DictationStage { loading, listening, waiting, answering, revealed, paused, failed, done }

class _DictationPage extends StatefulWidget {
  const _DictationPage(this.controller, this.book, this.queue);
  final DictationController controller;
  final RowData book;
  final List<_DictationCard> queue;

  @override
  State<_DictationPage> createState() => _DictationPageState();
}

class _DictationPageState extends State<_DictationPage> with WidgetsBindingObserver {
  final _audio = NativeAudioTransport.instance;
  late final String _identity = '${textOf(widget.book, 'id')}:dictation:${DateTime.now().microsecondsSinceEpoch}';
  late final int _repeats = widget.controller.repeats;
  late final int _interval = widget.controller.interval;
  late final bool _pauseEach = widget.controller.pauseEach;
  late final bool _randomOrder = widget.controller.randomOrder;
  List<_DictationQuestion> _questions = [];
  List<String> _phrases = [];
  List<_DictationBlankPart> _blankBody = [];
  List<int> _choices = [];
  List<int?> _filled = [];
  int _index = 0, _epoch = 0, _round = 0, _remaining = 0, _skippedResources = 0;
  int _slot = 0;
  int? _wrongChoice;
  String? _version, _message, _expectedId;
  bool _seenActive = false, _starting = false, _replaying = false;
  Timer? _timer;
  Completer<bool>? _audioDone, _delayDone;
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
    widget.controller.host.changes.addListener(_resourcesChanged);
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
    if (_owns || _starting) await _audio.stop();
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

  void _resourcesChanged() {
    if (!widget.controller.access.available || widget.controller.host.isBookUnavailable(_bookId)) {
      _cancel();
      unawaited(_stopOwned().catchError((Object e, StackTrace stack) { SystemErrors.record(e, stack, module: 'dictation', operation: '停止听写音频'); }));
      if (mounted) setState(() {
        _stage = _DictationStage.failed;
        _message = '内容或自习室暂不可用，请返回课程选择页';
      });
    }
  }

  Future<void> _prepare() async {
    _cancel();
    final epoch = _epoch;
    setState(() { _stage = _DictationStage.loading; _message = null; });
    try {
      if (!widget.controller.access.available) throw StateError('自习室暂未解锁');
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
    } catch (e, caughtStack) {
      SystemErrors.record(e, caughtStack, module: 'dictation', operation: '听写练习', context: {'source': 'study_room/dictation/feature/practice.dart'}); _fail(epoch, e); }
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
    if (!widget.controller.access.available) throw StateError('自习室暂未解锁');
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
    try {
      await _audio.start({
        'lesson': _identity,
        'title': '${_question.card.course} · 听写',
        'albumTitle': '听写',
        'words': _question.card.words,
        'batch': false,
        'speed': 1.0,
        'repeat': 1,
        'intervalSteps': 0,
        'clips': [{'id': id, 'path': _question.path}],
        'startIndex': 0,
      });
      _starting = false;
      if (!_current(epoch)) return false;
      _audioChanged();
      return await completion;
    } finally {
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
      _blankBody = [];
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
        final chunks = await _dictationPhrases(textOf(_question.row, 'content'));
        final phrases = <String>[];
        final body = <_DictationBlankPart>[];
        _dictationSeparatePunctuation(chunks, phrases, body);
        if (!_current(epoch)) return;
        if (phrases.isEmpty) {
          await _reveal(epoch);
          return;
        }
        final choices = List<int>.generate(phrases.length, (i) => i)..shuffle(Random());
        if (choices.length > 1 && choices.every((i) => choices[i] == i)) {
          choices.add(choices.removeAt(0));
        }
        setState(() {
          _phrases = phrases;
          _blankBody = body;
          _filled = List<int?>.filled(phrases.length, null);
          _choices = choices;
          _stage = _DictationStage.answering;
        });
      }
    } catch (e, caughtStack) {
      SystemErrors.record(e, caughtStack, module: 'dictation', operation: '听写练习', context: {'source': 'study_room/dictation/feature/practice.dart'}); _fail(epoch, e); }
  }

  Future<void> _reveal(int epoch) async {
    if (!_current(epoch)) return;
    setState(() { _stage = _DictationStage.revealed; _message = null; });
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
    } catch (e, caughtStack) {
      SystemErrors.record(e, caughtStack, module: 'dictation', operation: '听写练习', context: {'source': 'study_room/dictation/feature/practice.dart'}); _fail(epoch, e); }
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
    } catch (e, caughtStack) {
      SystemErrors.record(e, caughtStack, module: 'dictation', operation: '听写练习', context: {'source': 'study_room/dictation/feature/practice.dart'}); _fail(epoch, e); }
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

  Widget _fourColumns(List<Widget> children) => LayoutBuilder(
    builder: (context, bounds) => Wrap(
      spacing: 8,
      runSpacing: 10,
      children: [
        for (final child in children)
          SizedBox(width: (bounds.maxWidth - 24) / 4, child: child),
      ],
    ),
  );

  Widget _blankButton(int i) => StudyButton.outlined(
    style: TextButton.styleFrom(
      minimumSize: const Size(64, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    onPressed: !_canAnswer ? null : () => setState(() {
      _filled[i] = null;
      _slot = i;
      _message = null;
      _wrongChoice = null;
    }),
    child: Text(_filled[i] == null
      ? '${i + 1} ${_slot == i ? '▸' : '＿'}'
      : _phrases[_filled[i]!], style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP')), textAlign: TextAlign.center),
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || _stage == _DictationStage.done || _stage == _DictationStage.failed) return;
    _cancel();
    unawaited(_stopOwned().catchError((Object e, StackTrace stack) { SystemErrors.record(e, stack, module: 'dictation', operation: '停止听写音频'); }));
    if (mounted) setState(() => _stage = _DictationStage.paused);
  }

  @override
  void dispose() {
    _cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.host.changes.removeListener(_resourcesChanged);
    _audio.removeListener(_audioChanged);
    unawaited(_stopOwned().catchError((Object e, StackTrace stack) { SystemErrors.record(e, stack, module: 'dictation', operation: '停止听写音频'); }));
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
      _DictationStage.revealed => _question.card.words ? '核对单词 · $_remaining 秒后下一项' : '回答正确 · $_remaining 秒后下一项',
      _DictationStage.paused => '已暂停，点击重听继续',
      _DictationStage.failed => '当前题暂不可用',
      _DictationStage.done => '本次听写已完成',
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasQuestion = _questions.isNotEmpty && _stage != _DictationStage.done;
    return DictationScaffold(
      controlledLesson: _identity,
      appBar: StudyAppBar(centerTitle: true, title: const Text('听写')),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final part in _blankBody)
                        if (part.slot == null)
                          Text(part.punctuation, style: Theme.of(context).textTheme.titleLarge)
                        else _blankButton(part.slot!),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _fourColumns([
                    for (final choice in _choices) StudyButton.filled(
                      onPressed: !_canAnswer || _filled.contains(choice) ? null : () => _fill(choice),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12)),
                      child: _choiceLabel(choice),
                    ),
                  ]),
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
                  onPressed: () => unawaited(_next()),
                  child: const Text('下一个'),
                ),
              ),
              if (!_question.card.words) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: StudyButton.outlined(
                    onPressed: !_canAnswer ? null : () => setState(() {
                      _filled = List<int?>.filled(_phrases.length, null);
                      _slot = 0;
                      _message = null;
                      _wrongChoice = null;
                    }),
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

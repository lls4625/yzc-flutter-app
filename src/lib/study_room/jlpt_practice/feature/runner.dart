import '../../../system_errors.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../glass_ui.dart';
import 'models.dart';
import 'question_view.dart';
import 'listening_question.dart';
import 'repository.dart';
import 'result.dart';

// This is the practice module's own runner, independently maintained.

enum _FinishAction { cancel, answerMissing, submit }

class AttemptPage extends StatefulWidget {
  const AttemptPage(this.repository, this.attempt, {super.key});
  final JlptRepository repository;
  final Attempt attempt;
  @override
  State<AttemptPage> createState() => _AttemptPageState();
}

class _AttemptPageState extends State<AttemptPage> with WidgetsBindingObserver {
  final _watch = Stopwatch();
  final _questionScrollController = ScrollController();
  final _explanationKey = GlobalKey();
  Timer? _timer;
  bool _paused = true, _busy = false, _canPop = false, _saveFailed = false;
  bool _submitting = false, _submissionFailed = false;
  Future<void> _writes = Future.value();
  int _ticks = 0;
  Attempt get a => widget.attempt;
  Question get q => a.questions[a.position];
  String get _clock => 'practice';
  List<int> get _positions => List.generate(a.questions.length, (i) => i);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _paused || a.submitted) return;
      setState(() {});
      if (++_ticks % 5 == 0) _save();
    });
  }

  void _account() {
    if (_watch.isRunning) {
      a.elapsed[_clock] = (a.elapsed[_clock] as int? ?? 0) + _watch.elapsedMilliseconds;
      _watch.reset();
    }
  }

  Future<void> _save() async {
    if (_submitting) return;
    await _writeProgress();
  }

  Future<bool> _writeProgress({bool submit = false}) async {
    _account();
    final payload = jsonEncode({...a.progress, if (submit) 'submitted': true});
    final submitted = submit || a.submitted;
    var saved = false;
    final write = _writes.then((_) async {
      try {
        await widget.repository.save(a.id, payload, submitted);
        saved = true;
        if (mounted && _saveFailed) setState(() => _saveFailed = false);
      } catch (caughtError, caughtStack) {
      SystemErrors.record(caughtError, caughtStack, module: 'jlpt_practice', operation: '保存答题进度', context: {'source': 'study_room/jlpt_practice/feature/runner.dart'});
        if (mounted) setState(() => _saveFailed = true);
      }
    });
    _writes = write;
    await write;
    return saved;
  }

  Future<void> _submitAnswers() async {
    if (_submitting || a.submitted) return;
    _account(); _watch.stop();
    setState(() {
      _paused = true;
      _busy = true;
      _submitting = true;
      _submissionFailed = false;
    });
    final saved = await _writeProgress(submit: true);
    if (saved) a.progress['submitted'] = true;
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _busy = false;
      _submissionFailed = !saved;
    });
  }

  Widget _submissionStatus(BuildContext context) => Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Column(children: [
      if (_submitting) const CircularProgressIndicator()
      else Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
      const SizedBox(height: 20),
      Text(_submitting ? '正在提交' : '提交未保存',
        style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      Text(_submitting ? '计时已暂停，保存成功后显示结果。'
        : '计时已暂停，当前答案仍保留在本页。请重试提交，或返回作答后再提交。',
        textAlign: TextAlign.center),
      if (!_submitting) ...[
        const SizedBox(height: 24),
        Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
          StudyButton.filled(onPressed: _busy ? null : _submitAnswers, child: const Text('重试提交')),
          StudyButton.outlined(onPressed: _busy ? null : () {
            setState(() { _submissionFailed = false; _paused = false; });
            _watch.start();
          }, child: const Text('返回作答')),
        ]),
      ],
    ]),
  ));

  void _pause() {
    _account(); _watch.stop();
    if (mounted) setState(() => _paused = true);
    unawaited(_save());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !a.submitted) _pause();
  }

  Future<void> _leave() async {
    if (_busy) return;
    _busy = true;
    _pause();
    await _save();
    if (!mounted) return;
    _busy = false;
    if (_saveFailed) return;
    setState(() => _canPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  void _move(int position) {
    _account();
    setState(() => a.position = position);
    unawaited(_save());
  }

  void _answer(String value) {
    setState(() => a.answers[q.id] = value);
    unawaited(_save());
  }

  void _revealAnswerAndExplanation() {
    setState(() => a.revealed.add(q.id));
    unawaited(_save());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final explanationContext = _explanationKey.currentContext;
      if (!mounted || !_questionScrollController.hasClients ||
          explanationContext == null) return;
      final explanation = explanationContext.findRenderObject();
      if (explanation == null) return;
      unawaited(_questionScrollController.position.ensureVisible(explanation,
        alignment: 0,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut));
    });
  }

  Future<_FinishAction> _confirm(String title, String message, String action,
      {required bool hasMissing}) async =>
    await showGlassDialog<_FinishAction>(context: context, builder: (context) => GlassAlertDialog(
      title: Text(title), content: Text(message), actions: [
        StudyButton.text(onPressed: () => Navigator.pop(context, _FinishAction.cancel), child: const Text('继续作答')),
        if (hasMissing) StudyButton.outlined(
          onPressed: () => Navigator.pop(context, _FinishAction.answerMissing), child: const Text('去补答')),
        StudyButton.filled(onPressed: () => Navigator.pop(context, _FinishAction.submit), child: Text(action)),
      ],
    )) ?? _FinishAction.cancel;

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    final missing = _positions.where((i) => !a.answers.containsKey(a.questions[i].id)).toList();
    final confirmed = await _confirm('提交练习',
      missing.isEmpty ? '全部题目已作答。提交后生成结果与解析。'
        : '还有 ${missing.length} 题未答。提交后生成结果与解析。', '提交',
      hasMissing: missing.isNotEmpty);
    if (!mounted) return;
    if (confirmed == _FinishAction.answerMissing && missing.isNotEmpty) {
      _move(missing.first);
    } else if (confirmed == _FinishAction.submit) {
      await _submitAnswers();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _answerCard() async {
    final positions = _positions;
    final chosen = await showModalBottomSheet<int>(context: context,
      isScrollControlled: true, builder: (context) => SafeArea(child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('答题卡 · 实心为已答，旗帜为标记')),
          Expanded(child: GridView.builder(padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 80, mainAxisSpacing: 8, crossAxisSpacing: 8),
            itemCount: positions.length, itemBuilder: (context, index) {
              final position = positions[index]; final item = a.questions[position];
              return StudyButton.outlined(style: OutlinedButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.all(4),
                backgroundColor: a.answers.containsKey(item.id)
                    ? Theme.of(context).colorScheme.primaryContainer : null),
                onPressed: () => Navigator.pop(context, position),
                child: Text('${position + 1}${a.flags.contains(item.id) ? ' ⚑' : ''}'));
            })),
        ]),
      )));
    if (chosen != null && mounted) _move(chosen);
  }

  String get _timeLabel {
    final used = (a.elapsed[_clock] as int? ?? 0) + _watch.elapsedMilliseconds;
    var seconds = used ~/ 1000;
    String prefix = '用时';
    return '$prefix ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _canPop,
    onPopInvokedWithResult: (didPop, _) { if (!didPop) unawaited(_leave()); },
    child: Scaffold(
      appBar: StudyAppBar(centerTitle: true, title: Text(a.submitted ? '结果与回顾' : '${a.level} 专项练习'),
        actions: [if (!a.submitted) StudyIconButton(tooltip: '暂停并保存',
          onPressed: _busy || _submissionFailed ? null : _pause, icon: const Icon(Icons.pause_circle_outline))]),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860), child: Column(children: [
        if (_saveFailed && !_submitting && !_submissionFailed) MaterialBanner(content: const Text('进度保存失败，请重试后再退出。'),
          actions: [StudyButton.text(onPressed: _busy ? null : () => unawaited(_save()), child: const Text('重试保存'))]),
        Expanded(child: a.submitted ? ResultView(a, resolveMedia: widget.repository.mediaPath)
          : _submitting || _submissionFailed ? _submissionStatus(context)
          : _paused ? _ready(context) : _body(context)),
      ])))),
    ),
  );

  Widget _ready(BuildContext context) => Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(28), child: Column(children: [
      const Icon(Icons.menu_book_outlined, size: 56), const SizedBox(height: 20),
      Text(a.title,
        style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: 12), Text('本部分 ${_positions.length} 题 · $_timeLabel'),
      const SizedBox(height: 16),
      const Text('准备好后开始计时。暂停、退出或切到后台不计时。练习不限时，可按自己的节奏作答。', textAlign: TextAlign.center),
      if (q.listening) const Padding(padding: EdgeInsets.only(top: 12),
        child: Text('听力按题目播放配套音频；未提供音频的题目可查看文字稿。')),
      const SizedBox(height: 24), StudyButton.filledIcon(onPressed: _busy ? null : () {
        setState(() => _paused = false); _watch.start();
      }, icon: const Icon(Icons.play_arrow), label: const Text('开始 / 继续作答')),
    ]),
  ));

  Widget _body(BuildContext context) {
    final positions = _positions;
    final localIndex = positions.indexOf(a.position);
    final answered = positions.where((i) => a.answers.containsKey(a.questions[i].id)).length;
    return Column(children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(children: [Expanded(child: Text(q.typeName)), Text(_timeLabel)])),
      LinearProgressIndicator(value: answered / positions.length),
      Padding(padding: const EdgeInsets.fromLTRB(12, 12, 8, 4), child: Row(children: [
        Expanded(child: Text('第 ${a.position + 1} 题 · 本部分已答 $answered/${positions.length}')),
        StudyIconButton(tooltip: a.flags.contains(q.id) ? '取消标记' : '标记本题',
          icon: Icon(a.flags.contains(q.id) ? Icons.flag : Icons.outlined_flag), onPressed: () {
            setState(() { a.flags.contains(q.id) ? a.flags.remove(q.id) : a.flags.add(q.id); });
            unawaited(_save());
          }),
        const SizedBox(width: 8),
        StudyIconButton(tooltip: '答题卡', onPressed: _answerCard, icon: const Icon(Icons.grid_view)),
      ])),
      Expanded(child: SingleChildScrollView(key: ValueKey(a.position),
        controller: _questionScrollController,
        padding: const EdgeInsets.all(20), child: Column(children: [
          if (q.listening) ListeningQuestion(key: ValueKey(q.id), question: q,
            resolveMedia: widget.repository.mediaPath,
            answer: a.answers[q.id] as String?, onAnswer: _busy ? null : _answer,
            review: a.revealed.contains(q.id), explanationKey: _explanationKey, onHelp: (kind) {
              final ids = a.progress.putIfAbsent(kind, () => <String>[]) as List;
              if (!ids.contains(q.id)) ids.add(q.id);
              unawaited(_save());
            })
          else QuestionView(question: q, answer: a.answers[q.id] as String?,
            review: a.revealed.contains(q.id),
            explanationKey: _explanationKey,
            onAnswer: _busy ? null : _answer),
          if (!a.revealed.contains(q.id)) ...[
            StudyButton.text(
              onPressed: _revealAnswerAndExplanation,
              child: const Text('查看答案与解析')),
            if (a.answers.containsKey(q.id)) const SizedBox(height: 8),
          ],
          if (a.answers.containsKey(q.id)) StudyButton.text(onPressed: _busy ? null : () {
            setState(() => a.answers.remove(q.id)); unawaited(_save());
          }, child: const Text('清除本题答案')),
        ]))),
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        if (localIndex < positions.length - 1)
          StudyButton.filled(onPressed: _busy ? null : () => _move(positions[localIndex + 1]), child: const Text('下一题'))
        else StudyButton.filled(onPressed: _busy ? null : _finish, child: const Text('提交练习')),
        const Spacer(),
        StudyButton.outlined(onPressed: _busy || localIndex == 0 ? null : () => _move(positions[localIndex - 1]), child: const Text('上一题')),
      ])),
    ]);
  }

  @override
  void dispose() {
    _timer?.cancel(); _watch.stop();
    _questionScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

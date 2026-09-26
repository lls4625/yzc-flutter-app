import '../../../system_errors.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../glass_ui.dart';
import 'models.dart';
import 'controller.dart';
import 'question_view.dart';
import 'listening_question.dart';
import 'repository.dart';
import 'result.dart';

// This is the test module's own runner, independently maintained.
const _phaseLabels = ['前部 · 文字词汇', '中部 · 语法与阅读', '后部 · 听力'];

enum _FinishAction { cancel, answerMissing, submit }

class AttemptPage extends StatefulWidget {
  const AttemptPage(this.repository, this.attempt, {super.key, required this.controller});
  final JlptDemoController controller;
  final JlptRepository repository;
  final Attempt attempt;
  @override
  State<AttemptPage> createState() => _AttemptPageState();
}

class _AttemptPageState extends State<AttemptPage> with WidgetsBindingObserver {
  bool _demoTranscript = false;
  final _watch = Stopwatch();
  Timer? _timer;
  bool _paused = true, _busy = false, _canPop = false, _saveFailed = false;
  bool _submitting = false, _submissionFailed = false;
  Future<void> _writes = Future.value();
  int _ticks = 0;
  Attempt get a => widget.attempt;
  Question get q => a.questions[a.position];
  String get _clock => q.clock;
  int get _nextPosition => a.questions.indexWhere((item) => item.phase > q.phase);
  List<int> get _positions => [for (var i = 0; i < a.questions.length; i++)
    if (a.questions[i].phase == q.phase) i];

  @override
  void initState() {
    super.initState();
    widget.controller.resume = () {
      if (!_paused || a.submitted) return;
      setState(() => _paused = false); _watch.start();
    };
    widget.controller.answerWrong = () => _answer(q.options.firstWhere((o) => o['id'] != q.correct)['id'] as String);
    widget.controller.answerCorrect = () => _answer(q.correct);
    widget.controller.showTranscript = () {
      setState(() => _demoTranscript = true);
      final ids = a.progress.putIfAbsent('text_help', () => <String>[]) as List;
      if (!ids.contains(q.id)) ids.add(q.id);
      unawaited(_save());
    };
    widget.controller.nextPhase = () async {
      final next = _nextPosition;
      if (next < 0) return;
      _account(); _watch.stop();
      final phase = q.phase;
      setState(() {
        final completed = a.progress['completed_phases'] as List;
        if (!completed.contains(phase)) completed.add(phase);
        a.position = next;
        a.progress['furthest_phase'] = q.phase;
        _paused = true;
      });
      await _save();
    };
    widget.controller.submit = _submitAnswers;
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
      SystemErrors.record(caughtError, caughtStack, module: 'jlpt_test_demo', operation: '保存答题进度', context: {'source': 'study_room/jlpt_test/demo/runner.dart'});
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
    final nextPosition = _nextPosition;
    final nextPhase = nextPosition >= 0;
    final positions = nextPhase ? _positions : List.generate(a.questions.length, (i) => i);
    final missing = positions.where((i) => !a.answers.containsKey(a.questions[i].id)).toList();
    final missingMessage = missing.isEmpty ? '${nextPhase ? '本部分' : '全卷'}题目已全部作答。'
      : '${nextPhase ? '本部分' : '全卷'}还有 ${missing.length} 题未答。';
    final confirmed = await _confirm(nextPhase ? '完成本部分' : '提交答案',
      missingMessage + (nextPhase ? '完成后进入下一部分准备页，计时暂停。' : '提交后生成结果与解析。'),
      nextPhase ? '进入下一部分' : '提交', hasMissing: missing.isNotEmpty);
    if (!mounted) return;
    if (confirmed == _FinishAction.answerMissing && missing.isNotEmpty) {
      _move(missing.first);
    } else if (confirmed == _FinishAction.submit) {
      _account(); _watch.stop();
      if (nextPhase) {
        final phase = q.phase;
        final completed = a.progress['completed_phases'] as List;
        if (!completed.contains(phase)) completed.add(phase);
        a.position = nextPosition;
        final furthest = a.progress['furthest_phase'] as int? ?? 0;
        if (q.phase > furthest) a.progress['furthest_phase'] = q.phase;
        _paused = true;
        await _save();
      } else {
        await _submitAnswers();
      }
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

  Future<void> _phases() async {
    final furthest = a.progress['furthest_phase'] as int? ?? q.phase;
    final chosen = await showModalBottomSheet<int>(context: context,
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('考试部分 · 可返回已到达的部分')),
        for (var phase = 0; phase < 3; phase++) if (a.questions.any((q) => q.phase == phase)) ListTile(
          title: Text(_phaseLabels[phase]),
          subtitle: Text(phase > furthest ? '完成前一部分后开放' : '进入准备页，继续作答'),
          enabled: phase <= furthest,
          leading: Icon(phase > furthest ? Icons.lock_outline : Icons.menu_book_outlined),
          onTap: () => Navigator.pop(context, phase),
        ),
      ])));
    if (chosen == null || !mounted) return;
    _pause();
    setState(() => a.position = a.questions.indexWhere((item) => item.phase == chosen));
    unawaited(_save());
  }

  String get _timeLabel {
    final used = (a.elapsed[_clock] as int? ?? 0) + _watch.elapsedMilliseconds;
    var seconds = used ~/ 1000;
    String prefix = '用时';
    {
      final parts = (a.snapshot['parts'] as List).cast<Json>();
      final part = parts.where((p) => p['code'] == _clock).firstOrNull;
      final recommended = part?['recommended_seconds'] as int?;
      if (recommended != null) {
        seconds = recommended - seconds;
        prefix = seconds >= 0 ? '剩余' : '超时';
        seconds = seconds.abs();
      }
    }
    return '$prefix ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _canPop,
    onPopInvokedWithResult: (didPop, _) { if (!didPop) unawaited(_leave()); },
    child: Scaffold(
      appBar: StudyAppBar(centerTitle: true, title: Text(a.submitted ? '结果与回顾' : '${a.level} 测试演示'),
        actions: [
          if (!a.submitted) StudyIconButton(tooltip: '考试部分', onPressed: _busy || _submissionFailed ? null : _phases,
            icon: const Icon(Icons.view_week_outlined)),
          if (!a.submitted) StudyIconButton(tooltip: '暂停并保存',
            onPressed: _busy || _submissionFailed ? null : _pause, icon: const Icon(Icons.pause_circle_outline)),
        ]),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860), child: Column(children: [
        if (_saveFailed && !_submitting && !_submissionFailed) MaterialBanner(content: const Text('进度保存失败，请重试后再退出。'),
          actions: [StudyButton.text(onPressed: _busy ? null : () => unawaited(_save()), child: const Text('重试保存'))]),
        Expanded(child: a.submitted ? ResultView(a, key: widget.controller.resultTarget)
          : _submitting || _submissionFailed ? _submissionStatus(context)
          : _paused ? _ready(context) : _body(context)),
      ])))),
    ),
  );

  Widget _ready(BuildContext context) => Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(28), child: Column(children: [
      const Icon(Icons.menu_book_outlined, size: 56), const SizedBox(height: 20),
      Text(_phaseLabels[q.phase],
        style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: 12), Text('本部分 ${_positions.length} 题 · $_timeLabel'),
      const SizedBox(height: 16),
      const Text('准备好后开始计时。暂停、退出或切到后台不计时。超过参考时间可继续作答。', textAlign: TextAlign.center),
      if (['N1', 'N2'].contains(a.level) && q.phase < 2)
        const Padding(padding: EdgeInsets.only(top: 12), child: Text('N1 / N2 前部与中部共用语言知识·阅读计时。')),
      if (q.listening) const Padding(padding: EdgeInsets.only(top: 12),
        child: Text('本题库暂无正式录音，可用系统合成朗读或文字稿作答；不代表真实听辨成绩。')),
      const SizedBox(height: 24), StudyButton.filledIcon(
        key: widget.controller.readyTarget, onPressed: _busy ? null : () {
        setState(() => _paused = false); _watch.start();
      }, icon: const Icon(Icons.play_arrow), label: const Text('开始 / 继续作答')),
    ]),
  ));

  Widget _body(BuildContext context) {
    final positions = _positions;
    final localIndex = positions.indexOf(a.position);
    final answered = positions.where((i) => a.answers.containsKey(a.questions[i].id)).length;
    return Column(key: widget.controller.questionTarget, children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(children: [Expanded(child: Text(_phaseLabels[q.phase])), Text(_timeLabel)])),
      LinearProgressIndicator(value: answered / positions.length),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
        Expanded(child: Text('第 ${a.position + 1} 题 · 本部分已答 $answered/${positions.length}')),
        StudyIconButton(tooltip: a.flags.contains(q.id) ? '取消标记' : '标记本题',
          icon: Icon(a.flags.contains(q.id) ? Icons.flag : Icons.outlined_flag), onPressed: () {
            setState(() { a.flags.contains(q.id) ? a.flags.remove(q.id) : a.flags.add(q.id); });
            unawaited(_save());
          }),
        StudyIconButton(tooltip: '答题卡', onPressed: _answerCard, icon: const Icon(Icons.grid_view)),
      ])),
      Expanded(child: SingleChildScrollView(key: ValueKey(a.position),
        padding: const EdgeInsets.all(20), child: Column(children: [
          if (q.listening) ListeningQuestion(key: ValueKey(q.id), question: q,
            showDemoTranscript: _demoTranscript,
            answer: a.answers[q.id] as String?, onAnswer: _busy ? null : _answer,
            onHelp: (kind) {
              final ids = a.progress.putIfAbsent(kind, () => <String>[]) as List;
              if (!ids.contains(q.id)) ids.add(q.id);
              unawaited(_save());
            })
          else QuestionView(question: q, answer: a.answers[q.id] as String?,
            onAnswer: _busy ? null : _answer),
          if (a.answers.containsKey(q.id)) StudyButton.text(onPressed: _busy ? null : () {
            setState(() => a.answers.remove(q.id)); unawaited(_save());
          }, child: const Text('清除本题答案')),
        ]))),
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        if (localIndex < positions.length - 1)
          StudyButton.filled(onPressed: _busy ? null : () => _move(positions[localIndex + 1]), child: const Text('下一题'))
        else StudyButton.filled(onPressed: _busy ? null : _finish, child: Text(_nextPosition >= 0 ? '完成本部分' : '交卷')),
        const Spacer(),
        StudyButton.outlined(onPressed: _busy || localIndex == 0 ? null : () => _move(positions[localIndex - 1]), child: const Text('上一题')),
      ])),
    ]);
  }

  @override
  void dispose() {
    _timer?.cancel(); _watch.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

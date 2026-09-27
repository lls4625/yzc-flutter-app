import '../../../system_errors.dart';
import '../../../foundation/native_audio_transport.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../glass_ui.dart';
import 'models.dart';
import 'question_view.dart';
import 'listening_question.dart';
import 'repository.dart';
import 'result.dart';

// This is the test module's own runner, independently maintained.

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
  Timer? _timer;
  bool _paused = true, _busy = false, _canPop = false, _saveFailed = false;
  bool _submitting = false, _submissionFailed = false, _deleting = false;
  Future<void> _writes = Future.value();
  int _ticks = 0;
  Attempt get a => widget.attempt;
  Question get q => a.questions[a.position];
  bool get _audioRunning {
    final audio = NativeAudioTransport.instance;
    return audio.lesson?.startsWith('jlpt_test-') == true && audio.active && !audio.paused;
  }

  bool _waitForAudio() {
    if (!_audioRunning) return false;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请等待本题音频播放完成。')));
    return true;
  }
  String get _clock => q.clock;
  int get _sectionIndex => a.sectionIndex(q);
  int get _nextPosition => a.questions.indexWhere(
    (item) => a.sectionIndex(item) > _sectionIndex);
  List<int> get _positions => [for (var i = 0; i < a.questions.length; i++)
    if (a.questions[i].clock == _clock) i];

  String _sectionDescription(String sectionCode) {
    final knownName = examSectionNames[sectionCode];
    if (knownName != null) return knownName;
    final questions = a.questions.where((question) => question.clock == sectionCode);
    final categories = <String>[];
    if (questions.any((question) => question.type.startsWith('V_'))) categories.add('文字词汇');
    final grammar = questions.any((question) => question.type.startsWith('G_'));
    final reading = questions.any((question) => question.type.startsWith('R_'));
    if (grammar && reading) {
      categories.add('语法与阅读');
    } else if (grammar) {
      categories.add('语法');
    } else if (reading) {
      categories.add('阅读');
    }
    if (questions.any((question) => question.type.startsWith('L_'))) categories.add('听力');
    if (categories.isNotEmpty) return categories.join(' · ');
    return questions.map((question) => question.typeName).toSet().take(2).join('、');
  }

  String _sectionLabel(String sectionCode) =>
    '第 ${a.sectionCodes.indexOf(sectionCode) + 1} 部分 · ${_sectionDescription(sectionCode)}';

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
    if (_submitting || _deleting) return;
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
      SystemErrors.record(caughtError, caughtStack, module: 'jlpt_test', operation: '保存答题进度', context: {'source': 'study_room/jlpt_test/feature/runner.dart'});
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

  void _pause({bool interrupted = false}) {
    if (!interrupted && _waitForAudio()) return;
    _account(); _watch.stop();
    if (mounted) setState(() => _paused = true);
    unawaited(_save());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !a.submitted) _pause(interrupted: true);
  }

  Future<void> _leave() async {
    if (_waitForAudio()) return;
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

  Future<void> _delete() async {
    if (_busy || _deleting || _audioRunning) return;
    final confirmed = await showGlassDialog<bool>(context: context,
      builder: (dialogContext) => GlassAlertDialog(
        title: const Text('删除本次测试记录？'),
        content: const Text('本次测试、作答进度、答题明细及其产生的错题和复习关联记录将被删除，无法撤销。'),
        actions: [
          StudyButton.text(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          StudyButton.filled(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确定'),
          ),
        ],
      ));
    if (confirmed != true || !mounted) return;
    _account();
    _watch.stop();
    setState(() {
      _paused = true;
      _busy = true;
      _deleting = true;
    });
    await _writes;
    try {
      await widget.repository.delete(a.id);
      if (!mounted) return;
      setState(() => _canPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop(true);
    } catch (caughtError, caughtStack) {
      SystemErrors.record(caughtError, caughtStack,
        module: 'jlpt_test', operation: '删除本次测试记录',
        context: {'source': 'study_room/jlpt_test/feature/runner.dart'});
      if (!mounted) return;
      setState(() {
        _busy = false;
        _deleting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        GlassSnackBar(content: const Text('本次测试记录暂未删除，请重试。')));
    }
  }

  void _move(int position) {
    if (_waitForAudio()) return;
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
    if (_waitForAudio()) return;
    if (_busy) return;
    setState(() => _busy = true);
    final nextPosition = _nextPosition;
    final hasNextSection = nextPosition >= 0;
    final positions = hasNextSection ? _positions : List.generate(a.questions.length, (i) => i);
    final missing = positions.where((i) => !a.answers.containsKey(a.questions[i].id)).toList();
    final missingMessage = missing.isEmpty ? '${hasNextSection ? '本部分' : '全卷'}题目已全部作答。'
      : '${hasNextSection ? '本部分' : '全卷'}还有 ${missing.length} 题未答。';
    final confirmed = await _confirm(hasNextSection ? '完成本部分' : '提交答案',
      missingMessage + (hasNextSection ? '完成后进入下一部分准备页，计时暂停。' : '提交后生成结果与解析。'),
      hasNextSection ? '进入下一部分' : '提交', hasMissing: missing.isNotEmpty);
    if (!mounted) return;
    if (confirmed == _FinishAction.answerMissing && missing.isNotEmpty) {
      _move(missing.first);
    } else if (confirmed == _FinishAction.submit) {
      _account(); _watch.stop();
      if (hasNextSection) {
        if (!a.completedSections.contains(_clock)) a.completedSections.add(_clock);
        a.position = nextPosition;
        _paused = true;
        await _save();
      } else {
        await _submitAnswers();
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _answerCard() async {
    if (_waitForAudio()) return;
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
      appBar: StudyAppBar(centerTitle: true, title: Text(a.submitted ? '结果与回顾' : '${a.level} 模拟测试'),
        actions: [
          StudyIconButton(
            tooltip: '删除本次测试记录',
            onPressed: _busy || _submissionFailed || _audioRunning ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          if (!a.submitted) StudyIconButton(tooltip: '暂停并保存',
            onPressed: _busy || _submissionFailed || _audioRunning ? null : () => _pause(), icon: const Icon(Icons.pause_circle_outline)),
        ]),
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
      Text(_sectionLabel(_clock),
        style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: 12), Text('本部分 ${_positions.length} 题 · $_timeLabel'),
      const SizedBox(height: 16),
      const Text('准备好后开始计时。暂停、退出或切到后台不计时。超过参考时间可继续作答。', textAlign: TextAlign.center),
      if (['N1', 'N2'].contains(a.level) && _clock == 'language_reading')
        const Padding(padding: EdgeInsets.only(top: 12), child: Text('本部分包含文字、词汇、语法与阅读，并连续使用同一计时额度。')),
      if (q.listening) const Padding(padding: EdgeInsets.only(top: 12),
        child: Text('听力按题目播放配套音频；未提供音频的题目可查看文字稿。')),
      const SizedBox(height: 24), _sectionIndicator(context),
      const SizedBox(height: 16), StudyButton.filledIcon(onPressed: _busy ? null : () {
        setState(() => _paused = false); _watch.start();
      }, icon: const Icon(Icons.play_arrow), label: const Text('开始 / 继续作答')),
    ]),
  ));

  Widget _sectionIndicator(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sections = a.sectionCodes;
    final completed = a.completedSections;
    return Align(alignment: Alignment.center, child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: LayoutBuilder(builder: (context, bounds) {
        final spacing = bounds.maxWidth < 360 ? 6.0 : 10.0;
        final cardWidth = (bounds.maxWidth - spacing * (sections.length - 1)) / sections.length;
        final scale = (cardWidth / 160).clamp(.68, 1.0).toDouble();
        return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          for (var index = 0; index < sections.length; index++) ...[
            if (index > 0) SizedBox(width: spacing),
            Expanded(child: Builder(builder: (context) {
              final sectionCode = sections[index];
              final current = sectionCode == _clock;
              final done = !current && completed.contains(sectionCode);
              final foreground = current ? scheme.primary : scheme.onSurfaceVariant;
              final icon = current
                ? Icons.menu_book_rounded
                : done ? Icons.check_circle_outline_rounded : Icons.lock_outline_rounded;
              return Semantics(
                selected: current,
                label: '第 ${index + 1} 部分，${_sectionDescription(sectionCode)}，${current ? '当前阶段' : done ? '已完成' : '尚未开放'}',
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  height: 112 * scale,
                  padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 10 * scale),
                  decoration: BoxDecoration(
                    color: current
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(16 * scale),
                    border: Border.all(
                      color: current ? scheme.primary : scheme.outlineVariant.withValues(alpha: .75),
                      width: current ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Icon(icon, key: ValueKey(icon), size: 28 * scale,
                          color: current ? scheme.primary : foreground.withValues(alpha: .68)),
                      ),
                      SizedBox(height: 7 * scale),
                      Text('第 ${index + 1} 部分', maxLines: 1, overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 16 * scale,
                          fontWeight: current ? FontWeight.w700 : FontWeight.w600,
                        )),
                      SizedBox(height: 2 * scale),
                      Text(_sectionDescription(sectionCode), maxLines: 1, overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: foreground.withValues(alpha: current ? .82 : .62),
                          fontSize: 12 * scale,
                        )),
                    ],
                  ),
                ),
              );
            })),
          ],
        ]);
      }),
    ));
  }

  Widget _body(BuildContext context) {
    final positions = _positions;
    final localIndex = positions.indexOf(a.position);
    final answered = positions.where((i) => a.answers.containsKey(a.questions[i].id)).length;
    return Column(children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(children: [Expanded(child: Text(_sectionLabel(_clock))), Text(_timeLabel)])),
      LinearProgressIndicator(value: answered / positions.length),
      Padding(padding: const EdgeInsets.fromLTRB(12, 12, 8, 4), child: Row(children: [
        Expanded(child: Text('第 ${a.position + 1} 题 · 本部分已答 $answered/${positions.length}')),
        StudyIconButton(tooltip: a.flags.contains(q.id) ? '取消标记' : '标记本题',
          icon: Icon(a.flags.contains(q.id) ? Icons.flag : Icons.outlined_flag), onPressed: () {
            setState(() { a.flags.contains(q.id) ? a.flags.remove(q.id) : a.flags.add(q.id); });
            unawaited(_save());
          }),
        const SizedBox(width: 8),
        StudyIconButton(tooltip: '答题卡', onPressed: _audioRunning ? null : _answerCard, icon: const Icon(Icons.grid_view)),
      ])),
      Expanded(child: SingleChildScrollView(key: ValueKey(a.position),
        padding: const EdgeInsets.all(20), child: Column(children: [
          if (q.listening) ListeningQuestion(key: ValueKey(q.id), question: q,
            resolveMedia: widget.repository.mediaPath,
            mistakeReview: a.snapshot['mistake_review'] == true,
            audioCompleted: (a.progress['completed_audio'] as List? ?? []).contains(q.id),
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
          StudyButton.filled(onPressed: _busy || _audioRunning ? null : () => _move(positions[localIndex + 1]), child: const Text('下一题'))
        else StudyButton.filled(onPressed: _busy || _audioRunning ? null : _finish, child: Text(_nextPosition >= 0 ? '完成本部分' : '交卷')),
        const Spacer(),
        StudyButton.outlined(onPressed: _busy || _audioRunning || localIndex == 0 ? null : () => _move(positions[localIndex - 1]), child: const Text('上一题')),
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

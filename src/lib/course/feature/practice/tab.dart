import 'dart:async';
import 'package:flutter/material.dart';
import '../../../ai_question.dart';
import '../../../data.dart';
import '../../../ios_lesson_playback.dart';
import '../../../practice_question_body.dart';
import '../../../system_errors.dart';
import '../../../ui.dart';
import '../../../user_error.dart';
import '../host.dart';
import '../image_interaction_config.dart';
import '../media_widgets.dart';
import '../video_controller.dart';

typedef OpenPracticeSession = Future<void> Function(BuildContext context, String id);

/// Independent implementation of the course practice tab.
class CoursePracticeTab extends StatefulWidget {
  const CoursePracticeTab({required this.host, required this.book, required this.lesson,
    required this.openPractice, super.key});
  final CourseTabHost host;
  final RowData book, lesson;
  final OpenPracticeSession openPractice;

  @override
  State<CoursePracticeTab> createState() => _CoursePracticeTabState();
}

class _CoursePracticeTabState extends State<CoursePracticeTab> {
  final _playback = IosLessonPlayback.instance;
  final _video = CourseVideoController();
  List<RowData> _questions = [], _pending = [];
  bool _loading = true, _busy = false, _resourceUpdating = false;
  String? _error;

  String get _bookId => textOf(widget.book, 'id');
  String get _lessonId => textOf(widget.lesson, 'id');
  String get _identity => '$_bookId:$_lessonId:open-practice';
  bool get _ownsPlayback => _playback.lesson == _identity;
  bool get _blocked => widget.host.resources.unavailable.contains(_bookId) ||
    widget.host.resources.activeBook == _bookId;

  @override
  void initState() {
    super.initState();
    widget.host.resources.addListener(_resourceChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.host.resources.removeListener(_resourceChanged);
    if (_ownsPlayback) unawaited(_playback.stop());
    _video.dispose();
    super.dispose();
  }

  void _resourceChanged() {
    if (widget.host.resources.activeBook == _bookId) _resourceUpdating = true;
    if (_resourceUpdating && widget.host.resources.activeBook == null) {
      _resourceUpdating = false;
      unawaited(_load());
    }
    if (mounted) setState(() {});
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_practice', operation: '练习页操作',
        context: {'textbook_id': _bookId, 'lesson_id': _lessonId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          GlassSnackBar(content: Text(userError(error))),
        );
      }
    }
  }

  Future<void> _load() async {
    try {
      final questions = await widget.host.store.content('yzc_ai_question', _bookId, _lessonId);
      final history = await widget.host.store.history();
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _pending = history.where((row) => row['type'] != 'review' && row['status'] != 'complete' &&
          row['textbook_id'] == _bookId && row['lessons_id'] == _lessonId).toList();
        _loading = false;
        _error = null;
      });
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_practice', operation: '读取练习页签',
        context: {'textbook_id': _bookId, 'lesson_id': _lessonId});
      if (mounted) setState(() { _loading = false; _error = userError(error, fallback: '练习内容读取失败'); });
    }
  }

  Future<void> _open(String id) async {
    await widget.openPractice(context, id);
    if (mounted) await _load();
  }

  Future<void> _start({String? relation}) async {
    if (_busy || _blocked) return;
    setState(() => _busy = true);
    await _perform(() async {
      if (_ownsPlayback) await _playback.stop();
      await _video.stop();
      final id = await widget.host.store.startPractice(_questions, relation: relation);
      if (mounted) await _open(id);
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _playAudio(RowData question, {String? filename, String? title}) async {
    if (_busy || _blocked) return;
    setState(() => _busy = true);
    await _perform(() async {
      await _video.stop();
      if (_playback.active) await _playback.stop();
      final path = filename == null
        ? await widget.host.resources.mediaPath(_bookId, textOf(question, 'media_src'), 'audio')
        : await widget.host.resources.audioPath(_bookId, filename);
      await _playback.start({
        'lesson': _identity, 'title': title ?? '开放练习听力', 'words': false,
        'batch': false, 'speed': widget.host.speed, 'repeat': 1,
        'intervalSteps': 0, 'startIndex': 0,
        'clips': [{'id': 'open-practice:${question['id']}:${filename ?? question['media_src']}', 'path': path}],
      });
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _playHotspot(RowData question, CourseImageHotspot hotspot) =>
    _playAudio(question, filename: hotspot.audioSource, title: hotspot.label);

  Future<void> _playVideo(RowData question) async {
    if (_busy || _blocked) return;
    await _video.play(id: textOf(question, 'id'), book: _bookId,
      resolvePath: () => widget.host.resources.mediaPath(
        _bookId, textOf(question, 'media_src'), 'video'),
      beforePlay: () async { if (_playback.active) await _playback.stop(); });
  }

  Widget _questionMedia(RowData question) {
    final type = textOf(question, 'media_type');
    if (type.isEmpty || type == 'text') return const SizedBox.shrink();
    if (type == 'audio') {
      return Padding(padding: const EdgeInsets.only(bottom: 16), child: StudyButton.outlined(
        onPressed: _busy || _blocked ? null : () => _playAudio(question),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.volume_up_outlined), SizedBox(width: 8), Text('播放听力材料'),
        ])));
    }
    if (type == 'image') {
      return CourseImageCard(source: textOf(question, 'media_src'), label: '开放练习插图',
        resolvePath: () => widget.host.resources.mediaPath(
          _bookId, textOf(question, 'media_src'), 'image'));
    }
    if (type == 'interactive_image') {
      return CourseInteractiveImageCard(
        source: textOf(question, 'media_src'), label: '开放练习互动插图',
        mediaConfig: textOf(question, 'media_config'),
        resolvePath: () => widget.host.resources.mediaPath(
          _bookId, textOf(question, 'media_src'), 'interactive_image'),
        onActivate: (hotspot) => _playHotspot(question, hotspot),
        interactionEnabled: !_busy && !_blocked);
    }
    if (type == 'video') {
      return CourseVideoCard(controller: _video, id: textOf(question, 'id'),
        source: textOf(question, 'media_src'),
        resolvePath: () => widget.host.resources.mediaPath(
          _bookId, textOf(question, 'media_src'), 'video'),
        onPlay: () => _playVideo(question), enabled: !_busy && !_blocked);
    }
    return const Padding(padding: EdgeInsets.only(bottom: 16),
      child: Text('此开放练习媒体类型暂不支持'));
  }

  Widget _openQuestion(RowData question, int index) => _card(Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('开放练习 ${index + 1} · ${questionRelationLabel(question['relation'])}',
        style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 14),
      _questionMedia(question),
      PracticeQuestionBody(textOf(question, 'content'),
        key: ValueKey('open-practice-${question['id']}')),
    ],
  ));

  Widget _card(Widget child) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: StudyPanel(
      color: dark ? const Color(0xFF252525) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17), child: child)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: StudyCircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 16),
        StudyButton.filled(onPressed: _load, child: const Text('重新读取练习')),
      ])));
    final openQuestions = _questions.where(isOpenDisplayQuestion).toList();
    final choiceQuestions = _questions.where((row) => !isOpenDisplayQuestion(row)).toList();
    final counts = {for (final relation in questionRelations)
      relation: choiceQuestions.where((row) => row['relation'] == relation).length};
    final quota = practiceQuota(choiceQuestions);
    final ready = quota.entries.every((entry) => counts[entry.key]! >= entry.value);
    return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 20), children: [
      _card(const Text('题目可能存在错误，请自行校对，内容仅供参考。',
        style: TextStyle(fontSize: 14, color: Colors.red))),
      if (openQuestions.isNotEmpty) ...[
        _card(Text('本课有 ${openQuestions.length} 道开放练习。请自行口头或纸笔作答，App 不记录作答、不判对错。')),
        for (var i = 0; i < openQuestions.length; i++) _openQuestion(openQuestions[i], i),
      ],
      if (choiceQuestions.isNotEmpty) _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('客观练习 ${choiceQuestions.length} 题：单词 ${counts['word']}、文法 ${counts['grammar']}、课文 ${counts['content']}\n'
            '综合练习每次 10 题（${quota.entries.map((entry) => '${questionRelationLabel(entry.key)} ${entry.value} 题').join('、')}）'),
          const SizedBox(height: 12),
          if (_pending.isNotEmpty) StudyButton.outlined(onPressed: _busy ? null : () => _open(textOf(_pending.first, 'id')),
            child: Text('继续未完成练习（${_pending.first['answered']}/${_pending.first['count']}）')),
          if (_pending.isNotEmpty && ready) const SizedBox(height: 20),
          if (ready) StudyButton.filled(onPressed: _busy || _blocked ? null : _start,
            child: Text(_busy ? '准备中' : '开始随机练习'))
          else const Text('客观题尚未齐备，暂不能开始随机练习。'),
          for (final relation in questionRelations)
            if (counts[relation]! > 0) ...[
              const SizedBox(height: 12),
              StudyButton.outlined(onPressed: _busy || _blocked ? null : () => _start(relation: relation),
                child: Text('${questionRelationLabel(relation)}专项（最多${relation == 'content' ? 3 : 10}题）')),
            ],
        ])),
      if (_questions.isEmpty) _card(const Text('本课练习题正在整理中。')),
    ]);
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../ai_question.dart';
import '../../../data.dart';
import '../../../system_errors.dart';
import '../../../ui.dart';
import '../../../user_error.dart';
import '../host.dart';

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
  List<RowData> _questions = [], _pending = [];
  bool _loading = true, _busy = false, _resourceUpdating = false;
  String? _error;

  String get _bookId => textOf(widget.book, 'id');
  String get _lessonId => textOf(widget.lesson, 'id');
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
      final id = await widget.host.store.startPractice(_questions, relation: relation);
      if (mounted) await _open(id);
    });
    if (mounted) setState(() => _busy = false);
  }

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
    final counts = {for (final relation in questionRelations)
      relation: _questions.where((row) => row['relation'] == relation).length};
    final quota = practiceQuota(_questions);
    final ready = quota.entries.every((entry) => counts[entry.key]! >= entry.value);
    return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 20), children: [
      _card(const Text('题目可能存在错误，请自行校对，内容仅供参考。',
        style: TextStyle(fontSize: 14, color: Colors.red))),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('本课 ${_questions.length} 题：单词 ${counts['word']}、文法 ${counts['grammar']}、课文 ${counts['content']}\n'
          '综合练习每次 10 题（${quota.entries.map((entry) => '${questionRelationLabel(entry.key)} ${entry.value} 题').join('、')}）'),
        const SizedBox(height: 12),
        if (_pending.isNotEmpty) StudyButton.outlined(onPressed: _busy ? null : () => _open(textOf(_pending.first, 'id')),
          child: Text('继续未完成练习（${_pending.first['answered']}/${_pending.first['count']}）')),
        if (_pending.isNotEmpty && ready) const SizedBox(height: 20),
        if (ready) StudyButton.filled(onPressed: _busy || _blocked ? null : _start,
          child: Text(_busy ? '准备中' : '开始随机练习'))
        else Text(_questions.isEmpty ? '本课练习题正在整理中。' : '题目尚未齐备，暂不能开始练习。'),
        for (final relation in questionRelations)
          if (counts[relation]! > 0) ...[
            const SizedBox(height: 12),
            StudyButton.outlined(onPressed: _busy || _blocked ? null : () => _start(relation: relation),
              child: Text('${questionRelationLabel(relation)}专项（最多${relation == 'content' ? 3 : 10}题）')),
          ],
      ])),
    ]);
  }
}

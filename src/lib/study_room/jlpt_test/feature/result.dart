import 'package:flutter/material.dart';
import '../../../glass_ui.dart';
import 'models.dart';
import 'question_view.dart';
import 'review_audio.dart';

class ResultView extends StatefulWidget {
  const ResultView(this.attempt, {super.key, required this.resolveMedia});
  final Future<String?> Function(String, String) resolveMedia;
  final Attempt attempt;
  @override
  State<ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<ResultView> {
  String _filter = '全部';
  @override
  Widget build(BuildContext context) {
    final a = widget.attempt;
    final correct = a.questions.where(a.correct).length;
    final unanswered = a.questions.where((q) => !a.answers.containsKey(q.id)).length;
    final policy = a.snapshot['score_policy'] as Json?;
    final byType = <String, List<Question>>{};
    for (final q in a.questions) { byType.putIfAbsent(q.type, () => []).add(q); }
    final questions = a.questions.where((q) => _filter == '错题与未答'
        ? !a.correct(q) : _filter == '答对' ? a.correct(q)
        : _filter == '标记' ? a.flags.contains(q.id) : true).toList();
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(a.title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Text('$correct / ${a.questions.length} 题正确',
        style: Theme.of(context).textTheme.headlineMedium),
      Text('正确率 ${(100 * correct / a.questions.length).toStringAsFixed(1)}% · 未答 $unanswered 题'),
      Text('有效用时 ${((a.elapsed.values.fold<num>(0, (sum, v) => sum + (v as num))) / 60000).toStringAsFixed(1)} 分钟'),
      if (a.revealed.isNotEmpty) Text('${a.revealed.length} 题曾查看解析，成绩包含辅助作答'),
      const SizedBox(height: 16),
      if (policy != null) ...[
        Text('练习参考总分 ${_total(a, policy)} / 180'),
        const Text('分项练习参考分（非官方尺度分）', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final band in (policy['bands'] as List).cast<Json>())
          _band(a, band),
      ],
      if (a.questions.any((q) => q.listening))
        Text('听力适配：${(a.progress['file_audio'] as List? ?? []).length} 题播放音频，'
          '${(a.progress['text_help'] as List? ?? []).length} 题查看文字稿；不代表真实听辨能力。'),
      const Text('原创模拟与教材练习，尚待教研审校；结果不作 J 合格判定。'),
      const SizedBox(height: 16),
      ExpansionTile(title: const Text('题型表现'), children: [
        for (final entry in byType.entries) ListTile(
          title: Text(typeNames[entry.key] ?? entry.key),
          trailing: Text('${entry.value.where(a.correct).length} / ${entry.value.length}'),
        ),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [for (final filter in ['全部', '错题与未答', '答对', '标记'])
        StudyChoiceChip(label: Text(filter), selected: _filter == filter,
          onSelected: (_) => setState(() => _filter = filter))]),
      if (questions.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('这里暂时没有题目。')),
      for (final q in questions) ExpansionTile(
        key: ValueKey('${_filter}_${q.id}'),
        title: Text('${a.questions.indexOf(q) + 1}. ${q.typeName}'),
        subtitle: Text(a.answers[q.id] == null ? '未作答' : a.correct(q) ? '回答正确' : '需要巩固'),
        leading: Icon(a.answers[q.id] == null
            ? Icons.radio_button_unchecked
            : a.correct(q) ? Icons.check_circle_outline : Icons.error_outline),
        childrenPadding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          if (q.listening) ReviewAudio(key: ValueKey(q.id), question: q, resolveMedia: widget.resolveMedia),
          QuestionView(question: q, resolveMedia: widget.resolveMedia, answer: a.answers[q.id] as String?, review: true),
        ],
      ),
    ]);
  }

  String _total(Attempt a, Json policy) {
    var total = 0.0;
    for (final band in (policy['bands'] as List).cast<Json>()) {
      final qs = a.questions.where((q) => q.scoreBand == band['code']).toList();
      if (qs.isEmpty) return '资料不足';
      final value = qs.where(a.correct).length / qs.length * (band['max_score'] as num);
      total += (value * 10).round() / 10;
    }
    return total.toStringAsFixed(1);
  }

  Widget _band(Attempt a, Json band) {
    final qs = a.questions.where((q) => q.scoreBand == band['code']).toList();
    const labels = {'language': '语言知识', 'reading': '阅读',
      'language_reading': '语言知识与阅读', 'listening': '听力适配'};
    final score = qs.isEmpty ? '资料不足'
        : ((qs.where(a.correct).length / qs.length * (band['max_score'] as num) * 10).round() / 10).toStringAsFixed(1);
    return ListTile(contentPadding: EdgeInsets.zero,
      title: Text(labels[band['code']] ?? band['code'].toString()),
      trailing: Text('$score / ${band['max_score']}'));
  }
}

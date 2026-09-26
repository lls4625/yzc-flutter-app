import '../../../system_errors.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'controller.dart';
import '../../../glass_ui.dart';
import 'models.dart';
import 'repository.dart';
import 'runner.dart';

class JlptTestPage extends StatefulWidget {
  const JlptTestPage(this.controller, {super.key});
  final JlptDemoController controller;
  @override
  State<JlptTestPage> createState() => _JlptTestPageState();
}

class _JlptTestPageState extends State<JlptTestPage> {
  late final JlptRepository _repository = widget.controller.repository;
  String _level = 'N5';
  bool _levelRestored = false;
  int _paper = 0, _generation = 0;
  Bank? _bank;
  List<Json> _history = [];
  bool _loading = true, _opening = false, _choosingLevel = false;
  String? _error, _historyError;

  @override
  void initState() {
    super.initState();
    widget.controller.start = () { unawaited(_open()); };
    unawaited(_load()); unawaited(_loadHistory());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() { _loading = true; _error = null; _bank = null; });
    try {
      if (!_levelRestored) {
        final level = await _repository.loadLevel();
        if (!mounted || generation != _generation) return;
        setState(() { _level = level; _levelRestored = true; });
      }
      final bank = await _repository.load(_level);
      if (!mounted || generation != _generation) return;
      setState(() { _bank = bank; _paper = 0; _loading = false; });
    } catch (caughtError, caughtStack) {
      SystemErrors.record(caughtError, caughtStack, module: 'jlpt_test_demo', operation: '测试列表操作', context: {'source': 'study_room/jlpt_test/demo/page.dart'});
      if (mounted && generation == _generation) setState(() {
        _loading = false; _error = '题库读取失败，请重试或重新播放演示。';
      });
    }
  }

  Future<void> _loadHistory() async {
    try {
      final history = await _repository.history();
      if (mounted) setState(() { _history = history; _historyError = null; });
    } catch (caughtError, caughtStack) {
      SystemErrors.record(caughtError, caughtStack, module: 'jlpt_test_demo', operation: '测试列表操作', context: {'source': 'study_room/jlpt_test/demo/page.dart'});
      if (mounted) setState(() => _historyError = '历史记录读取失败，点此重试');
    }
  }

  List<Question> _questions(Json paper) {
    final allocation = (paper['type_allocation'] as List).cast<Json>();
    final order = {for (var i = 0; i < allocation.length; i++) allocation[i]['type_code']: i};
    final questions = (paper['questions'] as List).cast<Json>().map(Question.new).toList();
    questions.sort((a, b) {
      final type = order[a.type]!.compareTo(order[b.type]!);
      return type != 0 ? type : (a.data['paper_position'] as int).compareTo(b.data['paper_position'] as int);
    });
    return questions;
  }

  Future<void> _chooseLevel() async {
    if (!_levelRestored || _opening || _choosingLevel) return;
    setState(() => _choosingLevel = true);
    try {
      final level = await showGlassDialog<String>(
        context: context,
        builder: (dialogContext) => GlassAlertDialog(
          title: Row(children: [
            const Expanded(child: Text('选择考试等级')),
            const SizedBox(width: 12),
            StudyIconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(dialogContext),
              icon: const Icon(Icons.close_rounded),
            ),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final level in levels) ...[
              if (level != levels.first) const SizedBox(height: 12),
              Semantics(
                selected: level == _level,
                child: level == _level
                    ? StudyButton.filled(
                        onPressed: () => Navigator.pop(dialogContext, level),
                        child: Text(level),
                      )
                    : StudyButton.text(
                        onPressed: () => Navigator.pop(dialogContext, level),
                        child: Text(level),
                      ),
              ),
            ]],
          ),
          actions: const [],
        ),
      );
      if (mounted && level != null && level != _level) {
        await _repository.saveLevel(level);
        if (!mounted) return;
        _level = level;
        await _load();
      }
    } catch (caughtError, caughtStack) {
      SystemErrors.record(caughtError, caughtStack, module: 'jlpt_test_demo', operation: '保存考试等级');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('考试等级保存失败，请重试。')));
    } finally {
      if (mounted) setState(() => _choosingLevel = false);
    }
  }

  Future<void> _openMistakes() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final rows = await _repository.mistakes();
      if (!mounted) return;
      final selected = await showModalBottomSheet<Json>(context: context,
        isScrollControlled: true, builder: (context) => SafeArea(child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('演示错题 · 仅保留在本次演示中')),
            Expanded(child: ListView(children: [
              if (rows.isEmpty) const ListTile(title: Text('暂无待重做的错题')),
              for (final row in rows) ListTile(
                title: Text(row['question']['stem_json']['text'] as String, style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP')),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${row['question']['level']} · 做错 ${row['wrong_count']} 次'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, row)),
            ])),
          ]),
        )));
      if (selected == null || !mounted) return;
      final question = Question(Map<String, dynamic>.from(selected['question'] as Map));
      final attempt = Attempt.create(question.data['level'] as String, '错题重做 · ${question.typeName}', [question]);
      attempt.snapshot['mistake_review'] = true;
      await _repository.create(attempt);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AttemptPage(_repository, attempt, controller: widget.controller)));
      await _loadHistory();
    } catch (caughtError, caughtStack) {
      SystemErrors.record(caughtError, caughtStack, module: 'jlpt_test_demo', operation: '测试列表操作', context: {'source': 'study_room/jlpt_test/demo/page.dart'});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('错题记录暂时无法打开，请重试。')));
    } finally { if (mounted) setState(() => _opening = false); }
  }

  Widget _mistakesButton() => TextButton.icon(
    onPressed: _opening ? null : _openMistakes,
    icon: const Icon(Icons.history_edu), label: const Text('演示错题重做'),
  );

  Future<void> _open({String? id}) async {
    if (_opening || (id == null && (_loading || _choosingLevel))) return;
    setState(() => _opening = true);
    try {
      final Attempt attempt;
      if (id != null) {
        attempt = await _repository.restore(id);
      } else {
        final paper = _bank!.papers[_paper];
        attempt = Attempt.create(_level, paper['title'] as String, _questions(paper), paper: paper);
        await _repository.create(attempt);
      }
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AttemptPage(_repository, attempt, controller: widget.controller)));
      await _loadHistory();
    } catch (caughtError, caughtStack) {
      SystemErrors.record(caughtError, caughtStack, module: 'jlpt_test_demo', operation: '测试列表操作', context: {'source': 'study_room/jlpt_test/demo/page.dart'});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂时无法打开试卷，请检查设备存储后重试。')));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: StudyAppBar(title: const Text('J测试 · 演示'), centerTitle: true, actions: [
      StudyIconButton(
        tooltip: '选择考试等级（当前 $_level）',
        onPressed: !_levelRestored || _opening || _choosingLevel ? null : _chooseLevel,
        icon: Text(_level, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
      StudyIconButton(
        key: widget.controller.startTarget, tooltip: _opening ? '准备中' : '开始测试',
        onPressed: _loading || _opening || _choosingLevel ? null : () => _open(),
        icon: const Icon(Icons.play_circle_outline_rounded),
      ),
    ]),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: _loading ? const Center(child: CircularProgressIndicator())
        : _bank == null ? ListView(padding: const EdgeInsets.all(20), children: [
            Text(_error ?? '演示样例暂不可用，请重新播放。'),
            if (_error != null) TextButton(onPressed: _opening || _choosingLevel ? null : _load, child: const Text('重新读取')),
            if (_error != null) const SizedBox(height: 8),
            _mistakesButton(),
            const SizedBox(height: 16), const Text('仍可打开已保存的作答记录'),
            if (_historyError != null) TextButton(onPressed: _loadHistory, child: Text(_historyError!)),
            if (_history.isEmpty && _historyError == null) const ListTile(title: Text('暂无已保存的作答记录')),
            for (final item in _history) _historyRow(item),
          ]) : _content(context),
    ))),
  );

  Widget _content(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paper = _bank!.papers[_paper];
    final questions = _questions(paper);
    final parts = (paper['parts'] as List).cast<Json>();
    final totalSeconds = parts.fold<int>(0, (sum, p) => sum + (p['recommended_seconds'] as int));
    return ListView(padding: const EdgeInsets.all(20), children: [
      _mistakesButton(),
      Text('给自己一次完整的检视', key: widget.controller.selection, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8), Text('$_level · ${questions.length} 题 · 参考 $totalSeconds 秒（${totalSeconds ~/ 60} 分钟）'),
      const SizedBox(height: 20),
      Row(children: [const Expanded(child: Text('选择模拟卷', style: TextStyle(fontWeight: FontWeight.bold))),
        TextButton.icon(onPressed: _opening || _bank!.papers.length < 2 ? null : () => setState(() {
          final size = _bank!.papers.length;
          if (size > 1) _paper = (_paper + 1 + Random().nextInt(size - 1)) % size;
        }), icon: const Icon(Icons.shuffle), label: const Text('随机一份'))]),
      LayoutBuilder(builder: (context, bounds) {
        const columns = 4;
        return Wrap(spacing: 4, runSpacing: 4,
          children: List.generate(_bank!.papers.length, (index) {
          final checked = _paper == index;
          return SizedBox(width: (bounds.maxWidth - (columns - 1) * 4) / columns,
            child: Semantics(
            selected: checked,
            button: true,
            enabled: !_opening,
            inMutuallyExclusiveGroup: true,
            label: '第 ${index + 1} 套 · $_level',
            child: StudyPanel(
              color: checked ? scheme.primaryContainer : scheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: checked ? scheme.primary : scheme.outlineVariant,
                  width: checked ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: StudyInkWell(
                onTap: _opening ? null : () => setState(() => _paper = index),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 60),
                    child: SizedBox(width: double.infinity, child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('第 ${index + 1} 套', textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 5),
                      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 2, children: [
                          Icon(Icons.description_outlined, size: 13, color: scheme.primary),
                          const SizedBox(width: 2),
                          Text(_level, style: const TextStyle(fontSize: 10)),
                          const SizedBox(width: 2),
                          Icon(checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                            size: 12, color: checked ? scheme.primary : scheme.onSurfaceVariant),
                      ]),
                    ],
                  ))),
                ),
              ),
            ),
          ));
        }),
      );
      }),
      const SizedBox(height: 24),
      Text('考试介绍', style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text('按前部 → 中部 → 后部顺序完成',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.schedule_rounded, size: 16, color: scheme.primary),
        const SizedBox(width: 6),
        Expanded(child: Text(
          ['N1', 'N2'].contains(_level)
            ? '前部与中部${_duration(parts, questions, 0).replaceFirst('前中共用', '共用')} · 后部${_duration(parts, questions, 2)}'
            : [for (var phase = 0; phase < 3; phase++)
                '${['前部', '中部', '后部'][phase]}${_duration(parts, questions, phase)}'].join(' · '),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        )),
      ]),
      const SizedBox(height: 12),
      for (var phase = 0; phase < 3; phase++) ...[
        if (phase > 0) const SizedBox(height: 10),
        _phaseIntroduction(paper, questions, phase),
      ],
      const SizedBox(height: 16),
      Text(['N1', 'N2'].contains(_level)
        ? 'N1 / N2 正式考试非听力部分共用计时；这里分前、中两页顺序作答，共用同一计时额度。'
        : '前、中、后三部分分别计时。每部分完成后进入下一部分准备页。'),
      const SizedBox(height: 8),
      const Text('可暂停、退出续做；超时不会自动交卷。交卷前提示未答题，提交后查看解析和分项表现。'),
      const SizedBox(height: 8),
      const Text('题目为模拟练习。听力支持合成朗读与文字稿适配；结果为练习参考，不作官方合格判定。'),
      const SizedBox(height: 24), const Text('最近测试', style: TextStyle(fontWeight: FontWeight.bold)),
      if (_historyError != null) TextButton(onPressed: _loadHistory, child: Text(_historyError!)),
      if (_history.isEmpty && _historyError == null) const ListTile(title: Text('开始后，测试进度会保存在这里。')),
      for (final item in _history) _historyRow(item),
    ]);
  }

  Widget _phaseIntroduction(Json paper, List<Question> questions, int phase) {
    final scheme = Theme.of(context).colorScheme;
    final styles = Theme.of(context).textTheme;
    final phaseQuestions = questions.where((q) => q.phase == phase).toList();
    final allocations = (paper['type_allocation'] as List).cast<Json>()
      .where((allocation) => phaseQuestions.any((q) => q.type == allocation['type_code']))
      .toList();
    String name(Json allocation) =>
      typeNames[allocation['type_code']] ?? allocation['name_ja'].toString();
    final summary = allocations.isEmpty ? '暂无题目'
      : '${allocations.take(2).map(name).join('、')}${allocations.length > 2 ? '等' : ' · '} ${allocations.length} 类题型';
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text('0${phase + 1}', style: styles.labelMedium?.copyWith(
                color: scheme.primary, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('${['前部', '中部', '后部'][phase]} · ${['文字与词汇', '语法与阅读', '听力适配'][phase]}',
              style: styles.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
            const SizedBox(width: 8),
            Text('${phaseQuestions.length} 题', style: styles.bodyMedium),
          ]),
          const SizedBox(height: 8),
          Text(summary, style: styles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ExpansionTile(
            key: ValueKey('$_level-$_paper-$phase'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 10),
            initiallyExpanded: false,
            dense: true,
            shape: const Border(),
            collapsedShape: const Border(),
            iconColor: scheme.onSurfaceVariant,
            collapsedIconColor: scheme.onSurfaceVariant,
            title: Text('题型明细', style: styles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            children: [
              Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: .6)),
              const SizedBox(height: 6),
              for (final allocation in allocations)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(child: Text(name(allocation), style: styles.bodySmall)),
                    const SizedBox(width: 12),
                    Text('${allocation['question_count']} 题', style: styles.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant)),
                  ]),
                ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _historyRow(Json item) => ListTile(
    title: Row(children: [
      Expanded(child: Text(item['title'] as String, maxLines: 1, overflow: TextOverflow.ellipsis)),
      const SizedBox(width: 12),
      Text(item['submitted'] == 1 ? '查看结果' : '继续作答',
        style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(width: 4), const Icon(Icons.chevron_right, size: 20),
    ]),
    onTap: _opening ? null : () => _open(id: item['id'] as String),
  );

  String _duration(List<Json> parts, List<Question> questions, int phase) {
    final phaseQuestions = questions.where((q) => q.phase == phase);
    if (phaseQuestions.isEmpty) return '暂无题目';
    final clock = phaseQuestions.first.clock;
    final seconds = parts.firstWhere((part) => part['code'] == clock)['recommended_seconds'] as int;
    return '${['N1', 'N2'].contains(_level) && phase < 2 ? '前中共用' : '参考'} ${seconds ~/ 60} 分钟';
  }

  @override
  void dispose() { _generation++; unawaited(_repository.close()); super.dispose(); }
}

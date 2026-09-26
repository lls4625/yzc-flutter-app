import '../../../system_errors.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../glass_ui.dart';
import 'controller.dart';
import 'models.dart';
import 'repository.dart';
import 'runner.dart';

class JlptPracticePage extends StatefulWidget {
  const JlptPracticePage(this.controller, {super.key});
  final JlptDemoController controller;
  @override
  State<JlptPracticePage> createState() => _JlptPracticePageState();
}

class _JlptPracticePageState extends State<JlptPracticePage> {
  late final JlptRepository _repository = widget.controller.repository;
  String _level = 'N5', _type = 'V_KANJI_READING';
  bool _levelRestored = false;
  int _count = 2, _generation = 0;
  Bank? _bank;
  List<Json> _history = [];
  bool _loading = true, _opening = false, _choosingLevel = false;
  String? _error, _historyError;
  Map<String, Map<int, int>> _sizes = {};
  Map<String, Map<int, bool>> _partial = {};

  @override
  void initState() {
    super.initState();
    widget.controller.start = () { unawaited(_open()); };
    widget.controller.openMistakes = () { unawaited(_openMistakes()); };
    widget.controller.home = () { unawaited(_loadHistory()); };
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
      final sizes = <String, Map<int, int>>{};
      final partial = <String, Map<int, bool>>{};
      for (final type in bank.byType.keys) {
        sizes[type] = {};
        partial[type] = {};
        for (final count in [2]) {
          final selection = bank.practice(type, count, randomize: false);
          sizes[type]![count] = selection.length;
          partial[type]![count] = bank.hasPartialGroup(selection);
        }
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _bank = bank; _sizes = sizes; _partial = partial; _loading = false;
        if (!bank.byType.containsKey(_type)) _type = bank.byType.keys.first;
      });
    } catch (caughtError, caughtStack) {
      SystemErrors.record(caughtError, caughtStack, module: 'jlpt_practice_demo', operation: '练习列表操作', context: {'source': 'study_room/jlpt_practice/demo/page.dart'});
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
      SystemErrors.record(caughtError, caughtStack, module: 'jlpt_practice_demo', operation: '练习列表操作', context: {'source': 'study_room/jlpt_practice/demo/page.dart'});
      if (mounted) setState(() => _historyError = '历史记录读取失败，点此重试');
    }
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
      SystemErrors.record(caughtError, caughtStack, module: 'jlpt_practice_demo', operation: '保存考试等级');
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
      SystemErrors.record(caughtError, caughtStack, module: 'jlpt_practice_demo', operation: '练习列表操作', context: {'source': 'study_room/jlpt_practice/demo/page.dart'});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('错题记录暂时无法打开，请重试。')));
    } finally { if (mounted) setState(() => _opening = false); }
  }

  Widget _mistakesButton() => TextButton.icon(key: widget.controller.mistakesTarget,
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
        final questions = _bank!.practice(_type, _count);
        if (questions.isEmpty) throw StateError('当前题型数量不足');
        attempt = Attempt.create(_level, '$_level · ${typeNames[_type]} · ${questions.length}题', questions);
        await _repository.create(attempt);
      }
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AttemptPage(_repository, attempt, controller: widget.controller)));
      await _loadHistory();
    } catch (caughtError, caughtStack) {
      SystemErrors.record(caughtError, caughtStack, module: 'jlpt_practice_demo', operation: '练习列表操作', context: {'source': 'study_room/jlpt_practice/demo/page.dart'});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂时无法打开练习，请检查设备存储后重试。')));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actual = _sizes[_type]?[_count] ?? 0;
    return Scaffold(
      appBar: StudyAppBar(title: const Text('J练习 · 演示'), centerTitle: true, actions: [
        StudyIconButton(
          tooltip: '选择考试等级（当前 $_level）',
          onPressed: !_levelRestored || _opening || _choosingLevel ? null : _chooseLevel,
          icon: Text(_level, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        StudyIconButton(
          key: widget.controller.startTarget, tooltip: _opening ? '准备中' : '开始练习',
          onPressed: _loading || _opening || _choosingLevel || (_bank != null && actual == 0)
              ? null : () => _open(),
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
            for (final item in _history) ListTile(title: Text(item['title'] as String),
              subtitle: Text(item['submitted'] == 1 ? '查看结果' : '继续作答'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _opening ? null : () => _open(id: item['id'] as String)),
          ]) : ListView(padding: const EdgeInsets.all(20), children: [
            _mistakesButton(),
            Text('专注一个题型，练稳每一步', key: widget.controller.selection, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8), const Text('选择题型，再点击右上角开始，演示固定练习 2 题。'),
            const SizedBox(height: 20),
            Row(children: [
              Text('练习题数', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: 12),
              const Expanded(child: Text('2 题')),
            ]),
            const SizedBox(height: 10),
            Text(actual == 0 ? '该题型数量不足，请选择其他题型。'
              : _partial[_type]?[_count] == true ? '本次 $actual 题：末尾题组选取部分小题。'
              : '本次 $actual 题 · 选项顺序固定。'),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, bounds) {
              final wide = bounds.maxWidth >= 600;
              return Wrap(spacing: 8, runSpacing: 8, children: [
                for (final category in const ['V_', 'G_', 'R_', 'L_'])
                  SizedBox(width: wide ? (bounds.maxWidth - 8) / 2 : bounds.maxWidth,
                    child: _categoryCard(category)),
              ]);
            }),
            const SizedBox(height: 24), const Text('最近练习', style: TextStyle(fontWeight: FontWeight.bold)),
            if (_historyError != null) TextButton(onPressed: _loadHistory, child: Text(_historyError!)),
            if (_history.isEmpty && _historyError == null) const ListTile(title: Text('开始后，练习进度会保存在这里。')),
            for (final item in _history) ListTile(title: Text(item['title'] as String),
              subtitle: Text(item['submitted'] == 1 ? '已完成 · 查看结果' : '已暂停 · 继续练习'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _opening ? null : () => _open(id: item['id'] as String)),
            const SizedBox(height: 16), const Text('题目为模拟练习。听力支持合成朗读与文字稿适配。'),
          ]),
      ))),
    );
  }

  Widget _categoryCard(String category) {
    final scheme = Theme.of(context).colorScheme;
    return StudyPanel(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              {'V_': '文字与词汇', 'G_': '语法', 'R_': '阅读', 'L_': '听力 · 适配练习'}[category]!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          _typeGrid(category),
        ]),
      ),
    );
  }

  Widget _typeGrid(String category) {
    final scheme = Theme.of(context).colorScheme;
    final types = typeNames.keys.where((type) =>
      type.startsWith(category) && _bank!.byType.containsKey(type)).toList();
    return LayoutBuilder(builder: (context, bounds) => Wrap(
      spacing: 4, runSpacing: 4,
      children: List.generate(types.length, (index) {
        final type = types[index];
        final checked = _type == type;
        final count = _bank!.byType[type]!.length;
        return SizedBox(width: (bounds.maxWidth - 4) / 2, child: Semantics(
          selected: checked,
          button: true,
          inMutuallyExclusiveGroup: true,
          enabled: !_opening,
          label: '${typeNames[type]} · $count 道题',
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
              onTap: _opening ? null : () => setState(() => _type = type),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 60),
                  child: SizedBox(width: double.infinity, child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(typeNames[type]!, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 2, children: [
                        Text('$count 道题', style: const TextStyle(fontSize: 10)),
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
    ));
  }

  @override
  void dispose() { _generation++; unawaited(_repository.close()); super.dispose(); }
}

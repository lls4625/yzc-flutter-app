import 'dart:async';

import 'package:flutter/material.dart';

import '../../../glass_ui.dart';
import '../../../playback_scaffold.dart';
import '../../../ui.dart' show plainJapanese;
import '../../host_contracts.dart';
import 'repository.dart';

class GrammarLookupPage extends StatefulWidget {
  const GrammarLookupPage(this.host, {super.key});
  final StudyRoomHost host;

  @override
  State<GrammarLookupPage> createState() => _GrammarLookupPageState();
}

class _GrammarLookupPageState extends State<GrammarLookupPage> {
  late final GrammarLookupRepository _repository = GrammarLookupRepository(
    widget.host,
  );
  final _controller = TextEditingController();
  Timer? _debounce;
  List<GrammarLookupRow> _rows = const [];
  final Set<String> _expandedRows = <String>{};
  int _request = 0;
  bool _loading = false;
  bool _meaningsAvailable = true;
  String? _usageFilter;
  String? _error;
  TextEditingValue? _lastInput;
  final Map<String, Future<List<GrammarLookupRow>>> _details = {};

  @override
  void initState() {
    super.initState();
    _controller.addListener(_inputChanged);
    widget.host.changes.addListener(_resourcesChanged);
  }

  void _resourcesChanged() {
    _details.clear();
    _changed(_controller.text);
  }

  void _inputChanged() {
    final next = _controller.value;
    if (_lastInput?.text == next.text &&
        _lastInput?.composing == next.composing) return;
    _lastInput = next;
    _changed(next.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.host.changes.removeListener(_resourcesChanged);
    _controller.removeListener(_inputChanged);
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _request++;
    final composing = _controller.value.composing;
    setState(() {
      _rows = const [];
      _expandedRows.clear();
      _details.clear();
      _usageFilter = null;
      _loading = false;
      _error = null;
    });
    if (value.trim().isEmpty ||
        (composing.isValid && !composing.isCollapsed)) return;
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 280), () => _search(value));
  }

  Future<void> _search(String value) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _expandedRows.clear();
      _details.clear();
      _usageFilter = null;
    });
    try {
      final result = await _repository.search(value);
      if (!mounted || request != _request) return;
      setState(() {
        _rows = result.rows;
        _meaningsAvailable = result.meaningsAvailable;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _rows = const [];
        _loading = false;
        _error = '查询失败，请重试。';
      });
    }
  }

  String _text(GrammarLookupRow row, String key) => row[key]?.toString() ?? '';
  String _rowKey(GrammarLookupRow row) => [
    _text(row, 'textbook_id'),
    _text(row, 'lessons_id'),
    _text(row, 'id'),
  ].join(':');

  String _source(GrammarLookupRow row) {
    final book = [
      _text(row, 'book_name'),
      _text(row, 'book_volume'),
    ].where((value) => value.isNotEmpty).join('·');
    final lesson = _text(row, 'lesson_num');
    final title = _text(row, 'lesson_title');
    return [
      book,
      if (lesson.isNotEmpty) '第 $lesson 课',
      title,
    ].where((value) => value.isNotEmpty).join(' · ');
  }

  Widget _paragraph(GrammarLookupRow row, String key, {Color? color}) {
    final text = _text(row, key);
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        plainJapanese(text),
        style: TextStyle(
          fontSize: 15,
          height: 1.55,
          color: color,
          fontFamily: key.contains('definition') || key == 'tip' || key == 'lookup_meaning'
              ? 'PingFang SC'
              : 'Hiragino Sans',
        ),
      ),
    );
  }

  Widget _treeBody(List<GrammarLookupRow> rows, GrammarLookupRow match) {
    if (rows.isEmpty) return const Text('内容内容已变化，请重新查询。');
    final rootId = _text(match, 'id');
    final children = <String, List<GrammarLookupRow>>{};
    for (final row in rows) {
      children.putIfAbsent(_text(row, 'pid'), () => []).add(row);
    }
    final visited = <String>{};
    List<Widget> paragraphs(GrammarLookupRow item) {
      if (!visited.add(_text(item, 'id'))) return const [];
      final matched = _text(item, 'id') == _text(match, 'lookup_match_id') ||
          _text(item, 'id') == _text(match, 'lookup_evidence_id');
      final title = const ['4', '41'].contains(_text(item, 'type'));
      return [
        if (matched && _text(item, 'id') != rootId)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('本次匹配的文法或说明', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        if (_text(item, 'id') != rootId)
          _paragraph(item, 'content', color: title || matched ? Theme.of(context).colorScheme.primary : null),
        for (final field in ['definition', 'connection', 'example', 'example_definition', 'tip'])
          _paragraph(item, field, color: field == 'example_definition' ? Colors.grey : null),
        for (final child in children[_text(item, 'id')] ?? const <GrammarLookupRow>[])
          ...paragraphs(child),
      ];
    }
    final root = rows.firstWhere((row) => _text(row, 'id') == rootId, orElse: () => rows.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('匹配依据：${plainJapanese(_text(match, 'lookup_snippet'))}',
          style: const TextStyle(height: 1.55)),
        ...paragraphs(root),
      ],
    );
  }

  Widget _result(GrammarLookupRow row) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? const Color(0xFFDDDDDD) : const Color(0xFF595959);
    final titleColor = dark ? const Color(0xFFFFB366) : const Color(0xFFB85C00);
    final border = dark ? const Color(0xFF454545) : const Color(0xFFDDDDDD);
    final key = _rowKey(row);
    final expanded = _expandedRows.contains(key);
    final source = _source(row);
    return Padding(
      key: ValueKey(key),
      padding: const EdgeInsets.only(bottom: 12),
      child: StudyPanel(
        color: dark ? const Color(0xFF252525) : Colors.white,
        shape: RoundedRectangleBorder(side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: expanded,
              child: StudyInkWell(
                onTap: () => setState(() {
                  if (expanded) {
                    _expandedRows.remove(key);
                  } else {
                    _expandedRows.add(key);
                    _details.putIfAbsent(key, () => _repository.tree(row));
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plainJapanese(_text(row, 'content')),
                              style: TextStyle(
                                fontFamily: 'Hiragino Sans',
                                locale: const Locale('ja', 'JP'),
                                fontSize: 19,
                                height: 1.45,
                                fontWeight: FontWeight.w600,
                                color: titleColor,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                [_text(row, 'lookup_label'), _text(row, 'lookup_usage')]
                                    .where((value) => value.isNotEmpty).join(' · '),
                                style: TextStyle(fontSize: 12, color: foreground),
                              ),
                            ),
                            if (_text(row, 'lookup_meaning').isNotEmpty)
                              _paragraph(row, 'lookup_meaning'),
                            if (_text(row, 'lookup_match_id') != _text(row, 'id') &&
                                _text(row, 'lookup_meaning').isNotEmpty)
                              _paragraph(row, 'lookup_match_title', color: titleColor),
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                plainJapanese(_text(row, 'lookup_snippet')),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, height: 1.5),
                              ),
                            ),
                            if (source.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  source,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: Colors.grey),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: foreground,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (expanded) ...[
              StudyDivider(height: 1, thickness: 1, color: border),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 22),
                child: FutureBuilder<List<GrammarLookupRow>>(
                  future: _details[key],
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return TextButton(
                        onPressed: () => setState(() {
                          _details[key] = _repository.tree(row);
                        }),
                        child: const Text('内容加载失败，点击重试'),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: LinearProgressIndicator(),
                      );
                    }
                    return _treeBody(snapshot.data!, row);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _usageFilter == null ? _rows : _rows.where((row) =>
        _text(row, 'lookup_usage').split('·').contains(_usageFilter)).toList();
    final usages = _rows.expand((row) => _text(row, 'lookup_usage').split('·'))
        .where((value) => value.isNotEmpty).toSet().toList();
    final direct = _rows.where((row) => (row['lookup_score'] as int) >= 700).length;
    final composing = _controller.value.composing;
    final isComposing = composing.isValid && !composing.isCollapsed;
    return PlaybackScaffold(
      appBar: StudyAppBar(title: const Text('查文法')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (value) {
                  _debounce?.cancel();
                  final active = _controller.value.composing;
                  if (value.trim().isNotEmpty &&
                      (!active.isValid || active.isCollapsed)) _search(value);
                },
                decoration: InputDecoration(
                  hintText: '输入日语句型或中文含义',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _controller.clear();
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _controller.text.trim().isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          '输入日语句型或中文含义\n例如：必须、不必、即使……也……\n查询已导入内容中的文法',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : isComposing
                  ? const Center(child: Text('输入完成后查询'))
                  : _error != null
                  ? Center(child: Text(_error!))
                  : !_loading && _rows.isEmpty
                  ? Center(child: Text(_meaningsAvailable
                      ? '没有找到匹配的文法，可尝试简短的中文含义或日语句型'
                      : '中文含义资料暂不可用，正文中也未找到匹配'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: filtered.length + 1,
                      itemBuilder: (context, index) {
                        if (index > 0) return _result(filtered[index - 1]);
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _loading ? '正在查询…' : direct == 0
                                    ? '暂无标题或中文含义直接匹配，找到 ${_rows.length} 条正文参考'
                                    : '找到 $direct 条标题或中文含义匹配，${_rows.length - direct} 条正文参考',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (!_meaningsAvailable)
                                const Text('中文含义资料暂不可用，当前使用内容正文匹配。'),
                              if (usages.length > 1)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Wrap(
                                    spacing: 6,
                                    children: [
                                      ChoiceChip(label: const Text('全部'),
                                        selected: _usageFilter == null,
                                        onSelected: (_) => setState(() => _usageFilter = null)),
                                      for (final usage in usages)
                                        ChoiceChip(label: Text(usage),
                                          selected: _usageFilter == usage,
                                          onSelected: (selected) => setState(() =>
                                              _usageFilter = selected ? usage : null)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

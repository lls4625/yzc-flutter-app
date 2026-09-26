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
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _request++;
      setState(() {
        _rows = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () => _search(value));
  }

  Future<void> _search(String value) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _expandedRows.clear();
    });
    try {
      final rows = await _repository.search(value);
      if (!mounted || request != _request) return;
      setState(() {
        _rows = rows;
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
          fontFamily: key.contains('definition') || key == 'tip'
              ? 'PingFang SC'
              : 'Hiragino Sans',
        ),
      ),
    );
  }

  Widget _result(List<GrammarLookupRow> rows) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? const Color(0xFFDDDDDD) : const Color(0xFF595959);
    final titleColor = dark ? const Color(0xFFFFB366) : const Color(0xFFB85C00);
    final border = dark ? const Color(0xFF454545) : const Color(0xFFDDDDDD);
    final byId = {for (final row in rows) _text(row, 'id'): row};
    final children = <String, List<GrammarLookupRow>>{};
    for (final row in rows) {
      final parent = _text(row, 'pid');
      if (parent.isNotEmpty &&
          byId.containsKey(parent) &&
          parent != _text(row, 'id')) {
        children.putIfAbsent(parent, () => []).add(row);
      }
    }
    final row = rows.firstWhere(
      (candidate) =>
          _text(candidate, 'id') == _text(candidate, 'lookup_root_id'),
      orElse: () => rows.first,
    );
    final key = _rowKey(row);
    final expanded = _expandedRows.contains(key);
    final source = _source(row);
    final visited = <String>{_text(row, 'id')};
    List<Widget> paragraphs(GrammarLookupRow item) {
      final id = _text(item, 'id');
      if (!visited.add(id)) return const [];
      final subtitle = _text(item, 'type') == '4';
      return [
        _paragraph(item, 'content', color: subtitle ? titleColor : null),
        _paragraph(item, 'definition'),
        _paragraph(item, 'connection'),
        _paragraph(item, 'example'),
        _paragraph(item, 'example_definition', color: Colors.grey),
        _paragraph(item, 'tip'),
        for (final child in children[id] ?? const <GrammarLookupRow>[])
          ...paragraphs(child),
      ];
    }

    final body = <Widget>[
      for (final field in [
        'definition',
        'connection',
        'example',
        'example_definition',
        'tip',
      ])
        _paragraph(
          row,
          field,
          color: field == 'example_definition' ? Colors.grey : null,
        ),
      for (final child
          in children[_text(row, 'id')] ?? const <GrammarLookupRow>[])
        ...paragraphs(child),
    ];
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: body,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<List<GrammarLookupRow>> _groupedRows() {
    final groups = <String, List<GrammarLookupRow>>{};
    for (final row in _rows) {
      final rootId = _text(row, 'lookup_root_id');
      groups.putIfAbsent(rootId, () => <GrammarLookupRow>[]).add(row);
    }
    return groups.values.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupedRows();
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
                onChanged: _changed,
                decoration: InputDecoration(
                  hintText: '输入日语文法或中文解释',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _controller.clear();
                            _changed('');
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
                          '输入日语或中文关键词\n查询日文文法或中文翻译',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : _error != null
                  ? Center(child: Text(_error!))
                  : !_loading && _rows.isEmpty
                  ? const Center(child: Text('没有找到匹配的文法'))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
                          child: Text(
                            '找到 ${groups.length} 条结果',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        for (final rows in groups) _result(rows),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

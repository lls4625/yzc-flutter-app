import '../../../content_language.dart';
import '../../../content_typography.dart';
import '../../../l10n/l10n.dart';
import '../../demo_localization/ui.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../glass_ui.dart';
import '../../../lesson_presentation.dart';
import '../../../playback_scaffold.dart';
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
        _lastInput?.composing == next.composing)
      return;
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
    if (value.trim().isEmpty || (composing.isValid && !composing.isCollapsed))
      return;
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

  ContentLanguage _language(Map<String, Object?> row) =>
      ContentLanguage.fromTextbook({...row, 'id': row['textbook_id']});
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
      if (lesson.isNotEmpty || _text(row, 'lesson_code').isNotEmpty)
        lessonLabel(
          row,
          locale: Localizations.localeOf(context),
          lessonKey: 'lesson_code',
          numberKey: 'lesson_num',
        ),
      title,
    ].where((value) => value.isNotEmpty).join(' · ');
  }

  Widget _paragraph(GrammarLookupRow row, String key, {Color? color}) {
    final text = _text(row, key);
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        plainContentText(
          text,
          grammarFieldLanguage(
            _language(row),
            key,
            type: _text(
              row,
              key == 'lookup_match_title' ? 'lookup_match_type' : 'type',
            ),
            content: _text(
              row,
              key == 'lookup_match_title' ? 'lookup_match_title' : 'content',
            ),
          ),
        ),
        style: contentTextStyle(
          grammarFieldLanguage(
            _language(row),
            key,
            type: _text(
              row,
              key == 'lookup_match_title' ? 'lookup_match_type' : 'type',
            ),
            content: _text(
              row,
              key == 'lookup_match_title' ? 'lookup_match_title' : 'content',
            ),
          ),
        ).copyWith(fontSize: 15, height: 1.55, color: color),
      ),
    );
  }

  Widget _treeBody(List<GrammarLookupRow> rows, GrammarLookupRow match) {
    if (rows.isEmpty)
      return Text(
        context.tr(
          '内容内容已变化，请重新查询。',
          '內容已變更，請重新查詢。',
          'Content changed. Search again.',
          '内容が変わりました。検索し直してください。',
        ),
      );
    final rootId = _text(match, 'id');
    final children = <String, List<GrammarLookupRow>>{};
    for (final row in rows) {
      children.putIfAbsent(_text(row, 'pid'), () => []).add(row);
    }
    final visited = <String>{};
    List<Widget> paragraphs(GrammarLookupRow item) {
      if (!visited.add(_text(item, 'id'))) return const [];
      final matched =
          _text(item, 'id') == _text(match, 'lookup_match_id') ||
          _text(item, 'id') == _text(match, 'lookup_evidence_id');
      final title = const ['4', '41'].contains(_text(item, 'type'));
      return [
        if (matched && _text(item, 'id') != rootId)
          Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              context.tr(
                '本次匹配的文法或说明',
                '本次相符的文法或說明',
                'Matching grammar or explanation',
                '一致した文法または説明',
              ),
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        if (_text(item, 'id') != rootId)
          _paragraph(
            item,
            'content',
            color: title || matched
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
        for (final field in [
          'definition',
          'connection',
          'example',
          'example_definition',
          'tip',
        ])
          _paragraph(
            item,
            field,
            color: field == 'example_definition' ? Colors.grey : null,
          ),
        for (final child
            in children[_text(item, 'id')] ?? const <GrammarLookupRow>[])
          ...paragraphs(child),
      ];
    }

    final root = rows.firstWhere(
      (row) => _text(row, 'id') == rootId,
      orElse: () => rows.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          studyUi(
            context,
            '匹配依据：${plainContentText(_text(match, 'lookup_snippet'), grammarFieldLanguage(_language(match), _text(match, 'lookup_field'), type: _text(match, 'lookup_match_type'), content: _text(match, 'lookup_match_title')))}',
          ),
          style: const TextStyle(height: 1.55),
        ),
        ...paragraphs(root),
      ],
    );
  }

  Widget _result(GrammarLookupRow row) {
    if (ContentLanguage.tryFromTextbook({...row, 'id': row['textbook_id']}) ==
        null)
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          context.tr(
            '内容包语言配置无效，请下载修正版。',
            '內容包語言設定無效，請下載修正版。',
            'Invalid package language settings. Download a corrected package.',
            'パッケージの言語設定が無効です。修正版をダウンロードしてください。',
          ),
        ),
      );
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
      child: StudyCard(
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
                              plainContentText(
                                _text(row, 'content'),
                                _language(row).sourceLanguage,
                              ),
                              style:
                                  contentTextStyle(
                                    _language(row).sourceLanguage,
                                  ).copyWith(
                                    fontSize: 19,
                                    height: 1.45,
                                    fontWeight: FontWeight.w600,
                                    color: titleColor,
                                  ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                [
                                      _text(row, 'lookup_label'),
                                      _text(row, 'lookup_usage'),
                                    ]
                                    .where((value) => value.isNotEmpty)
                                    .join(' · '),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: foreground,
                                ),
                              ),
                            ),
                            if (_text(row, 'lookup_meaning').isNotEmpty)
                              _paragraph(row, 'lookup_meaning'),
                            if (_text(row, 'lookup_match_id') !=
                                    _text(row, 'id') &&
                                _text(row, 'lookup_meaning').isNotEmpty)
                              _paragraph(
                                row,
                                'lookup_match_title',
                                color: titleColor,
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                plainContentText(
                                  _text(row, 'lookup_snippet'),
                                  grammarFieldLanguage(
                                    _language(row),
                                    _text(row, 'lookup_field'),
                                    type: _text(row, 'lookup_match_type'),
                                    content: _text(row, 'lookup_match_title'),
                                  ),
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                ),
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
                        child: Text(
                          context.tr(
                            '内容加载失败，点击重试',
                            '內容載入失敗，點擊重試',
                            'Could not load content. Tap to retry.',
                            '内容を読み込めませんでした。タップして再試行',
                          ),
                        ),
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
    final filtered = _usageFilter == null
        ? _rows
        : _rows
              .where(
                (row) => _text(
                  row,
                  'lookup_usage',
                ).split('·').contains(_usageFilter),
              )
              .toList();
    final usages = _rows
        .expand((row) => _text(row, 'lookup_usage').split('·'))
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    final direct = _rows
        .where((row) => (row['lookup_score'] as int) >= 700)
        .length;
    final composing = _controller.value.composing;
    final isComposing = composing.isValid && !composing.isCollapsed;
    return PlaybackScaffold(
      appBar: StudyAppBar(
        title: Text(context.tr('查文法', '查文法', 'Grammar search', '文法検索')),
      ),
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
                      (!active.isValid || active.isCollapsed))
                    _search(value);
                },
                decoration: InputDecoration(
                  hintText: context.tr(
                    '输入句型或含义',
                    '輸入句型或含義',
                    'Enter a pattern or meaning',
                    '文型または意味を入力',
                  ),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.tr('清空', '清除', 'Clear', 'クリア'),
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
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          context.tr(
                            '输入句型或含义\n查询已导入内容中的文法',
                            '輸入句型或含義\n搜尋已匯入內容的文法',
                            'Enter a pattern or meaning\nSearch grammar in imported content',
                            '文型または意味を入力\n取り込み済みコンテンツの文法を検索',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : isComposing
                  ? Center(
                      child: Text(
                        context.tr(
                          '输入完成后查询',
                          '輸入後查詢',
                          'Search after typing',
                          '入力後に検索',
                        ),
                      ),
                    )
                  : _error != null
                  ? Center(child: Text(studyUi(context, _error!)))
                  : !_loading && _rows.isEmpty
                  ? Center(
                      child: Text(
                        studyUi(
                          context,
                          _meaningsAvailable
                              ? '没有找到匹配的文法，可尝试简短的中文含义或日语句型'
                              : '中文含义资料暂不可用，正文中也未找到匹配',
                        ),
                      ),
                    )
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
                                studyUi(
                                  context,
                                  _loading
                                      ? '正在查询…'
                                      : direct == 0
                                      ? '暂无标题或中文含义直接匹配，找到 ${_rows.length} 条正文参考'
                                      : '找到 $direct 条标题或中文含义匹配，${_rows.length - direct} 条正文参考',
                                ),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (!_meaningsAvailable)
                                Text(
                                  context.tr(
                                    '增强含义索引暂不可用，当前使用内容正文匹配。',
                                    '增強含義索引暫不可用，目前使用內容正文比對。',
                                    'The enhanced meaning index is unavailable. Searching the content text instead.',
                                    '拡張意味索引を利用できないため、本文から検索しています。',
                                  ),
                                ),
                              if (usages.length > 1)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Wrap(
                                    spacing: 6,
                                    children: [
                                      ChoiceChip(
                                        label: Text(studyUi(context, '全部')),
                                        selected: _usageFilter == null,
                                        onSelected: (_) =>
                                            setState(() => _usageFilter = null),
                                      ),
                                      for (final usage in usages)
                                        ChoiceChip(
                                          label: Text(usage),
                                          selected: _usageFilter == usage,
                                          onSelected: (selected) => setState(
                                            () => _usageFilter = selected
                                                ? usage
                                                : null,
                                          ),
                                        ),
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

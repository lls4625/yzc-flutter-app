import 'dart:convert';

import 'package:flutter/services.dart';

import '../../host_contracts.dart';

typedef GrammarLookupRow = Map<String, Object?>;

String grammarText(GrammarLookupRow row, String key) =>
    row[key]?.toString() ?? '';

// Search-only normalization; displayed textbook text remains untouched.
String normalizeGrammar(String text) => text
    .replaceAllMapped(RegExp(r'!([^!\s()]+)\([^)]*\)'), (m) => m[1]!)
    .replaceAll(RegExp(r'''[\s!＊*∫～~…。，、：:；;！？!?“”"‘’'（）()\[\]【】＋+／/·]'''), '')
    .toLowerCase();

class GrammarLookupSearch {
  const GrammarLookupSearch(this.rows, {required this.meaningsAvailable});
  final List<GrammarLookupRow> rows;
  final bool meaningsAvailable;
}

class _Meaning {
  _Meaning(Map<String, dynamic> data)
    : book = data['textbook_id'] as String,
      id = data['grammar_id'] as String,
      title = data['title'] as String,
      usage = data['usage'] as String,
      meaning = data['meaning'] as String,
      evidenceId = data['evidence_id'] as String,
      evidence = data['evidence'] as String,
      aliases = (data['aliases'] as List).cast<String>();
  final String book, id, title, usage, meaning, evidenceId, evidence;
  final List<String> aliases;
}

class _Hit {
  const _Hit(this.row, this.score, this.label, this.snippet, {
    this.meaning = '', this.usage = '', this.evidenceId = '',
  });
  final GrammarLookupRow row;
  final int score;
  final String label, snippet, meaning, usage, evidenceId;
}

class GrammarLookupRepository {
  GrammarLookupRepository(this.host);
  final StudyRoomHost host;
  List<_Meaning>? _meanings;

  String _key(GrammarLookupRow row) =>
      '${grammarText(row, 'textbook_id')}:${grammarText(row, 'id')}';

  Future<List<_Meaning>> _loadMeanings() async {
    if (_meanings != null) return _meanings!;
    final source = await rootBundle.loadString('assets/grammar_lookup/meanings.json');
    final data = jsonDecode(source) as Map<String, dynamic>;
    if (data['version'] != 1) throw const FormatException('文法检索资料版本不支持');
    return _meanings = [
      for (final item in data['entries'] as List)
        _Meaning(item as Map<String, dynamic>),
    ];
  }

  String _query(String input) {
    var text = input.trim();
    // Strip complete question wrappers, never negation or arbitrary words.
    final patterns = [
      RegExp(r'^(?:请问)?(?:表示|表达)(.+?)(?:的)?(?:日语)?(?:语法|文法|句型)[？?]?$'),
      RegExp(r'^(?:请问)?(.+?)(?:用日语|日语)?怎么说[？?]?$'),
      RegExp(r'^(.+?)的(?:日语)?(?:语法|文法|句型)[？?]?$'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        text = match[1]!;
        break;
      }
    }
    return text;
  }

  String _excerpt(String content, String query) {
    final flat = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= 150) return flat;
    final index = flat.indexOf(query);
    final start = index > 40 ? index - 40 : 0;
    final end = start + 150 < flat.length ? start + 150 : flat.length;
    return '${start > 0 ? '…' : ''}${flat.substring(start, end)}'
        '${end < flat.length ? '…' : ''}';
  }

  Future<GrammarLookupSearch> search(String input) async {
    final query = _query(input);
    final needle = normalizeGrammar(query);
    if (needle.isEmpty) {
      return const GrammarLookupSearch([], meaningsAvailable: true);
    }
    final literalNeedles = {normalizeGrammar(input), needle};
    // Re-read installed content on every search: no stale cache after imports.
    // Examples and complete grammar trees load only when a card is expanded.
    final rows = await host.database.rawQuery('''
      SELECT g.*, b.textbook AS book_name, b.volume AS book_volume,
        l.lesson AS lesson_code, l.num AS lesson_num, l.title AS lesson_title
      FROM yzc_grammar g
      LEFT JOIN yzc_textbook b ON b.id=g.textbook_id
      LEFT JOIN yzc_lessons l ON l.id=g.lessons_id
      WHERE g.type IN ('1','2','4','41','9')
      ORDER BY b.sort IS NULL, b.sort, l.num IS NULL, l.num,
        g.sort IS NULL, g.sort, g.id
    ''');
    final byKey = {for (final row in rows) _key(row): row};
    final roots = <String, GrammarLookupRow>{};
    for (final row in rows) {
      if (grammarText(row, 'type') == '1') roots[_key(row)] = row;
    }
    GrammarLookupRow? rootOf(GrammarLookupRow row) {
      GrammarLookupRow? current = row;
      final visited = <String>{};
      while (current != null && visited.add(_key(current))) {
        if (grammarText(current, 'type') == '1') return current;
        current = byKey['${grammarText(current, 'textbook_id')}:'
            '${grammarText(current, 'pid')}'];
      }
      return null;
    }

    var meaningsAvailable = true;
    List<_Meaning> meanings;
    try {
      meanings = await _loadMeanings();
    } catch (_) {
      meaningsAvailable = false;
      meanings = [];
    }
    final hits = <String, _Hit>{};
    void add(_Hit hit) {
      final root = rootOf(hit.row);
      if (root == null) return;
      final key = _key(root);
      // Maximum score avoids rewarding repeated words in long explanations.
      if (!hits.containsKey(key) || hit.score > hits[key]!.score) hits[key] = hit;
    }

    final terms = query.split(RegExp(r'\s+')).map(normalizeGrammar)
        .where((word) => word.isNotEmpty).toList();
    for (final item in meanings) {
      final row = byKey['${item.book}:${item.id}'];
      final evidence = byKey['${item.book}:${item.evidenceId}'];
      if (row == null || evidence == null ||
          grammarText(row, 'content') != item.title ||
          grammarText(evidence, 'content') != item.evidence ||
          grammarText(evidence, 'pid') != item.id) continue;
      final aliases = item.aliases.map(normalizeGrammar).toSet();
      final usageTerms = item.usage.split('·').map(normalizeGrammar).toSet();
      final exact = aliases.contains(needle) || normalizeGrammar(item.meaning) == needle;
      final allTerms = terms.length > 1 &&
          terms.every((term) => aliases.contains(term) || usageTerms.contains(term));
      if (exact || allTerms) {
        add(_Hit(row, exact ? 950 : 900, '中文含义匹配',
            _excerpt(item.evidence, query), meaning: item.meaning,
            usage: item.usage, evidenceId: item.evidenceId));
      }
    }
    for (final row in rows) {
      final content = grammarText(row, 'content');
      final normalized = normalizeGrammar(content);
      if (!literalNeedles.any(normalized.contains)) continue;
      final title = const ['1', '4', '41'].contains(grammarText(row, 'type'));
      final score = title ? (literalNeedles.contains(normalized) ? 1000 : 700)
          : grammarText(row, 'type') == '2' ? 300 : 100;
      add(_Hit(row, score, title ? '文法标题匹配' : '说明中提及',
          _excerpt(content, query)));
    }
    final order = {for (var i = 0; i < rows.length; i++) _key(rows[i]): i};
    final keys = hits.keys.toList()..sort((a, b) {
      final score = hits[b]!.score.compareTo(hits[a]!.score);
      return score != 0 ? score : order[a]!.compareTo(order[b]!);
    });
    return GrammarLookupSearch([
      for (final key in keys) {
        ...roots[key]!,
        'lookup_root_id': grammarText(roots[key]!, 'id'),
        'lookup_match_id': grammarText(hits[key]!.row, 'id'),
        'lookup_evidence_id': hits[key]!.evidenceId,
        'lookup_match_title': grammarText(hits[key]!.row, 'content'),
        'lookup_score': hits[key]!.score,
        'lookup_label': hits[key]!.label,
        'lookup_snippet': hits[key]!.snippet,
        'lookup_meaning': hits[key]!.meaning,
        'lookup_usage': hits[key]!.usage,
      },
    ], meaningsAvailable: meaningsAvailable);
  }

  Future<List<GrammarLookupRow>> tree(GrammarLookupRow root) =>
      host.database.rawQuery('''
        WITH RECURSIVE tree(id) AS (
          SELECT id FROM yzc_grammar WHERE id=? AND textbook_id=?
          UNION
          SELECT child.id FROM yzc_grammar child JOIN tree ON child.pid=tree.id
          WHERE child.textbook_id=?
        )
        SELECT g.* FROM tree JOIN yzc_grammar g ON g.id=tree.id
        WHERE g.textbook_id=? ORDER BY g.sort IS NULL, g.sort, g.id
      ''', [root['id'], root['textbook_id'], root['textbook_id'], root['textbook_id']]);
}

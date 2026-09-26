import '../../host_contracts.dart';

typedef GrammarLookupRow = Map<String, Object?>;

class GrammarLookupRepository {
  GrammarLookupRepository(this.host);
  final StudyRoomHost host;

  String _pattern(String input) {
    final escaped = input
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    return '%$escaped%';
  }

  Future<List<GrammarLookupRow>> search(String input) async {
    final keyword = input.trim();
    if (keyword.isEmpty) return const [];
    final pattern = _pattern(keyword);
    return host.database.rawQuery(
      '''
      WITH RECURSIVE
      matched(id, pid, type) AS (
        SELECT id, pid, type
        FROM yzc_grammar
        WHERE type IN ('1', '2', '4', '41', '9')
          AND content LIKE ? ESCAPE '\\'
      ),
      ancestors(id, pid, type) AS (
        SELECT id, pid, type FROM matched
        UNION
        SELECT parent.id, parent.pid, parent.type
        FROM yzc_grammar parent
        JOIN ancestors child ON child.pid=parent.id
      ),
      roots(id) AS (
        SELECT DISTINCT id FROM ancestors WHERE type='1'
      ),
      grammar_tree(root_id, id) AS (
        SELECT id, id FROM roots
        UNION
        SELECT tree.root_id, child.id
        FROM grammar_tree tree
        JOIN yzc_grammar child ON child.pid=tree.id
        WHERE child.id<>tree.id
      )
      SELECT g.*, grammar_tree.root_id AS lookup_root_id,
        root.sort AS lookup_root_sort,
        b.textbook AS book_name, b.volume AS book_volume,
        l.num AS lesson_num, l.title AS lesson_title
      FROM grammar_tree
      JOIN yzc_grammar g ON g.id=grammar_tree.id
      JOIN yzc_grammar root ON root.id=grammar_tree.root_id
      LEFT JOIN yzc_textbook b ON b.id=g.textbook_id
      LEFT JOIN yzc_lessons l ON l.id=g.lessons_id
      ORDER BY b.sort IS NULL, b.sort,
        l.num IS NULL, l.num,
        lookup_root_sort IS NULL, lookup_root_sort,
        grammar_tree.root_id,
        g.sort IS NULL, g.sort,
        g.id
    ''',
      [pattern],
    );
  }
}

import '../../host_contracts.dart';

typedef WordLookupRow = Map<String, Object?>;

class WordLookupRepository {
  WordLookupRepository(this.host);
  final StudyRoomHost host;

  String _pattern(String input) {
    final escaped = input.replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%').replaceAll('_', r'\_');
    return '%$escaped%';
  }

  Future<List<WordLookupRow>> search(String input) async {
    final keyword = input.trim();
    if (keyword.isEmpty) return const [];
    final pattern = _pattern(keyword);
    return host.database.rawQuery('''
      SELECT w.*, b.textbook AS book_name, b.volume AS book_volume,
        l.lesson AS lesson_code, l.num AS lesson_num
      FROM yzc_words w
      LEFT JOIN yzc_textbook b ON b.id=w.textbook_id
      LEFT JOIN yzc_lessons l ON l.id=w.lessons_id
      WHERE w.word LIKE ? ESCAPE '\\'
        OR w.kana LIKE ? ESCAPE '\\'
        OR w.kanji LIKE ? ESCAPE '\\'
        OR w.definition LIKE ? ESCAPE '\\'
      ORDER BY b.sort IS NULL, b.sort,
        l.num IS NULL, l.num,
        w.sort IS NULL, w.sort,
        w.id
    ''', [
      pattern, pattern, pattern, pattern,
    ]);
  }
}

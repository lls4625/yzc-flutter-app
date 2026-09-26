// Independent demo snapshot; maintained separately from the real flashcards.
import 'dart:convert';

enum FlashDemoDirection {
  japanese('日语 → 中文'),
  chinese('中文 → 日语');

  const FlashDemoDirection(this.label);
  final String label;
}

String flashDemoText(Object? value) => (value?.toString() ?? '')
    .replaceAllMapped(RegExp(r'!([^!\s()]+)\([^)]*\)'), (m) => m[1]!)
    .replaceAll('!', '')
    .trim();

class FlashDemoWord {
  const FlashDemoWord({
    required this.bookId,
    required this.lessonId,
    required this.id,
    required this.japanese,
    required this.kana,
    required this.chinese,
    required this.pos,
    required this.source,
  });
  final String bookId, lessonId, id, japanese, kana, chinese, pos, source;
  String get key => jsonEncode([bookId, lessonId, id]);
  Map<String, Object?> toJson() => {
    'book': bookId,
    'lesson': lessonId,
    'id': id,
    'japanese': japanese,
    'kana': kana,
    'chinese': chinese,
    'pos': pos,
    'source': source,
  };
  factory FlashDemoWord.fromJson(Map<String, dynamic> row) => FlashDemoWord(
    bookId: row['book'] as String,
    lessonId: row['lesson'] as String,
    id: row['id'] as String,
    japanese: row['japanese'] as String,
    kana: row['kana'] as String,
    chinese: row['chinese'] as String,
    pos: row['pos'] as String,
    source: row['source'] as String,
  );
}

class FlashDemoSession {
  FlashDemoSession({
    required this.id,
    required this.direction,
    required this.words,
    required this.version,
    this.index = 0,
    Map<String, bool>? marks,
  }) : marks = marks ?? {};
  final String id, version;
  final FlashDemoDirection direction;
  final List<FlashDemoWord> words;
  final int index;
  final Map<String, bool> marks;
  bool get complete => index >= words.length;
  List<FlashDemoWord> get weak =>
      words.where((w) => marks[w.key] == false).toList();
  FlashDemoSession marked(bool known) => FlashDemoSession(
    id: id,
    direction: direction,
    words: words,
    version: version,
    index: index + 1,
    marks: {...marks, words[index].key: known},
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'direction': direction.name,
    'words': words.map((w) => w.toJson()).toList(),
    'version': version,
    'index': index,
    'marks': marks,
  };
  factory FlashDemoSession.fromJson(Map<String, dynamic> row) {
    final words = (row['words'] as List)
        .map((w) => FlashDemoWord.fromJson(Map<String, dynamic>.from(w as Map)))
        .toList();
    final index = row['index'] as int;
    final marks = Map<String, bool>.from(row['marks'] as Map);
    if (words.isEmpty ||
        index < 0 ||
        index > words.length ||
        words.map((w) => w.key).toSet().length != words.length ||
        marks.length != index ||
        words.take(index).any((w) => !marks.containsKey(w.key))) {
      throw const FormatException('闪卡草稿不完整');
    }
    return FlashDemoSession(
      id: row['id'] as String,
      direction: FlashDemoDirection.values.byName(row['direction'] as String),
      words: words,
      version: row['version'] as String,
      index: index,
      marks: marks,
    );
  }
}

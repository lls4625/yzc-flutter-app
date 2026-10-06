/// Presentation-only lesson metadata. Database ids, codes and numbers stay intact.
final _specialLessonCode = RegExp(r'^([rp])([0-9]+)$');

RegExpMatch? _specialLesson(Map<String, Object?> row, String key) {
  final code = row[key]?.toString() ?? '';
  final match = _specialLessonCode.firstMatch(code);
  return match != null && match.end == code.length ? match : null;
}

bool isRegularLesson(Map<String, Object?> row) =>
    _specialLesson(row, 'lesson') == null;

String lessonLabel(
  Map<String, Object?> row, {
  String lessonKey = 'lesson',
  String numberKey = 'num',
}) {
  final special = _specialLesson(row, lessonKey);
  if (special != null) {
    final number = BigInt.parse(special[2]!).toString();
    return '${special[1] == 'r' ? '复习' : '预备'}$number';
  }
  return '第${row[numberKey] ?? ''}课';
}

/// Prep lessons come first. Reviews follow regular lessons with the same num.
/// The input order breaks all remaining ties, including duplicate num values.
List<Map<String, Object?>> sortLessons(Iterable<Map<String, Object?>> rows) {
  final indexed = rows.toList().asMap().entries.toList();
  int compareNumber(Object? a, Object? b) {
    final left = num.tryParse(a?.toString() ?? '');
    final right = num.tryParse(b?.toString() ?? '');
    if (left == null) return right == null ? 0 : 1;
    if (right == null) return -1;
    return left.compareTo(right);
  }

  indexed.sort((a, b) {
    final left = _specialLesson(a.value, 'lesson');
    final right = _specialLesson(b.value, 'lesson');
    final leftPrep = left?[1] == 'p';
    final rightPrep = right?[1] == 'p';
    if (leftPrep != rightPrep) return leftPrep ? -1 : 1;
    final number = leftPrep
        ? BigInt.parse(left![2]!).compareTo(BigInt.parse(right![2]!))
        : compareNumber(a.value['num'], b.value['num']);
    if (number != 0) return number;
    final leftReview = left?[1] == 'r';
    final rightReview = right?[1] == 'r';
    if (leftReview != rightReview) return leftReview ? 1 : -1;
    return a.key.compareTo(b.key);
  });
  return [for (final entry in indexed) entry.value];
}

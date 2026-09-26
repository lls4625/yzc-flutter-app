import 'dart:math';

typedef Json = Map<String, dynamic>;
const levels = ['N5'];
const typeNames = {
  'V_KANJI_READING': '汉字读音', 'V_ORTHOGRAPHY': '表记',
  'V_WORD_FORMATION': '构词', 'V_CONTEXT': '语境词汇',
  'V_PARAPHRASE': '近义改写', 'V_USAGE': '词语用法',
  'G_FORM': '语法形式', 'G_COMPOSITION': '句子组合', 'G_TEXT': '篇章语法',
  'R_SHORT': '短文理解', 'R_MEDIUM': '中篇理解', 'R_LONG': '长文理解',
  'R_INTEGRATED': '多篇整合理解', 'R_THEMATIC': '主张理解',
  'R_INFORMATION': '信息检索', 'L_TASK': '课题理解', 'L_POINT': '要点理解',
  'L_SUMMARY': '概要理解', 'L_UTTERANCE': '情境发话',
  'L_RESPONSE': '即时应答', 'L_INTEGRATED': '综合听力',
};

class Question {
  Question(this.data);
  final Json data;
  String get id => data['id'] as String;
  String get type => data['type_code'] as String;
  String get typeName => typeNames[type] ?? type;
  String get stem => data['stem_json']['text'] as String;
  Json get material => data['material_json'] as Json;
  Json get presentation => data['presentation_json'] as Json;
  List<Json> get options => (data['options_json'] as List).cast<Json>();
  String get correct => (data['answer_json']['correct_option_ids'] as List).single.toString();
  String get explanation => data['explanation_json']['summary'] as String? ?? '';
  bool get listening => type.startsWith('L_');
  String get transcript => material['transcript'] as String? ?? '';
  String get scoreBand => data['score_section_code'] as String;
  String get clock => data['exam_section_code'] as String;
  int get phase => listening ? 2 : type.startsWith('V_') ? 0 : 1;
}

class Bank {
  Bank(this.data);
  final Json data;
  List<Json> get papers => (data['papers'] as List).cast<Json>();
  late final Map<String, List<Question>> byType = _index();
  Map<String, List<Question>> _index() {
    final seen = <String>{};
    final result = <String, List<Question>>{};
    for (final paper in papers) {
      for (final raw in (paper['questions'] as List).cast<Json>()) {
        final q = Question(raw);
        if (seen.add('${q.id}:${raw['version']}')) {
          result.putIfAbsent(q.type, () => []).add(q);
        }
      }
    }
    return result;
  }

  /// Prefer complete groups. A practice-only adaptation may select a subset
  /// of the final group to honor the requested count; full material remains
  /// embedded in each question. Authored exam papers are never sampled here.
  List<Question> practice(String type, int target, {bool randomize = true}) {
    final groups = <String, List<Question>>{};
    for (final q in byType[type] ?? <Question>[]) {
      final key = q.data['selection_policy'] == 'whole_group'
          ? q.data['group_id'] as String? ?? q.id : q.id;
      groups.putIfAbsent(key, () => []).add(q);
    }
    final units = groups.values.toList();
    if (randomize) units.shuffle(Random());
    for (final unit in units) {
      unit.sort((a, b) => (a.data['group_order'] as int).compareTo(b.data['group_order'] as int));
    }
    final paths = <int, List<int>>{0: []};
    final largest = units.fold<int>(0, (n, g) => max(n, g.length));
    for (var i = 0; i < units.length; i++) {
      for (final count in paths.keys.toList().reversed) {
        final next = count + units[i].length;
        if (next <= target + largest && !paths.containsKey(next)) {
          paths[next] = [...paths[count]!, i];
        }
      }
      if (paths.containsKey(target)) break;
    }
    final sizes = paths.keys.where((n) => n >= target).toList()..sort();
    if (sizes.isEmpty) return [];
    return [for (final i in paths[sizes.first]!) ...units[i]].take(target).toList();
  }

  bool hasPartialGroup(List<Question> selection) {
    final grouped = <String, int>{};
    for (final q in selection.where((q) => q.data['selection_policy'] == 'whole_group')) {
      final id = q.data['group_id'] as String? ?? q.id;
      grouped[id] = (grouped[id] ?? 0) + 1;
    }
    return selection.any((q) => q.data['selection_policy'] == 'whole_group' &&
      (grouped[q.data['group_id'] ?? q.id] ?? 0) < (q.data['group_size'] as int));
  }
}

class Attempt {
  Attempt(this.snapshot, this.progress);
  final Json snapshot, progress;
  String get id => snapshot['id'] as String;
  String get title => snapshot['title'] as String;
  String get level => snapshot['level'] as String;
  bool get submitted => progress['submitted'] == true;
  late final List<Question> questions = (snapshot['questions'] as List)
      .cast<Json>().map(Question.new).toList();
  Map<String, dynamic> get answers => progress['answers'] as Json;
  List<dynamic> get flags => progress['flags'] as List;
  List<dynamic> get revealed => progress['revealed'] as List;
  Json get elapsed => progress['elapsed'] as Json;
  int get position => progress['position'] as int;
  set position(int value) => progress['position'] = value;
  bool correct(Question q) => answers[q.id] == q.correct;
  static Attempt create(String level, String title, List<Question> questions,
      {Json? paper}) {
    final now = DateTime.now().toUtc().toIso8601String();
    return Attempt({
      'id': '$now-${Random.secure().nextInt(1 << 32)}',
      'title': title, 'level': level, 'created': now,
      'questions': questions.map((q) => q.data).toList(),
      'parts': paper?['parts'] ?? [], 'score_policy': paper?['score_policy'],
      'paper_id': paper?['id'], 'paper_version': paper?['version'],
    }, {
      'answers': <String, dynamic>{}, 'flags': <String>[],
      'revealed': <String>[], 'elapsed': <String, dynamic>{},
      'position': 0, 'submitted': false, 'completed_phases': <int>[],
    });
  }
}

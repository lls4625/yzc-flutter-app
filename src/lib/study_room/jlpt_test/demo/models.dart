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

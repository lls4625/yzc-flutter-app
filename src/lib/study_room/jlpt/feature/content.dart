import 'dart:convert';
import 'package:sqflite/sqflite.dart';

typedef StudyJson = Map<String, dynamic>;
const studyContentTables = [
  'stydy_jlpt_question', 'stydy_jlpt_blueprint',
  'stydy_jlpt_paper', 'stydy_jlpt_paper_item',
];
const studyLevels = ['N1', 'N2', 'N3', 'N4', 'N5'];
const studyTypes = {
  'V_KANJI_READING', 'V_ORTHOGRAPHY', 'V_WORD_FORMATION', 'V_CONTEXT',
  'V_PARAPHRASE', 'V_USAGE', 'G_FORM', 'G_COMPOSITION', 'G_TEXT',
  'R_SHORT', 'R_MEDIUM', 'R_LONG', 'R_INTEGRATED', 'R_THEMATIC',
  'R_INFORMATION', 'L_TASK', 'L_POINT', 'L_SUMMARY', 'L_UTTERANCE',
  'L_RESPONSE', 'L_INTEGRATED',
};

dynamic studyJson(Object? value) {
  if (value is! String) throw const FormatException('题库 JSON 字段为空');
  return jsonDecode(value);
}

StudyJson decodeStudyQuestion(Map<String, Object?> row) {
  final result = Map<String, dynamic>.from(row);
  for (final name in ['source_json', 'stem_json', 'options_json', 'response_json',
    'answer_json', 'explanation_json', 'material_json', 'presentation_json', 'tags_json']) {
    result[name] = studyJson(row[name]);
  }
  validateStudyQuestion(result);
  return result;
}

void validateStudyQuestion(StudyJson q) {
  final options = q['options_json'];
  final answers = q['answer_json'];
  final stem = q['stem_json'];
  if (q['id'] is! String || (q['id'] as String).isEmpty ||
      q['version'] is! int || (q['version'] as int) < 1 ||
      q['schema_version'] != '1.0.0' || !studyLevels.contains(q['level']) ||
      !studyTypes.contains(q['type_code']) || stem is! Map ||
      stem['text'] is! String || (stem['text'] as String).trim().isEmpty ||
      q['material_json'] is! Map || q['presentation_json'] is! Map ||
      q['explanation_json'] is! Map || q['group_order'] is! int ||
      q['exam_section_code'] is! String || q['score_section_code'] is! String ||
      options is! List || options.length < 2 || answers is! Map) {
    throw const FormatException('题目内容或版本不受支持');
  }
  final ids = <String>{};
  for (final option in options) {
    if (option is! Map || option['id'] is! String || option['text'] is! String ||
        !ids.add(option['id'] as String)) throw const FormatException('题目选项无效');
  }
  final correct = answers['correct_option_ids'];
  if (correct is! List || correct.length != 1 || !ids.contains(correct.single)) {
    throw const FormatException('题目答案无效');
  }
}

/// Used exclusively by formal JLPT features and the formal resource installer.
Future<StudyJson> readStudyBank(DatabaseExecutor db, String level,
    {bool practice = false, bool allVersions = false}) async {
  if (!studyLevels.contains(level)) throw const FormatException('考试等级无效');
  if (practice) {
    final rows = await db.rawQuery('''SELECT q.* FROM stydy_jlpt_question q
      WHERE q.level=? AND NOT EXISTS (SELECT 1 FROM stydy_jlpt_question newer
        WHERE newer.id=q.id AND newer.version>q.version) ORDER BY q.id''', [level]);
    return {'papers': [if (rows.isNotEmpty) {'questions': rows.map(decodeStudyQuestion).toList()}]};
  }
  final papers = await db.rawQuery('''SELECT p.* FROM stydy_jlpt_paper p
    WHERE p.level=? ${allVersions ? '' : 'AND NOT EXISTS (SELECT 1 FROM stydy_jlpt_paper newer WHERE newer.id=p.id AND newer.version>p.version)'}
    ORDER BY p.id,p.version''', [level]);
  final questionRows = await db.query('stydy_jlpt_question', where: 'level=?', whereArgs: [level]);
  final byVersion = <String, StudyJson>{};
  for (final row in questionRows) {
    byVersion[jsonEncode([row['id'], row['version']])] = decodeStudyQuestion(row);
  }
  final result = <StudyJson>[];
  for (final p in papers) {
    final items = await db.query('stydy_jlpt_paper_item',
      where: 'paper_id=? AND paper_version=?', whereArgs: [p['id'], p['version']], orderBy: 'position');
    final questions = <StudyJson>[];
    for (final item in items) {
      final raw = byVersion[jsonEncode([item['question_id'], item['question_version']])];
      if (raw == null || item['position'] is! int || (item['position'] as int) < 1 ||
          item['item_id'] is! String || (item['item_id'] as String).isEmpty) {
        throw const FormatException('试卷题目关联不完整');
      }
      final question = Map<String, dynamic>.from(raw);
      final optionOrder = studyJson(item['option_order_json']);
      if (optionOrder is! List) throw const FormatException('试卷选项顺序无效');
      if (optionOrder.isNotEmpty) {
        final options = (question['options_json'] as List).cast<StudyJson>();
        if (optionOrder.length != options.length || optionOrder.toSet().length != options.length ||
            !options.every((o) => optionOrder.contains(o['id']))) {
          throw const FormatException('试卷选项顺序与题目不一致');
        }
        question['options_json'] = [for (final id in optionOrder) options.firstWhere((o) => o['id'] == id)];
      }
      question['paper_position'] = item['position'];
      question['item_id'] = item['item_id'];
      questions.add(question);
    }
    final parts = studyJson(p['parts_json']);
    final allocation = studyJson(p['type_allocation_json']);
    final score = studyJson(p['score_policy_json']);
    if (parts is! List || allocation is! List || score is! Map || score['bands'] is! List ||
        p['id'] is! String || p['version'] is! int || (p['version'] as int) < 1 ||
        p['title'] is! String || questions.isEmpty || p['question_count'] != questions.length) {
      throw const FormatException('试卷结构不完整');
    }
    for (final part in parts) {
      if (part is! Map || part['code'] is! String || part['recommended_seconds'] is! int) {
        throw const FormatException('试卷计时信息无效');
      }
    }
    final partCodes = [for (final part in parts) (part as Map)['code'] as String];
    final expectedPartCodes = ['N1', 'N2'].contains(p['level'])
        ? const ['language_reading', 'listening']
        : const ['vocabulary', 'grammar_reading', 'listening'];
    if (partCodes.length != expectedPartCodes.length ||
        partCodes.toSet().length != partCodes.length ||
        [for (var i = 0; i < partCodes.length; i++) partCodes[i] == expectedPartCodes[i]].contains(false)) {
      throw const FormatException('试卷考试部分与等级不一致');
    }
    if (partCodes.any((code) => !questions.any((q) => q['exam_section_code'] == code))) {
      throw const FormatException('试卷考试部分没有题目');
    }
    for (final a in allocation) {
      if (a is! Map || !studyTypes.contains(a['type_code'])) throw const FormatException('试卷题型无效');
    }
    for (final band in score['bands'] as List) {
      if (band is! Map || band['code'] is! String || band['max_score'] is! num) {
        throw const FormatException('试卷评分信息无效');
      }
    }
    for (final q in questions) {
      if (!parts.any((p) => p['code'] == q['exam_section_code']) ||
          !allocation.any((a) => a['type_code'] == q['type_code'])) {
        throw const FormatException('试卷分段或题型关联不完整');
      }
    }
    var previousPartIndex = 0;
    for (final q in questions) {
      final partIndex = partCodes.indexOf(q['exam_section_code'] as String);
      if (partIndex < previousPartIndex) throw const FormatException('试卷考试部分顺序无效');
      previousPartIndex = partIndex;
    }
    result.add({...p, 'parts': parts, 'type_allocation': allocation,
      'score_policy': score, 'questions': questions});
  }
  return {'papers': result};
}

Future<void> validateStudyContent(DatabaseExecutor db) async {
  // Empty resource tables are valid: importing them clears only the selected level.
  for (var offset = 0; ; offset += 200) {
    final questions = await db.query('stydy_jlpt_question', limit: 200, offset: offset);
    for (final row in questions) { decodeStudyQuestion(row); }
    if (questions.length < 200) break;
  }
  final invalidLevel = await db.rawQuery("SELECT id FROM stydy_jlpt_paper WHERE level IS NULL OR level NOT IN ('N1','N2','N3','N4','N5') LIMIT 1");
  if (invalidLevel.isNotEmpty) throw const FormatException('试卷等级无效');
  final orphan = await db.rawQuery('''SELECT i.item_id FROM stydy_jlpt_paper_item i
    LEFT JOIN stydy_jlpt_paper p ON p.id=i.paper_id AND p.version=i.paper_version
    LEFT JOIN stydy_jlpt_question q ON q.id=i.question_id AND q.version=i.question_version
    WHERE p.id IS NULL OR q.id IS NULL LIMIT 1''');
  if (orphan.isNotEmpty) throw const FormatException('试卷题目关联不完整');
  final duplicate = await db.rawQuery('''SELECT paper_id FROM stydy_jlpt_paper_item
    GROUP BY paper_id,paper_version,position HAVING COUNT(*)>1
    UNION ALL SELECT paper_id FROM stydy_jlpt_paper_item
    GROUP BY paper_id,paper_version,question_id HAVING COUNT(*)>1 LIMIT 1''');
  if (duplicate.isNotEmpty) throw const FormatException('试卷题目或位置重复');
  final blueprint = await db.rawQuery('''SELECT p.id FROM stydy_jlpt_paper p
    LEFT JOIN stydy_jlpt_blueprint b ON b.id=p.blueprint_id AND b.version=p.blueprint_version
    WHERE p.blueprint_id IS NOT NULL AND b.id IS NULL LIMIT 1''');
  if (blueprint.isNotEmpty) throw const FormatException('试卷模板关联不完整');
  for (final level in studyLevels) { await readStudyBank(db, level, allVersions: true); }
}

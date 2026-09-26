import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as hash;
import 'package:sqflite/sqflite.dart';
import '../../host_contracts.dart';
import 'content.dart';

/// Formal J practice and J test share user records; demos never use this store.
class JlptStorage {
  JlptStorage(this.host, this.entryPoint);
  final StudyRoomHost host;
  final String entryPoint;
  Database get db => host.database;
  bool _legacyLoaded = false;

  Future<String> loadLevel() async {
    final rows = await db.query('yzc_study_jlpt_setting', columns: ['level'],
      where: 'user_id=? AND entry_point=?', whereArgs: [host.userId, entryPoint]);
    return rows.isEmpty ? 'N5' : rows.single['level'] as String;
  }

  Future<void> saveLevel(String level) => host.write(() async {
    if (!const ['N1', 'N2', 'N3', 'N4', 'N5'].contains(level)) {
      throw ArgumentError('考试等级无效');
    }
    await db.insert('yzc_study_jlpt_setting', {
      'user_id': host.userId, 'entry_point': entryPoint, 'level': level,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  Future<StudyJson> load(String level) => db.transaction(
    (tx) => readStudyBank(tx, level, practice: entryPoint == 'practice'), exclusive: false);

  Future<void> create(StudyJson snapshot, StudyJson progress) => host.write(() => db.transaction((tx) async {
    await tx.insert('stydy_jlpt_attempt', {
      'id': snapshot['id'], 'user_id': host.userId, 'entry_point': entryPoint,
      'paper_id': snapshot['paper_id'], 'paper_version': snapshot['paper_version'],
      'mode': snapshot['mistake_review'] == true ? 'mistake_review' : entryPoint == 'test' ? 'mock' : 'practice',
      'status': 'active', 'snapshot_json': jsonEncode(snapshot), 'progress_json': jsonEncode(progress),
      'created_at': snapshot['created'], 'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }));

  Future<void> save(String id, String payload, bool submitted) => host.write(() => db.transaction((tx) async {
    final rows = await tx.query('stydy_jlpt_attempt',
      where: 'id=? AND user_id=?', whereArgs: [id, host.userId]);
    if (rows.length != 1) throw StateError('作答记录不存在');
    final old = rows.single;
    // Submitted histories are immutable; repeated autosaves cannot apply mistakes twice.
    if (old['status'] == 'submitted') return;
    final snapshot = studyJson(old['snapshot_json']) as StudyJson;
    final progress = jsonDecode(payload) as StudyJson;
    final now = DateTime.now().toUtc().toIso8601String();
    await tx.update('stydy_jlpt_attempt', {
      'progress_json': payload, 'status': submitted ? 'submitted' : 'active',
      'updated_at': now, if (submitted) 'submitted_at': now,
      'active_elapsed_ms': (progress['elapsed'] as Map).values.fold<num>(0, (a, b) => a + (b as num)).toInt(),
    }, where: 'id=? AND user_id=?', whereArgs: [id, host.userId]);
    if (!submitted) return;
    await _recordAnswers(tx, id, snapshot, progress, now);
  }));

  Future<void> _recordAnswers(Transaction tx, String id, StudyJson snapshot,
      StudyJson progress, String now, {bool legacy = false}) async {
    final answers = progress['answers'] as Map;
    final questions = (snapshot['questions'] as List).cast<StudyJson>();
    for (var index = 0; index < questions.length; index++) {
      final q = questions[index];
      final response = answers[q['id']];
      // Unanswered is recorded, but is not invented as a wrong answer.
      final correct = response == (q['answer_json']['correct_option_ids'] as List).single;
      final explanationSeen = (progress['revealed'] as List).contains(q['id']);
      final itemId = q['item_id'] as String? ?? '${index + 1}';
      await tx.insert('stydy_jlpt_answer', {
        'attempt_id': id, 'item_id': itemId, 'paper_id': snapshot['paper_id'],
        'paper_version': snapshot['paper_version'], 'response_json': jsonEncode(response),
        'result': response == null ? 'unanswered' : correct ? 'correct' : 'incorrect',
        'bookmarked': (progress['flags'] as List).contains(q['id']) ? 1 : 0,
        'explanation_seen': explanationSeen ? 1 : 0,
        'last_answered_at': now,
      });
      await _applyMistake(tx, id, snapshot, q, response, correct,
        explanationSeen, now, legacy: legacy);
    }
  }

  Future<void> _applyMistake(Transaction tx, String id, StudyJson snapshot,
      StudyJson question, Object? response, bool correct, bool explanationSeen,
      String now, {bool legacy = false, Map<String, Object?>? preserved}) async {
    if (response == null) return;
    final mistakes = await tx.query('stydy_jlpt_mistake',
      where: 'user_id=? AND question_id=?', whereArgs: [host.userId, question['id']]);
    if (mistakes.length > 1) throw StateError('错题记录重复，请先处理本地数据');
    final previous = mistakes.isEmpty ? null : mistakes.single;
    if (legacy && previous != null) {
      final previousTime = DateTime.tryParse(previous['updated_at']?.toString() ?? '');
      final incomingTime = DateTime.tryParse(now);
      if (previousTime != null && incomingTime != null && previousTime.isAfter(incomingTime)) return;
    }
    if (!correct) {
      final values = <String, Object?>{
        'question_version': question['version'], 'last_attempt_id': id,
        'snapshot_json': jsonEncode(question), 'state': 'new',
        'wrong_count': ((previous?['wrong_count'] as int?) ?? 0) + 1,
        'correct_streak': 0, 'updated_at': now,
      };
      if (previous == null) {
        await tx.insert('stydy_jlpt_mistake', {
          'id': preserved?['id'] ?? host.newId(),
          'user_id': host.userId, 'question_id': question['id'],
          'first_attempt_id': id, 'created_at': now,
          if (preserved?['reason_tags_json'] != null)
            'reason_tags_json': preserved!['reason_tags_json'],
          if (preserved?['personal_note'] != null)
            'personal_note': preserved!['personal_note'],
          if (preserved?['next_review_at'] != null)
            'next_review_at': preserved!['next_review_at'],
          if (preserved?['schedule_json'] != null)
            'schedule_json': preserved!['schedule_json'],
          ...values,
        });
      } else {
        await tx.update('stydy_jlpt_mistake', values,
          where: 'id=? AND user_id=?', whereArgs: [previous['id'], host.userId]);
      }
    } else if (previous != null && !explanationSeen) {
      // A correct answer after viewing the explanation is assisted practice.
      // Only an independent correct answer can mark a mistake as mastered.
      await tx.update('stydy_jlpt_mistake', {
        'state': 'mastered', 'correct_streak': ((previous['correct_streak'] as int?) ?? 0) + 1,
        'last_review_at': now, 'updated_at': now,
      }, where: 'id=? AND user_id=?', whereArgs: [previous['id'], host.userId]);
    }
    if (previous != null && snapshot['mistake_review'] == true) {
      await tx.insert('stydy_jlpt_review_log', {
        'id': host.newId(), 'mistake_id': previous['id'], 'attempt_id': id,
        'question_version': question['version'], 'response_json': jsonEncode(response),
        'result': correct ? 'correct' : 'incorrect', 'reviewed_at': now,
      });
      await tx.rawUpdate(
        'UPDATE stydy_jlpt_mistake SET review_count=COALESCE(review_count,0)+1 WHERE id=?',
        [previous['id']]);
    }
  }

  Future<void> delete(String id) => host.write(() async {
    final records = await db.query('stydy_jlpt_attempt',
      where: 'id=? AND user_id=? AND entry_point=?',
      whereArgs: [id, host.userId, entryPoint]);
    if (records.length != 1) throw StateError('作答记录不存在');
    final snapshot = studyJson(records.single['snapshot_json']) as StudyJson;
    final questionIds = (snapshot['questions'] as List).cast<StudyJson>()
      .map((question) => question['id'] as String).toSet();
    await _deleteLegacySource(id);
    await db.transaction((tx) async {
      await tx.delete('stydy_jlpt_review_log',
        where: 'attempt_id=?', whereArgs: [id]);
      await tx.delete('stydy_jlpt_question_feedback',
        where: 'attempt_id=? AND user_id=?', whereArgs: [id, host.userId]);
      for (final table in ['stydy_jlpt_attempt_section', 'stydy_jlpt_answer',
        'stydy_jlpt_answer_event', 'stydy_jlpt_score_report']) {
        await tx.delete(table, where: 'attempt_id=?', whereArgs: [id]);
      }
      await tx.delete('stydy_jlpt_attempt',
        where: 'id=? AND user_id=? AND entry_point=?',
        whereArgs: [id, host.userId, entryPoint]);
      await _rebuildMistakes(tx, questionIds);
    });
  });

  Future<void> _rebuildMistakes(Transaction tx, Set<String> questionIds) async {
    if (questionIds.isEmpty) return;
    final placeholders = List.filled(questionIds.length, '?').join(',');
    final oldRows = await tx.query('stydy_jlpt_mistake',
      where: 'user_id=? AND question_id IN ($placeholders)',
      whereArgs: [host.userId, ...questionIds]);
    final preserved = <String, Map<String, Object?>>{
      for (final row in oldRows) row['question_id'] as String: row,
    };
    if (oldRows.isNotEmpty) {
      final mistakeIds = oldRows.map((row) => row['id']).toList();
      final mistakePlaceholders = List.filled(mistakeIds.length, '?').join(',');
      await tx.delete('stydy_jlpt_review_log',
        where: 'mistake_id IN ($mistakePlaceholders)', whereArgs: mistakeIds);
      await tx.delete('stydy_jlpt_mistake',
        where: 'user_id=? AND question_id IN ($placeholders)',
        whereArgs: [host.userId, ...questionIds]);
    }
    final attempts = await tx.query('stydy_jlpt_attempt',
      where: 'user_id=? AND status=?', whereArgs: [host.userId, 'submitted'],
      orderBy: 'COALESCE(submitted_at,updated_at),id');
    for (final row in attempts) {
      final attemptId = row['id'] as String;
      final snapshot = studyJson(row['snapshot_json']) as StudyJson;
      final progress = studyJson(row['progress_json']) as StudyJson;
      final answers = progress['answers'] as Map;
      final revealed = progress['revealed'] as List;
      final now = (row['submitted_at'] ?? row['updated_at']).toString();
      for (final question in (snapshot['questions'] as List).cast<StudyJson>()) {
        final questionId = question['id'] as String;
        if (!questionIds.contains(questionId)) continue;
        final response = answers[questionId];
        final correct = response == (question['answer_json']['correct_option_ids'] as List).single;
        await _applyMistake(tx, attemptId, snapshot, question, response, correct,
          revealed.contains(questionId), now, preserved: preserved[questionId]);
      }
    }
    for (final entry in preserved.entries) {
      if (entry.value['state'] == 'archived') {
        await tx.update('stydy_jlpt_mistake', {'state': 'archived'},
          where: 'id=? AND user_id=?', whereArgs: [entry.value['id'], host.userId]);
      }
    }
  }

  Future<void> _deleteLegacySource(String id) async {
    final user = hash.sha256.convert(utf8.encode(host.userId)).toString();
    final prefix = 'legacy:$user:$entryPoint:';
    if (!id.startsWith(prefix)) return;
    final file = File('${host.rootPath}/study/jlpt_$entryPoint/$user/attempts.sqlite');
    if (!await file.exists()) return;
    final legacy = await openDatabase(file.path, singleInstance: false);
    try {
      await legacy.delete('attempts', where: 'id=?', whereArgs: [id.substring(prefix.length)]);
    } finally {
      await legacy.close();
    }
  }

  Future<List<StudyJson>> mistakes() async {
    await _importLegacy();
    final rows = await db.query('stydy_jlpt_mistake',
      where: 'user_id=? AND state NOT IN (?,?)', whereArgs: [host.userId, 'mastered', 'archived'],
      orderBy: 'updated_at DESC,id');
    return [for (final row in rows) {
      ...row, 'question': studyJson(row['snapshot_json']),
    }];
  }

  Future<List<StudyJson>> history() async {
    await _importLegacy();
    final pending = await db.query('stydy_jlpt_attempt',
      where: 'user_id=? AND entry_point=? AND status<>?',
      whereArgs: [host.userId, entryPoint, 'submitted'], orderBy: 'updated_at DESC');
    final completed = await db.query('stydy_jlpt_attempt',
      where: 'user_id=? AND entry_point=? AND status=?',
      whereArgs: [host.userId, entryPoint, 'submitted'], orderBy: 'updated_at DESC', limit: 30);
    return [for (final row in [...pending, ...completed]) {
      'id': row['id'], 'title': (studyJson(row['snapshot_json']) as Map)['title'],
      'submitted': row['status'] == 'submitted' ? 1 : 0,
    }];
  }

  Future<({StudyJson snapshot, StudyJson progress})> restore(String id) async {
    final rows = await db.query('stydy_jlpt_attempt',
      where: 'id=? AND user_id=?', whereArgs: [id, host.userId]);
    if (rows.length != 1) throw StateError('作答记录不存在');
    return (snapshot: studyJson(rows.single['snapshot_json']) as StudyJson,
      progress: studyJson(rows.single['progress_json']) as StudyJson);
  }

  Future<void> _importLegacy() async {
    if (_legacyLoaded) return;
    final user = hash.sha256.convert(utf8.encode(host.userId)).toString();
    final records = <StudyJson>[];
    for (final module in ['practice', 'test']) {
      final file = File('${host.rootPath}/study/jlpt_$module/$user/attempts.sqlite');
      if (!await file.exists()) continue;
      final legacy = await openDatabase(file.path, readOnly: true, singleInstance: false);
      try {
        for (final row in await legacy.query('attempts')) {
          records.add({...row, 'entry_point': module});
        }
      } finally { await legacy.close(); }
    }
    records.sort((a, b) => a['updated'].toString().compareTo(b['updated'].toString()));
    await host.write(() => db.transaction((tx) async {
      for (final row in records) {
        final module = row['entry_point'] as String;
        final id = 'legacy:$user:$module:${row['id']}';
        if ((await tx.query('stydy_jlpt_attempt', columns: ['id'], where: 'id=?', whereArgs: [id])).isNotEmpty) continue;
        final snapshot = studyJson(row['snapshot']) as StudyJson;
        snapshot['id'] = id;
        final now = row['updated'] as String;
        await tx.insert('stydy_jlpt_attempt', {
          'id': id, 'user_id': host.userId, 'entry_point': module,
          'mode': module == 'test' ? 'mock' : 'practice',
          'status': row['submitted'] == 1 ? 'submitted' : 'active',
          'snapshot_json': jsonEncode(snapshot), 'progress_json': row['progress'],
          'created_at': snapshot['created'], 'updated_at': now,
        });
        if (row['submitted'] == 1) {
          await _recordAnswers(tx, id, snapshot, studyJson(row['progress']) as StudyJson, now, legacy: true);
        }
      }
    }));
    _legacyLoaded = true;
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart' as hash;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'ai_question.dart';
import 'snowflake.dart';
import 'system_errors.dart';
import 'study_room/persistence/feature/local_migration.dart';

typedef RowData = Map<String, Object?>;
String textOf(RowData row, String key) => row[key]?.toString() ?? '';
int intOf(RowData row, String key, [int fallback = 0]) =>
    row[key] is int ? row[key] as int : int.tryParse(textOf(row, key)) ?? fallback;
int nowMs() => DateTime.now().millisecondsSinceEpoch;
bool validFontScale(Object? value) => value is int && (value == 0 || (value >= 90 && value <= 150 && value % 10 == 0));

class AppStore {
  late final Database db;
  late final Directory root;
  late final String userId;
  late final String appVersion;
  late final SnowflakeIds _ids;
  String newId() => _ids.next();
  Future<void> _writes = Future<void>.value();

  // Installation and learning transactions share one queue. A failed write
  // must not poison subsequent writes, nor report success before commit.
  Future<T> write<T>(Future<T> Function() body) {
    final result = _writes.then((_) => body());
    _writes = result.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return result;
  }

  Future<void> _createDatabase(File file) async {
    final script = await rootBundle.loadString('assets/database/init.sql');
    final temporary = File('${file.path}.creating');
    // Only the unfinished initialization file is discarded on a retry.
    await deleteDatabase(temporary.path);
    final initial = await openDatabase(temporary.path, singleInstance: false);
    try {
      await initial.transaction((tx) async {
        final statement = StringBuffer();
        for (final line in const LineSplitter().convert(script)) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('--')) continue;
          statement.writeln(line);
          if (trimmed.endsWith(';')) {
            await tx.execute(statement.toString());
            statement.clear();
          }
        }
        if (statement.isNotEmpty) throw const FormatException('初始化 SQL 语句缺少结束分号');
      });
    } finally {
      await initial.close();
    }
    await temporary.rename(file.path);
  }

  Future<void> open() async {
    root = Directory('${(await getApplicationSupportDirectory()).path}/v3.1');
    final directory = Directory('${root.path}/database');
    await directory.create(recursive: true);
    final file = File('${directory.path}/app.sqlite');
    if (!await file.exists()) {
      await _createDatabase(file);
    }
    db = await openDatabase(file.path,
      onConfigure: (db) async {
        // busy_timeout returns a row, so use the query API on iOS.
        await db.rawQuery('PRAGMA busy_timeout = 10000');
      },
    );
    await _prepareSystemErrorSchema();
    SystemErrors.attach(db);
    await _prepareStudySchema();
    await _prepareCourseMediaSchema();
    final studyMigration = StudyLocalMigration(db, root.path);
    await studyMigration.prepareSchema();
    await db.transaction((tx) async {
      await tx.execute('''CREATE TABLE IF NOT EXISTS yzc_user_book_position (
        user_id TEXT NOT NULL,
        textbook_id TEXT NOT NULL,
        lessons_id TEXT,
        open_time INTEGER,
        PRIMARY KEY (user_id, textbook_id)
      )''');
      await tx.execute('''INSERT OR IGNORE INTO yzc_user_book_position
        (user_id, textbook_id, lessons_id, open_time)
        SELECT p.user_id, p.last_textbook_id, p.lessons_id, p.open_time
        FROM yzc_user_position p JOIN yzc_lessons l
          ON l.id=p.lessons_id AND l.textbook_id=p.last_textbook_id
        WHERE p.open_time IS NOT NULL''');
    });
    // Seed above existing numeric keys without changing any old ID or relation.
    int floorId = 0;
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
    for (final table in tables) {
      final name = textOf(table, 'name').replaceAll('"', '""');
      final columns = await db.rawQuery('PRAGMA table_info("$name")');
      if (!columns.any((column) => column['name'] == 'id')) continue;
      final maximum = await db.rawQuery('SELECT MAX(CAST(id AS INTEGER)) value FROM "$name" WHERE id<>? AND id NOT GLOB ?', ['', '*[^0-9]*']);
      floorId = max(floorId, intOf(maximum.single, 'value'));
    }
    _ids = SnowflakeIds(Directory('${root.path}/ids'), floorId: floorId);
    final device = Map<String, Object?>.from(
      await const MethodChannel('yuzhichu/device').invokeMapMethod<String, Object?>('info') ?? {},
    );
    appVersion = textOf(device, 'app_ver').trim();
    SystemErrors.appVersion = appVersion;
    userId = await db.transaction((tx) async {
      final sessions = await tx.query('yzc_local_session', limit: 1);
      final time = nowMs();
      if (sessions.isNotEmpty) {
        final id = textOf(sessions.first, 'user_id');
        if ((await tx.query('yzc_user', where: 'id = ?', whereArgs: [id])).isEmpty) {
          throw StateError('本地用户记录不完整，请勿删除数据库');
        }
        await tx.update('yzc_user', {...device, 'last_active_time': time, 'update_time': time}, where: 'id = ?', whereArgs: [id]);
        await tx.update('yzc_user_device', {...device, 'last_active_time': time, 'update_time': time}, where: 'user_id = ? AND installation_id = ?', whereArgs: [id, sessions.first['installation_id']]);
        return id;
      }
      String id;
      do { id = newId(); } while ((await tx.query('yzc_user', where: 'id = ?', whereArgs: [id])).isNotEmpty);
      final installation = newId();
      await tx.insert('yzc_user', {'id': id, 'name': '语之初学习者', ...device, 'create_time': time, 'update_time': time, 'last_active_time': time});
      await tx.insert('yzc_user_device', {'id': newId(), 'user_id': id, 'installation_id': installation, ...device, 'create_time': time, 'update_time': time, 'last_active_time': time});
      await tx.insert('yzc_user_setting', {'id': newId(), 'user_id': id, 'create_time': time, 'update_time': time});
      await tx.insert('yzc_user_position', {'id': newId(), 'user_id': id, 'create_time': time, 'update_time': time});
      await tx.insert('yzc_local_session', {'id': newId(), 'user_id': id, 'installation_id': installation, 'update_time': time});
      return id;
    });
    SystemErrors.userId = userId;
    await studyMigration.migrate();
  }

  Future<void> _prepareCourseMediaSchema() async {
    await db.transaction((tx) async {
      for (final table in const ['yzc_words', 'yzc_grammar', 'yzc_ai_question', 'yzc_user_question']) {
        final columns = await tx.rawQuery('PRAGMA table_info($table)');
        final names = columns.map((column) => column['name']).toSet();
        if (!names.contains('media_type')) {
          await tx.execute("ALTER TABLE $table ADD COLUMN media_type varchar(32) NOT NULL DEFAULT 'text'");
        }
        if (!names.contains('media_src')) await tx.execute('ALTER TABLE $table ADD COLUMN media_src text NULL');
        if (!names.contains('media_config')) await tx.execute('ALTER TABLE $table ADD COLUMN media_config text NULL');
      }
    });
  }

  Future<void> _prepareSystemErrorSchema() async {
    final script = await rootBundle.loadString('assets/database/init.sql');
    await db.transaction((tx) async {
      final statement = StringBuffer();
      for (final line in const LineSplitter().convert(script)) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('--')) continue;
        statement.writeln(line);
        if (!trimmed.endsWith(';')) continue;
        final sql = statement.toString().trim();
        statement.clear();
        if (sql.startsWith('CREATE TABLE yzc_system_error ')) {
          await tx.execute(sql.replaceFirst('CREATE TABLE', 'CREATE TABLE IF NOT EXISTS'));
        } else if (sql.startsWith('CREATE INDEX yzc_system_error_')) {
          await tx.execute(sql.replaceFirst('CREATE INDEX', 'CREATE INDEX IF NOT EXISTS'));
        }
      }
    });
  }

  /// Existing installations need the new user snapshot fields too. This only
  /// creates absent study tables/adds snapshot columns; never replaces user data.
  Future<void> _prepareStudySchema() async {
    final script = await rootBundle.loadString('assets/database/init.sql');
    await db.transaction((tx) async {
      final statement = StringBuffer();
      for (final line in const LineSplitter().convert(script)) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('--')) continue;
        statement.writeln(line);
        if (!trimmed.endsWith(';')) continue;
        final sql = statement.toString().trim();
        statement.clear();
        if (RegExp(r'^CREATE TABLE "?stydy_').hasMatch(sql)) {
          await tx.execute(sql.replaceFirst('CREATE TABLE', 'CREATE TABLE IF NOT EXISTS'));
        }
      }
      for (final entry in <String, List<String>>{
        'stydy_jlpt_attempt': ['entry_point', 'snapshot_json', 'progress_json'],
        'stydy_jlpt_mistake': ['snapshot_json'],
      }.entries) {
        final columns = await tx.rawQuery('PRAGMA table_info(${entry.key})');
        for (final name in entry.value) {
          if (!columns.any((c) => c['name'] == name)) {
            await tx.execute('ALTER TABLE ${entry.key} ADD COLUMN $name TEXT');
          }
        }
      }
      // Older shipped JLPT definitions contained CHECK/UNIQUE/foreign keys and
      // required a resource paper for every attempt. Normalize those user table
      // constraints once, preserving every column and row (including snapshots).
      final definitions = await tx.rawQuery("SELECT name,sql FROM sqlite_master WHERE type='table' AND name LIKE 'stydy_jlpt_%'");
      const contentTables = {'stydy_jlpt_question', 'stydy_jlpt_blueprint', 'stydy_jlpt_paper', 'stydy_jlpt_paper_item'};
      String quote(String value) => '"${value.replaceAll('"', '""')}"';
      for (final definition in definitions) {
        final name = textOf(definition, 'name');
        if (contentTables.contains(name)) continue;
        final columns = await tx.rawQuery('PRAGMA table_info(${quote(name)})');
        final keys = columns.where((c) => intOf(c, 'pk') > 0).toList()
          ..sort((a, b) => intOf(a, 'pk').compareTo(intOf(b, 'pk')));
        final ddl = textOf(definition, 'sql');
        if (!RegExp(r'\b(CHECK|UNIQUE|REFERENCES|FOREIGN)\b', caseSensitive: false).hasMatch(ddl) &&
            !columns.any((c) => intOf(c, 'notnull') != (intOf(c, 'pk') > 0 ? 1 : 0))) continue;
        final indexes = await tx.rawQuery('PRAGMA index_list(${quote(name)})');
        final indexSql = <String>[];
        var number = 0;
        for (final index in indexes.where((i) => i['origin'] != 'pk')) {
          final fields = await tx.rawQuery('PRAGMA index_info(${quote(textOf(index, 'name'))})');
          if (fields.any((c) => c['name'] == null)) throw StateError('J 索引需要人工处理');
          final indexName = index['origin'] == 'c' ? textOf(index, 'name') : '${name}_logical_${number++}';
          indexSql.add('CREATE INDEX ${quote(indexName)} ON ${quote(name)} (${fields.map((c) => quote(textOf(c, 'name'))).join(',')})');
        }
        final temporary = '${name}_snapshot_upgrade';
        final fields = [for (final column in columns)
          '${quote(textOf(column, 'name'))} ${textOf(column, 'type')}'
          '${intOf(column, 'pk') > 0 ? ' NOT NULL' : ''}'
          '${column['dflt_value'] == null ? '' : ' DEFAULT ${column['dflt_value']}'}'];
        fields.add('PRIMARY KEY (${keys.map((c) => quote(textOf(c, 'name'))).join(',')})');
        await tx.execute('CREATE TABLE ${quote(temporary)} (${fields.join(',')})');
        final names = columns.map((c) => quote(textOf(c, 'name'))).join(',');
        await tx.execute('INSERT INTO ${quote(temporary)} (rowid,$names) SELECT rowid,$names FROM ${quote(name)}');
        await tx.execute('DROP TABLE ${quote(name)}');
        await tx.execute('ALTER TABLE ${quote(temporary)} RENAME TO ${quote(name)}');
        for (final sql in indexSql) { await tx.execute(sql); }
      }
      await tx.execute('CREATE INDEX IF NOT EXISTS stydy_jlpt_attempt_entry ON stydy_jlpt_attempt(user_id,entry_point,status,updated_at)');
      await tx.execute('CREATE INDEX IF NOT EXISTS stydy_jlpt_mistake_lookup_1 ON stydy_jlpt_mistake(user_id,question_id)');
    });
  }

  Future<RowData> setting() async => (await db.query('yzc_user_setting', where: 'user_id = ?', whereArgs: [userId])).single;
  Future<RowData> position() async => (await db.query('yzc_user_position', where: 'user_id = ?', whereArgs: [userId])).single;
  Future<void> setSetting(String key, Object value) => write(() async {
    if (!{'onboarding', 'daily_goal', 'theme', 'playback_speed', 'show_source', 'show_ruby', 'show_definition', 'font_scale'}.contains(key)) throw ArgumentError('未知设置');
    if (key == 'font_scale' && !validFontScale(value)) throw ArgumentError('字体大小设置无效');
    await db.update('yzc_user_setting', {key: value, 'update_time': nowMs()}, where: 'user_id = ?', whereArgs: [userId]);
  });
  Future<List<RowData>> textbooks() => db.query('yzc_textbook', orderBy: 'sort IS NULL, sort, id');
  Future<List<RowData>> lessons(String book) => db.query('yzc_lessons', where: 'textbook_id = ?', whereArgs: [book], orderBy: 'num IS NULL, num, id');
  Future<List<RowData>> content(String table, String book, String lesson) {
    if (table == 'yzc_ai_question') return _questions(db, book, lesson);
    if (!{'yzc_words', 'yzc_content', 'yzc_grammar'}.contains(table)) throw ArgumentError('未知内容表');
    return db.query(table, where: 'textbook_id = ? AND lessons_id = ?', whereArgs: [book, lesson],
      orderBy: '${table == 'yzc_content' ? 'category IS NULL, category, ' : ''}sort IS NULL, sort, id');
  }
  RowData _question(RowData row) => {...row, 'content': row['question'], 'definition': row['descr'], 'type': 'ai'};
  Future<List<RowData>> _questions(DatabaseExecutor tx, String book, String lesson) async {
    final rows = await tx.query('yzc_ai_question', where: 'textbook_id=? AND lessons_id=?', whereArgs: [book, lesson], orderBy: 'sort,id');
    return rows.map(_question).toList();
  }
  Future<void> selectBook(String book) => write(() async {
    await db.update('yzc_user_position', {'textbook_id': book, 'update_time': nowMs()}, where: 'user_id = ?', whereArgs: [userId]);
  });
  Future<List<RowData>> bookPosition(String book) => db.query('yzc_user_book_position',
    where: 'user_id=? AND textbook_id=?', whereArgs: [userId, book]);
  Future<void> remember(RowData book, RowData lesson) => write(() => db.transaction((tx) async {
    final valid = await tx.query('yzc_lessons', columns: ['id'],
      where: 'id=? AND textbook_id=?', whereArgs: [lesson['id'], book['id']], limit: 1);
    if (valid.isEmpty) return;
    final time = nowMs();
    await tx.insert('yzc_user_book_position', {
      'user_id': userId, 'textbook_id': book['id'], 'lessons_id': lesson['id'], 'open_time': time,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await tx.update('yzc_user_position', {'last_textbook_id': book['id'], 'lessons_id': lesson['id'], 'lesson': lesson['lesson'], 'textbook': book['textbook'], 'title': lesson['title'], 'open_time': time, 'update_time': time}, where: 'user_id = ?', whereArgs: [userId]);
  }));
  Future<void> complete(RowData book, RowData lesson, String category) => write(() => db.transaction((tx) async {
    if (!{'word', 'content', 'grammar', 'whole'}.contains(category)) throw ArgumentError('学习类别无效');
    final time = nowMs();
    final existing = await tx.query('yzc_user_learn', columns: ['id'],
      where: 'user_id=? AND textbook_id=? AND lessons_id=? AND category=?',
      whereArgs: [userId, book['id'], lesson['id'], category], limit: 1);
    if (existing.isEmpty) {
      await tx.insert('yzc_user_learn', {'id': newId(), 'user_id': userId, 'textbook_id': book['id'], 'unit_id': lesson['unit_id'], 'lessons_id': lesson['id'], 'lesson': lesson['lesson'], 'category': category, 'textbook': book['textbook'], 'title': lesson['title'], 'complete_time': time, 'create_time': time, 'update_time': time});
    }
    await _event(tx, 'complete:${book['id']}:${lesson['id']}:$category:${_date()}', 'complete', book: textOf(book, 'id'), lesson: textOf(lesson, 'id'));
  }));
  Future<List<RowData>> progress(String book) => db.query('yzc_user_learn', where: 'user_id = ? AND textbook_id = ?', whereArgs: [userId, book]);
  Future<void> cancelCompletion(RowData book, RowData lesson, String category) => write(() async {
    if (!{'word', 'content', 'grammar'}.contains(category)) throw ArgumentError('学习类别无效');
    // Only revoke completion; historical study activity still counts as learning.
    await db.delete('yzc_user_learn',
      where: 'user_id=? AND textbook_id=? AND lessons_id=? AND category=?',
      whereArgs: [userId, book['id'], lesson['id'], category]);
  });
  String _date() => DateTime.now().toIso8601String().substring(0, 10);
  Future<void> _event(DatabaseExecutor tx, String key, String type, {String? book, String? lesson, String? practice, String? item}) async {
    final existing = await tx.query('yzc_user_study', columns: ['id'],
      where: 'user_id=? AND event_key=?', whereArgs: [userId, key], limit: 1);
    if (existing.isNotEmpty) return;
    final time = nowMs();
    await tx.insert('yzc_user_study', {'id': newId(), 'user_id': userId, 'event_key': key, 'type': type, 'textbook_id': book, 'lessons_id': lesson, 'practice_id': practice, 'item_id': item, 'study_time': time, 'study_date': _date(), 'utc_offset': DateTime.now().timeZoneOffset.inMinutes, 'create_time': time, 'update_time': time});
  }

  Future<RowData> reviewStatistics() async {
    final time = nowMs();
    return (await db.rawQuery('SELECT COUNT(*) cards, COALESCE(SUM(CASE WHEN mistake>0 THEN 1 ELSE 0 END),0) mistakes, COALESCE(SUM(CASE WHEN review_time<=? THEN 1 ELSE 0 END),0) due, MIN(CASE WHEN review_time>? THEN review_time END) next_review_time FROM yzc_user_review WHERE user_id=?', [time, time, userId])).single;
  }

  Future<RowData> statistics() async {
    final answers = (await db.rawQuery('SELECT COUNT(*) total, COALESCE(SUM(correct),0) correct FROM yzc_user_practice_item WHERE user_id=? AND answer_time IS NOT NULL', [userId])).single;
    final review = await reviewStatistics();
    final dates = await db.rawQuery('SELECT DISTINCT study_date FROM yzc_user_study WHERE user_id=? ORDER BY study_date DESC', [userId]);
    int streak = 0;
    DateTime? previous;
    final localNow = DateTime.now();
    // Compare calendar dates without daylight-saving offsets changing day gaps.
    final today = DateTime.utc(localNow.year, localNow.month, localNow.day);
    for (final row in dates) {
      final parsed = DateTime.tryParse(textOf(row, 'study_date'));
      if (parsed == null) continue;
      final date = DateTime.utc(parsed.year, parsed.month, parsed.day);
      if (date.isAfter(today)) continue;
      if (previous == null && today.difference(date).inDays > 1) break;
      if (previous != null && previous.difference(date).inDays != 1) break;
      streak++;
      previous = date;
    }
    return {...answers, ...review, 'streak': streak};
  }

  Future<String> startPractice(List<RowData> pool, {bool review = false, String? relation}) => write(() => db.transaction((tx) async {
    if (relation != null && (review || !questionRelations.contains(relation))) throw ArgumentError('练习分类无效');
    final currentPool = review || pool.isEmpty ? pool : await _questions(tx, textOf(pool.first, 'textbook_id'), textOf(pool.first, 'lessons_id'));
    final seenRows = await tx.rawQuery('SELECT q.textbook_id,q.question_id,MAX(i.answer_time) last FROM yzc_user_question q JOIN yzc_user_practice_item i ON i.question_id=q.id AND i.user_id=q.user_id WHERE q.user_id=? GROUP BY q.textbook_id,q.question_id', [userId]);
    final seen = {for (final r in seenRows) '${r['textbook_id']}:${r['question_id']}': intOf(r, 'last')};
    final unique = <String, RowData>{};
    for (final q in currentPool) {
      if (!isOpenDisplayQuestion(q)) {
        unique['${q['textbook_id']}:${q['question_id'] ?? q['id']}'] = q;
      }
    }
    final candidates = unique.values.toList()..shuffle(Random.secure());
    final order = {for (var i = 0; i < candidates.length; i++) candidates[i]: i};
    candidates.sort((a, b) {
      final x = seen['${a['textbook_id']}:${a['question_id'] ?? a['id']}'] ?? 0;
      final y = seen['${b['textbook_id']}:${b['question_id'] ?? b['id']}'] ?? 0;
      return x == y ? order[a]!.compareTo(order[b]!) : x.compareTo(y);
    });
    final List<RowData> chosen;
    if (review) {
      chosen = candidates.take(10).toList();
    } else if (relation != null) {
      chosen = candidates.where((q) => q['relation'] == relation).take(relation == 'content' ? 3 : 10).toList();
    } else {
      final quota = practiceQuota(candidates);
      chosen = [];
      for (final entry in quota.entries) {
        final selected = candidates.where((q) => q['relation'] == entry.key).take(entry.value).toList();
        if (selected.length < entry.value) throw StateError('本课需至少 ${entry.value} 道${questionRelationLabel(entry.key)}题');
        chosen.addAll(selected);
      }
      chosen.shuffle(Random.secure());
    }
    if (chosen.isEmpty) throw StateError('本课暂无可用题目');
    final session = newId();
    final time = nowMs();
    await tx.insert('yzc_user_practice', {'id': session, 'user_id': userId, 'type': review ? 'review' : 'ai', 'textbook_id': review ? null : chosen.first['textbook_id'], 'lessons_id': review ? null : chosen.first['lessons_id'], 'start_time': time, 'status': 'active', 'create_time': time, 'update_time': time});
    for (var i = 0; i < chosen.length; i++) {
      final selected = chosen[i];
      // Re-read inside the queued transaction: a package may have changed
      // while the lesson screen was open. Never pair old text with new options.
      final current = await tx.query(review ? 'yzc_user_question' : 'yzc_ai_question',
        where: review ? 'id=? AND user_id=?' : 'id=? AND textbook_id=?',
        whereArgs: [selected['id'], review ? userId : selected['textbook_id']]);
      if (current.isEmpty) throw StateError('题库已更新，请重新打开课程后开始练习');
      final q = review ? current.single : _question(current.single);
      if (isOpenDisplayQuestion(q)) throw StateError('开放练习不创建作答记录');
      final options = questionOptions(q['options'], q['answer']);
      if (options.length != 4 || options.map((o) => o['code']).toSet().length != 4 || options.any((o) => !['A', 'B', 'C', 'D'].contains(o['code']) || textOf(o, 'content').isEmpty) || !options.any((o) => o['code'] == q['answer'])) throw StateError('题目选项或答案不完整');
      final snapshot = newId();
      final books = review ? <RowData>[] : await tx.query('yzc_textbook', where: 'id=?', whereArgs: [q['textbook_id']]);
      final lessons = review ? <RowData>[] : await tx.query('yzc_lessons', where: 'id=? AND textbook_id=?', whereArgs: [q['lessons_id'], q['textbook_id']]);
      await tx.insert('yzc_user_question', {'id': snapshot, 'user_id': userId, 'textbook_id': q['textbook_id'], 'lessons_id': q['lessons_id'], 'question_id': review ? q['question_id'] : q['id'], 'ver': q['ver'], 'type': q['type'] ?? 'ai', 'relation': q['relation'], 'content': q['content'], 'definition': q['definition'], 'options': encodeQuestionOptions(options), 'answer': q['answer'], 'media_json': q['media_json'], 'media_type': textOf(q, 'media_type').isEmpty ? 'text' : q['media_type'], 'media_src': q['media_src'], 'media_config': q['media_config'], 'textbook': review ? q['textbook'] : (books.isEmpty ? null : books.single['textbook']), 'title': review ? q['title'] : (lessons.isEmpty ? null : lessons.single['title']), 'create_time': time, 'update_time': time});
      await tx.insert('yzc_user_practice_item', {'id': newId(), 'user_id': userId, 'practice_id': session, 'question_id': snapshot, 'sort': i, 'create_time': time, 'update_time': time});
    }
    return session;
  }));

  Future<List<RowData>> practiceItems(String id) => db.rawQuery('SELECT i.*,q.content,q.definition,q.relation,q.answer correct_answer,q.textbook_id,q.lessons_id,q.question_id source_id,q.media_json,q.media_type,q.media_src,q.media_config FROM yzc_user_practice_item i JOIN yzc_user_question q ON q.id=i.question_id AND q.user_id=i.user_id WHERE i.user_id=? AND i.practice_id=? ORDER BY i.sort', [userId, id]);
  Future<List<RowData>> options(String snapshot) async {
    final rows = await db.query('yzc_user_question', where: 'id=? AND user_id=?', whereArgs: [snapshot, userId]);
    if (rows.isEmpty) throw StateError('练习快照不存在');
    return questionOptions(rows.single['options'], rows.single['answer']);
  }
  Future<void> answer(RowData item, String answer, int elapsed) => write(() => db.transaction((tx) async {
    final current = (await tx.query('yzc_user_practice_item', where: 'id=? AND user_id=?', whereArgs: [item['id'], userId])).single;
    if (current['answer_time'] != null) return;
    final q = (await tx.query('yzc_user_question', where: 'id=? AND user_id=?', whereArgs: [current['question_id'], userId])).single;
    if (!questionOptions(q['options'], q['answer']).any((option) => option['code'] == answer)) throw ArgumentError('无效选项');
    final correct = q['answer'] == answer;
    final time = nowMs();
    await tx.update('yzc_user_practice_item', {'answer': answer, 'correct': correct ? 1 : 0, 'duration': max(0, elapsed), 'answer_time': time, 'update_time': time}, where: 'id=? AND user_id=? AND answer_time IS NULL', whereArgs: [current['id'], userId]);
    final cards = await tx.query('yzc_user_review', where: 'user_id=? AND textbook_id=? AND question_id=?', whereArgs: [userId, q['textbook_id'], q['question_id']]);
    final old = cards.isEmpty ? <String, Object?>{} : cards.single;
    final level = correct ? min(5, intOf(old, 'lvl') + 1) : 0;
    final days = correct ? [1, 2, 4, 7, 14, 30][level] : 0;
    final values = {'snapshot_id': q['id'], 'lvl': level, 'interval_days': days, 'mistake': intOf(old, 'mistake') + (correct ? 0 : 1), 'review_time': DateTime.now().add(Duration(days: days)).millisecondsSinceEpoch, 'answer_time': time, 'update_time': time};
    if (cards.isEmpty) {
      await tx.insert('yzc_user_review', {'id': newId(), 'user_id': userId, 'textbook_id': q['textbook_id'], 'question_id': q['question_id'], 'create_time': time, ...values});
    } else {
      await tx.update('yzc_user_review', values, where: 'id=? AND user_id=?', whereArgs: [old['id'], userId]);
    }
    if (!correct) {
      final lastSort = Sqflite.firstIntValue(await tx.rawQuery('SELECT MAX(sort) FROM yzc_user_practice_item WHERE user_id=? AND practice_id=?', [userId, current['practice_id']])) ?? -1;
      await tx.insert('yzc_user_practice_item', {'id': newId(), 'user_id': userId, 'practice_id': current['practice_id'], 'question_id': current['question_id'], 'sort': lastSort + 1, 'retry_of': current['id'], 'create_time': time, 'update_time': time});
    }
    await _event(tx, 'answer:${current['id']}', 'answer', book: textOf(q, 'textbook_id'), lesson: textOf(q, 'lessons_id'), practice: textOf(current, 'practice_id'), item: textOf(current, 'id'));
    final remaining = Sqflite.firstIntValue(await tx.rawQuery('SELECT COUNT(*) FROM yzc_user_practice_item WHERE user_id=? AND practice_id=? AND answer_time IS NULL', [userId, current['practice_id']])) ?? 0;
    if (remaining == 0) await tx.update('yzc_user_practice', {'status': 'complete', 'end_time': time, 'update_time': time}, where: 'id=? AND user_id=?', whereArgs: [current['practice_id'], userId]);
  }));
  Future<void> rateMistake(RowData item, String? rating) => write(() async {
    if (rating != null && !{'again', 'hard', 'good', 'easy'}.contains(rating)) throw ArgumentError('无效评分');
    final changed = await db.update('yzc_user_practice_item', {'self_rating': rating, 'update_time': nowMs()}, where: 'id=? AND user_id=? AND correct=0', whereArgs: [item['id'], userId]);
    if (changed != 1) throw StateError('只能评价已提交的错题');
  });
  Future<String?> previousMistakeRating(RowData item) async {
    if (item['answer_time'] == null) return null;
    final rows = await db.rawQuery('SELECT i.self_rating FROM yzc_user_practice_item i JOIN yzc_user_question q ON q.id=i.question_id AND q.user_id=i.user_id WHERE i.user_id=? AND q.textbook_id=? AND q.question_id=? AND i.id<>? AND i.correct=0 AND i.self_rating IS NOT NULL AND i.answer_time<=? ORDER BY i.answer_time DESC,i.id DESC LIMIT 1', [userId, item['textbook_id'], item['source_id'], item['id'], item['answer_time']]);
    return rows.isEmpty ? null : textOf(rows.single, 'self_rating');
  }
  Future<List<RowData>> reviewPool({bool mistakes = false}) => db.rawQuery('SELECT q.* FROM yzc_user_review r JOIN yzc_user_question q ON r.snapshot_id=q.id AND r.user_id=q.user_id WHERE r.user_id=? AND ${mistakes ? 'r.mistake>0' : 'r.review_time<=?'} ORDER BY r.review_time', [userId, if (!mistakes) nowMs()]);
  Future<List<RowData>> history() => db.rawQuery('SELECT p.*,COUNT(i.id) count,COALESCE(SUM(i.correct),0) correct,COUNT(i.answer_time) answered FROM yzc_user_practice p LEFT JOIN yzc_user_practice_item i ON i.practice_id=p.id AND i.user_id=p.user_id WHERE p.user_id=? GROUP BY p.id ORDER BY p.start_time DESC', [userId]);
  // Match the history/review-pool counts without loading their detail rows.
  Future<List<RowData>> homeOverviewCounts() => db.rawQuery('''
    SELECT
      (SELECT COUNT(*) FROM yzc_user_practice
        WHERE user_id=? AND status='complete') AS completed_practices,
      (SELECT COUNT(*) FROM yzc_user_review r
        JOIN yzc_user_question q ON r.snapshot_id=q.id AND r.user_id=q.user_id
        WHERE r.user_id=? AND r.mistake>0) AS mistakes,
      (SELECT COUNT(*) FROM (
        SELECT textbook_id,lessons_id FROM yzc_user_learn
        WHERE user_id=? AND category IN ('word','content','grammar')
        GROUP BY textbook_id,lessons_id HAVING COUNT(DISTINCT category)=3
      )) AS completed_lessons
  ''', [userId, userId, userId]);
  Future<void> resetJlpt() => write(() async {
    // Remove legacy sources first so opening either entry cannot import them again.
    final digest = hash.sha256.convert(utf8.encode(userId)).toString();
    for (final entry in ['practice', 'test']) {
      final directory = '${root.path}/study/jlpt_$entry/$digest';
      await deleteDatabase('$directory/attempts.sqlite');
      final level = File('$directory/selected_level.txt');
      if (await level.exists()) await level.delete();
    }
    await db.transaction((tx) async {
      const attempts = 'SELECT id FROM stydy_jlpt_attempt WHERE user_id=?';
      const mistakes = 'SELECT id FROM stydy_jlpt_mistake WHERE user_id=?';
      await tx.delete('stydy_jlpt_review_log',
        where: 'attempt_id IN ($attempts) OR mistake_id IN ($mistakes)',
        whereArgs: [userId, userId]);
      for (final table in ['stydy_jlpt_attempt_section', 'stydy_jlpt_answer',
        'stydy_jlpt_answer_event', 'stydy_jlpt_score_report']) {
        await tx.delete(table, where: 'attempt_id IN ($attempts)', whereArgs: [userId]);
      }
      for (final table in ['stydy_jlpt_question_feedback', 'stydy_jlpt_question_note',
        'stydy_jlpt_mistake', 'stydy_jlpt_attempt', 'stydy_jlpt_generation_job',
        'yzc_study_jlpt_setting']) {
        await tx.delete(table, where: 'user_id=?', whereArgs: [userId]);
      }
    });
  });

  Future<void> reset() => write(() => db.transaction((tx) async {
    for (final table in ['yzc_user_review', 'yzc_user_practice_item', 'yzc_user_question', 'yzc_user_practice', 'yzc_user_study', 'yzc_user_learn', 'yzc_user_book_position']) {
      await tx.delete(table, where: 'user_id=?', whereArgs: [userId]);
    }
    await tx.update('yzc_user_position', {'textbook_id': null, 'last_textbook_id': null, 'lessons_id': null, 'lesson': null, 'textbook': null, 'title': null, 'open_time': null, 'update_time': nowMs()}, where: 'user_id=?', whereArgs: [userId]);
    await tx.update('yzc_user_setting', {'daily_goal': 10, 'theme': 'system', 'onboarding': 1, 'update_time': nowMs()}, where: 'user_id=?', whereArgs: [userId]);
  }));
}

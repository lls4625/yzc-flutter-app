import '../../../lesson_presentation.dart';
import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../host_contracts.dart';
import 'models.dart';

typedef FlashRow = Map<String, Object?>;

class FlashCatalog {
  FlashCatalog(this.host);
  final StudyRoomHost host;

  Future<String> pronunciation(FlashWord word) => _read((db) async {
    if (host.isBookUnavailable(word.bookId)) throw StateError('内容暂不可用');
    final rows = await db.query(
      'yzc_words',
      columns: ['phonetic'],
      where: 'textbook_id=? AND lessons_id=? AND id=?',
      whereArgs: [word.bookId, word.lessonId, word.id],
    );
    final installs = await db.query(
      'yzc_resource_install',
      columns: ['folder'],
      where: 'textbook_id=? AND status=?',
      whereArgs: [word.bookId, 'ready'],
    );
    if (rows.length != 1 || installs.length != 1) throw StateError('单词音频不可用');
    final file = rows.single['phonetic']?.toString() ?? '';
    final folder = installs.single['folder']?.toString() ?? '';
    for (final name in [file, folder]) {
      if (name.isEmpty ||
          name.startsWith('.') ||
          name.contains('..') ||
          name.contains('/') ||
          name.contains('\\') ||
          name.contains(':') ||
          name.contains('\u0000'))
        throw StateError('单词音频缺失或资源名称无效');
    }
    final path = '${host.rootPath}/resources/$folder/mp3/$file';
    if (!await File(path).exists()) throw StateError('单词音频文件缺失');
    return path;
  });

  Future<T> _read<T>(Future<T> Function(Database db) action) async {
    final db = await openDatabase(
      host.contentDatabasePath,
      readOnly: true,
      singleInstance: false,
    );
    try {
      return await action(db);
    } finally {
      await db.close();
    }
  }

  Future<List<FlashRow>> books() => _read((db) async {
    final rows = await db.rawQuery('''SELECT b.* FROM yzc_textbook b
      WHERE EXISTS (SELECT 1 FROM yzc_resource_install i WHERE i.textbook_id=b.id AND i.status='ready')
      ORDER BY b.sort IS NULL,b.sort,b.id''');
    return rows
        .where((r) => !host.isBookUnavailable(r['id'].toString()))
        .toList();
  });

  Future<List<FlashRow>> lessons(String book) => _read(
    (db) async => sortLessons(await db.query(
      'yzc_lessons',
      where: 'textbook_id=?',
      whereArgs: [book],
      orderBy: 'num IS NULL,num,id',
    )),
  );

  Future<String> _version(DatabaseExecutor db, String book) async {
    if (host.isBookUnavailable(book)) throw StateError('内容正在更新或需要修复，请稍后重新选择');
    final rows = await db.rawQuery(
      '''SELECT b.ver,i.job_id,i.install_time FROM yzc_textbook b
      JOIN yzc_resource_install i ON i.textbook_id=b.id WHERE b.id=? AND i.status='ready' ''',
      [book],
    );
    if (rows.length != 1) throw StateError('内容已不可用，请重新选择已安装内容');
    return jsonEncode(rows.single);
  }

  Future<String> version(String book) => _read((db) => _version(db, book));

  Future<({List<FlashWord> words, String version, int skipped})> words(
    String book,
    Set<String> lessonIds,
  ) => _read((db) async {
    final result = await db.transaction((tx) async {
      final stamp = await _version(tx, book);
      final rows = await tx.rawQuery(
        '''SELECT w.*,l.lesson lesson_code,l.num lesson_num,b.textbook book_name FROM yzc_words w
        JOIN yzc_lessons l ON l.id=w.lessons_id AND l.textbook_id=w.textbook_id
        JOIN yzc_textbook b ON b.id=w.textbook_id WHERE w.textbook_id=?
        AND w.lessons_id IN (${List.filled(lessonIds.length, '?').join(',')})
        ORDER BY l.num IS NULL,l.num,l.id,w.sort IS NULL,w.sort,w.id''',
        [book, ...lessonIds],
      );
      final words = <FlashWord>[];
      var skipped = 0;
      for (final row in rows) {
        final kana = flashText(row['kana']).replaceFirst(RegExp(r'@.*$'), '');
        final candidates = [
          flashText(row['kanji']),
          flashText(row['word']),
          kana,
        ];
        final jp = candidates.firstWhere((v) => v.isNotEmpty, orElse: () => '');
        final zh = flashText(row['definition']);
        if (jp.isEmpty || zh.isEmpty) {
          skipped++;
          continue;
        }
        words.add(
          FlashWord(
            bookId: book,
            lessonId: row['lessons_id'].toString(),
            id: row['id'].toString(),
            japanese: jp,
            kana: kana,
            chinese: zh,
            pos: flashText(row['pos']),
            source: '${row['book_name']} · ${lessonLabel(row, lessonKey: 'lesson_code', numberKey: 'lesson_num')}',
          ),
        );
      }
      return (words: words, version: stamp, skipped: skipped);
    }, exclusive: false);
    if (await _version(db, book) != result.version)
      throw StateError('内容已更新，请重新载入单词');
    return result;
  });
}

/// Storage contract owned exclusively by the formal flashcard feature.
abstract class FlashStore {
  Future<void> open();
  Future<Map<String, dynamic>> settings();
  Future<void> saveSettings(Map<String, dynamic> value);
  Future<Map<String, ({bool known, int time})>> mastery(
    FlashDirection direction,
  );
  Future<FlashSession?> draft();
  Future<void> begin(FlashSession session);
  Future<void> discard();
  Future<void> mark(FlashSession before, FlashSession after, bool known);
  Future<void> close();
}

class FlashDatabaseStore implements FlashStore {
  FlashDatabaseStore(this.host);
  final StudyRoomHost host;
  Database get db => host.database;
  @override
  Future<void> open() async {}

  @override
  Future<Map<String, dynamic>> settings() => db.transaction((tx) async {
    final rows = await tx.query(
      'yzc_study_flashcard_setting',
      where: 'user_id=?',
      whereArgs: [host.userId],
    );
    if (rows.isEmpty) return <String, dynamic>{};
    final row = rows.single;
    final lessons = await tx.query('yzc_study_flashcard_lesson',
      where: 'user_id=?', whereArgs: [host.userId], orderBy: 'position');
    return <String, dynamic>{
      'book': row['book'], 'direction': row['direction'],
      'onlyWeak': row['only_weak'] == 1, 'randomOrder': row['random_order'] == 1,
      'limit': row['word_limit'], 'lessons': [for (final lesson in lessons) lesson['lessons_id']],
    };
  }, exclusive: false);

  @override
  Future<void> saveSettings(Map<String, dynamic> value) => host.write(() => db.transaction((tx) async {
    await tx.insert('yzc_study_flashcard_setting', {
      'user_id': host.userId, 'book': value['book'], 'direction': value['direction'],
      'only_weak': value['onlyWeak'] == true ? 1 : 0,
      'random_order': value['randomOrder'] == true ? 1 : 0,
      'word_limit': value['limit'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await tx.delete('yzc_study_flashcard_lesson', where: 'user_id=?', whereArgs: [host.userId]);
    final lessons = (value['lessons'] as List).cast<String>().toSet().toList();
    for (var i = 0; i < lessons.length; i++) {
      await tx.insert('yzc_study_flashcard_lesson', {
        'user_id': host.userId, 'lessons_id': lessons[i], 'position': i,
      });
    }
  }));

  @override
  Future<Map<String, ({bool known, int time})>> mastery(
    FlashDirection direction,
  ) async {
    final rows = await db.query(
      'yzc_study_flashcard_mastery',
      where: 'user_id=? AND direction=?',
      whereArgs: [host.userId, direction.name],
    );
    return {
      for (final r in rows)
        r['word'] as String: (known: r['known'] == 1, time: r['time'] as int),
    };
  }

  @override
  Future<FlashSession?> draft() async {
    final rows = await db.query(
      'yzc_study_flashcard_session',
      where: 'user_id=?',
      whereArgs: [host.userId],
    );
    return rows.isEmpty
        ? null
        : FlashSession.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(rows.single['value'] as String) as Map,
            ),
          );
  }

  @override
  Future<void> begin(FlashSession session) => host.write(() async {
    await db.insert('yzc_study_flashcard_session', {
      'user_id': host.userId,
      'value': jsonEncode(session.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  @override
  Future<void> discard() => host.write(() async {
    await db.delete('yzc_study_flashcard_session', where: 'user_id=?', whereArgs: [host.userId]);
  });

  @override
  Future<void> mark(FlashSession before, FlashSession after, bool known) =>
      host.write(() => db.transaction((tx) async {
        final rows = await tx.query(
          'yzc_study_flashcard_session',
          where: 'user_id=?',
          whereArgs: [host.userId],
        );
        if (rows.isEmpty) throw StateError('复习进度已变化，请返回设置重新载入');
        final current = FlashSession.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(rows.single['value'] as String) as Map,
          ),
        );
        if (current.id != before.id || current.index != before.index)
          throw StateError('复习进度已变化，请返回设置重新载入');
        final word = before.words[before.index].key;
        final time = DateTime.now().millisecondsSinceEpoch;
        await tx.insert('yzc_study_flashcard_answer', {
          'user_id': host.userId,
          'session': before.id,
          'position': before.index,
          'word': word,
          'known': known ? 1 : 0,
          'time': time,
        });
        await tx.insert('yzc_study_flashcard_mastery', {
          'user_id': host.userId,
          'word': word,
          'direction': before.direction.name,
          'known': known ? 1 : 0,
          'time': time,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await tx.update(
          'yzc_study_flashcard_session',
          {'value': jsonEncode(after.toJson())},
          where: 'user_id=?',
          whereArgs: [host.userId],
        );
      }));
  // The application owns this connection; leaving flashcards must not close it.
  @override
  Future<void> close() async {}
}

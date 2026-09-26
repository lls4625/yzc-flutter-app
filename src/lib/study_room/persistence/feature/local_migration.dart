import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../../../system_errors.dart';

/// Startup migration for formal features only. No demo uses these tables.
class StudyLocalMigration {
  StudyLocalMigration(this.db, this.root);
  final Database db;
  final String root;
  static const _name = 'preferences_and_flashcards_v1';

  Future<void> prepareSchema() async {
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
        if (sql.startsWith('CREATE TABLE yzc_study_')) {
          await tx.execute(sql.replaceFirst('CREATE TABLE', 'CREATE TABLE IF NOT EXISTS'));
        }
      }
    });
  }

  Future<void> migrate() async {
    final path = '$root/study_room/flashcards/flashcards.sqlite';
    final done = await db.query('yzc_study_local_migration',
      where: 'name=?', whereArgs: [_name]);
    if (done.isEmpty) {
      if (await databaseExists(path)) {
        final legacy = await openDatabase(path, readOnly: true, singleInstance: false);
        try {
          // Hold one source snapshot while committing every destination table
          // and the completion marker together. Failure leaves the source intact.
          await legacy.transaction((source) => db.transaction(
            (tx) => _import(tx, source)), exclusive: false);
        } finally {
          await legacy.close();
        }
      } else {
        await db.transaction((tx) => _import(tx, null));
      }
    }
    // Only reached after a committed migration. Retry cleanup on next startup
    // if the previous process exited between commit and removal.
    try {
      if (await databaseExists(path)) await deleteDatabase(path);
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'study_storage',
        operation: '删除已迁移闪卡旧库');
    }
  }

  Future<void> _import(Transaction tx, DatabaseExecutor? legacy) async {
    for (final user in await tx.query('yzc_user', columns: ['id'])) {
      final id = user['id'] as String;
      await _importPreferences(tx, id);
    }
    if (legacy != null) await _importFlashcards(tx, legacy);
    await tx.insert('yzc_study_local_migration', {
      'name': _name, 'completed_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<bool> _hasUser(DatabaseExecutor tx, String table, String user) async =>
      (await tx.query(table, columns: ['user_id'],
        where: 'user_id=?', whereArgs: [user], limit: 1)).isNotEmpty;

  Future<Map<String, dynamic>?> _readSettings(String module, String user) async {
    final file = File('$root/study_room/$module/settings-${Uri.encodeComponent(user)}.json');
    if (!await file.exists()) return null;
    return Map<String, dynamic>.from(jsonDecode(await file.readAsString(encoding: utf8)) as Map);
  }

  Future<void> _importPreferences(Transaction tx, String user) async {
    if (!await _hasUser(tx, 'yzc_study_listening_setting', user)) {
      final settings = await _readSettings('listening', user);
      if (settings != null) {
        final speed = settings['playback_speed'];
        if ((settings['book'] != null && settings['book'] is! String) ||
            (speed != null && (speed is! int || speed < 5 || speed > 30)) ||
            ['show_ruby', 'show_source', 'show_definition'].any(
              (key) => settings[key] != null && ![0, 1].contains(settings[key]))) {
          throw const FormatException('迁移失败：磨耳朵设置无效，原文件已保留');
        }
        await tx.insert('yzc_study_listening_setting', {
          'user_id': user, 'book': settings['book'] ?? '',
          'playback_speed': speed ?? 10,
          for (final key in ['show_ruby', 'show_source', 'show_definition']) key: settings[key] ?? 1,
        });
      }
    }
    if (!await _hasUser(tx, 'yzc_study_dictation_setting', user)) {
      final settings = await _readSettings('dictation', user);
      if (settings != null) {
        if (settings['interval'] == 0) settings['interval'] = 1;
        final repeats = settings['repeats'];
        final interval = settings['interval'];
        if ((settings['book'] != null && settings['book'] is! String) ||
            ['pause_each', 'random_order'].any((key) => settings[key] != null && settings[key] is! bool) ||
            (repeats != null && (repeats is! int || repeats < 1 || repeats > 5)) ||
            (interval != null && (interval is! int || interval < 1 || interval > 10))) {
          throw const FormatException('迁移失败：听写设置无效，原文件已保留');
        }
        await tx.insert('yzc_study_dictation_setting', {
          'user_id': user, 'book': settings['book'] ?? '',
          'pause_each': settings['pause_each'] == true ? 1 : 0,
          'random_order': settings['random_order'] == true ? 1 : 0,
          'repeats': repeats ?? 1, 'interval': interval ?? 1,
        });
      }
    }
    final digest = hash.sha256.convert(utf8.encode(user)).toString();
    for (final entry in ['practice', 'test']) {
      final rows = await tx.query('yzc_study_jlpt_setting',
        where: 'user_id=? AND entry_point=?', whereArgs: [user, entry]);
      if (rows.isNotEmpty) continue;
      final file = File('$root/study/jlpt_$entry/$digest/selected_level.txt');
      if (!await file.exists()) continue;
      final value = (await file.readAsString(encoding: utf8)).trim();
      await tx.insert('yzc_study_jlpt_setting', {
        'user_id': user, 'entry_point': entry,
        'level': ['N1', 'N2', 'N3', 'N4', 'N5'].contains(value) ? value : 'N5',
      });
    }
  }

  Future<void> _importFlashcards(Transaction tx, DatabaseExecutor legacy) async {
    for (final row in await legacy.query('settings')) {
      final user = row['user'] as String;
      if (await _hasUser(tx, 'yzc_study_flashcard_setting', user)) continue;
      final settings = Map<String, dynamic>.from(jsonDecode(row['value'] as String) as Map);
      await tx.insert('yzc_study_flashcard_setting', {
        'user_id': user, 'book': settings['book'] as String? ?? '',
        'direction': ['japanese', 'chinese'].contains(settings['direction']) ? settings['direction'] : 'japanese',
        'only_weak': settings['onlyWeak'] == true ? 1 : 0,
        'random_order': settings['randomOrder'] == true ? 1 : 0,
        'word_limit': [0, 10, 20].contains(settings['limit']) ? settings['limit'] : 10,
      });
      final lessons = ((settings['lessons'] as List?) ?? []).whereType<String>().toSet().toList();
      for (var i = 0; i < lessons.length; i++) {
        await tx.insert('yzc_study_flashcard_lesson', {
          'user_id': user, 'lessons_id': lessons[i], 'position': i,
        });
      }
    }
    // Copy all users, including records not attached to the current session.
    for (final entry in {
      'sessions': ('yzc_study_flashcard_session', ['user']),
      'mastery': ('yzc_study_flashcard_mastery', ['user', 'word', 'direction']),
      'answers': ('yzc_study_flashcard_answer', ['user', 'session', 'position']),
    }.entries) {
      for (var offset = 0; ; offset += 200) {
        final rows = await legacy.query(entry.key, orderBy: 'rowid', limit: 200, offset: offset);
        if (rows.isEmpty) break;
        for (final row in rows) {
          final keys = entry.value.$2;
          final existing = await tx.query(entry.value.$1, columns: ['user_id'],
            where: keys.map((key) => '${key == 'user' ? 'user_id' : key}=?').join(' AND '),
            whereArgs: [for (final key in keys) row[key]], limit: 1);
          if (existing.isNotEmpty) continue;
          await tx.insert(entry.value.$1, {
            for (final field in row.entries) (field.key == 'user' ? 'user_id' : field.key): field.value,
          });
        }
      }
    }
  }
}

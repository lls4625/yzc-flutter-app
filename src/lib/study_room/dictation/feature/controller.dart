import '../../../user_error.dart';
import '../../../system_errors.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show BuildContext, ScaffoldMessenger, Text;
import 'package:sqflite/sqflite.dart';

import '../../../glass_ui.dart';
import '../../host_contracts.dart';
import '../../access/access.dart';

typedef RowData = Map<String, Object?>;
String textOf(RowData row, String key) => row[key]?.toString() ?? '';
String featureError(Object? error, {String fallback = '操作失败，请重试'}) =>
    userError(error, fallback: fallback);
Future<void> perform(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e, caughtStack) {
      SystemErrors.record(e, caughtStack, module: 'dictation', operation: '页面操作', context: {'source': 'study_room/dictation/feature/controller.dart'});
    if (context.mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(GlassSnackBar(content: Text(featureError(e))));
  }
}

class DictationController extends ChangeNotifier {
  DictationController(this.host, this.access)
    : catalog = DictationCatalog(host);
  final StudyRoomHost host;
  final StudyRoomAccess access;
  final DictationCatalog catalog;
  Map<String, dynamic> _settings = {};
  bool _loaded = false, _disposed = false;
  Future<void> _writes = Future.value();
  bool get unlocked => host.isUnlocked();
  bool get purchaseSaving => host.isPurchaseSaving();
  String get selectedBook => _settings['book'] as String? ?? '';
  bool get pauseEach => _settings['pause_each'] == true;
  bool get randomOrder => _settings['random_order'] == true;
  int get repeats => _settings['repeats'] as int? ?? 1;
  int get interval => _settings['interval'] as int? ?? 1;
  Future<void> load() async {
    if (_loaded) return;
    final rows = await host.database.query('yzc_study_dictation_setting',
      where: 'user_id=?', whereArgs: [host.userId]);
    _settings = rows.isEmpty ? {} : {
      ...rows.single,
      'pause_each': rows.single['pause_each'] == 1,
      'random_order': rows.single['random_order'] == 1,
    };
    _loaded = true;
  }

  Future<void> setting(String key, Object value) {
    final valid = switch (key) {
      'book' => value is String,
      'pause_each' => value is bool,
      'random_order' => value is bool,
      'repeats' => value is int && value >= 1 && value <= 5,
      'interval' => value is int && value >= 1 && value <= 10,
      _ => false,
    };
    if (!valid) {
      return Future.error(ArgumentError('未知功能设置'));
    }
    final result = _writes.then((_) async {
      final next = {..._settings, key: value};
      await host.write(() => host.database.transaction((tx) async {
        await tx.insert('yzc_study_dictation_setting', {'user_id': host.userId},
          conflictAlgorithm: ConflictAlgorithm.ignore);
        await tx.update('yzc_study_dictation_setting', {
          key: value is bool ? (value ? 1 : 0) : value,
        }, where: 'user_id=?', whereArgs: [host.userId]);
      }));
      _settings = next;
      if (!_disposed) notifyListeners();
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class DictationCatalog {
  DictationCatalog(this.host);
  final StudyRoomHost host;
  final _audioFolders = <String, String>{};
  final _versions = <String, String>{};
  Future<T> _read<T>(Future<T> Function(Database) action) async {
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

  Future<List<RowData>> textbooks() => _read((db) async {
    final rows = await db.rawQuery(
      '''SELECT b.* FROM yzc_textbook b WHERE EXISTS
      (SELECT 1 FROM yzc_resource_install i WHERE i.textbook_id=b.id AND i.status='ready')
      ORDER BY b.sort IS NULL,b.sort,b.id''',
    );
    return rows.where((r) => !host.isBookUnavailable(textOf(r, 'id'))).toList();
  });
  Future<List<RowData>> lessons(String book) => _read(
    (db) => db.query(
      'yzc_lessons',
      where: 'textbook_id=?',
      whereArgs: [book],
      orderBy: 'num IS NULL,num,id',
    ),
  );
  Future<String> version(String book) => _read((db) async {
    if (host.isBookUnavailable(book)) throw StateError('教材正在同步或需要修复');
    final rows = await db.query(
      'yzc_resource_install',
      columns: ['job_id', 'install_time'],
      where: 'textbook_id=? AND status=?',
      whereArgs: [book, 'ready'],
    );
    if (rows.length != 1) throw StateError('教材已不可用，请重新选择');
    final stamp = jsonEncode(rows.single);
    if (_versions[book] != stamp) _audioFolders.remove(book);
    _versions[book] = stamp;
    return stamp;
  });
  Future<List<RowData>> content(
    String table,
    String book,
    String lesson,
  ) => _read((db) {
    if (!{'yzc_words', 'yzc_content'}.contains(table))
      throw ArgumentError('未知内容类型');
    if (host.isBookUnavailable(book)) throw StateError('教材正在同步或需要修复');
    return db.query(
      table,
      where: 'textbook_id=? AND lessons_id=?',
      whereArgs: [book, lesson],
      orderBy:
          '${table == 'yzc_content' ? 'category IS NULL,category,' : ''}sort IS NULL,sort,id',
    );
  });
  Future<String> audioPath(String book, String filename) async {
    void safeName(String name) {
      if (name.isEmpty ||
          name.startsWith('.') ||
          name.contains('..') ||
          name.contains('/') ||
          name.contains('\\') ||
          name.contains(':') ||
          name.contains('\u0000'))
        throw StateError('音频资源名称无效');
    }

    safeName(filename);
    if (host.isBookUnavailable(book)) throw StateError('教材正在同步或需要修复');
    // The preparation version is checked before and after building a queue.
    // Resolve its directory once, rather than opening SQLite for every clip.
    final folder =
        _audioFolders[book] ??
        await _read<String>((db) async {
          final rows = await db.query(
            'yzc_resource_install',
            where: 'textbook_id=? AND status=?',
            whereArgs: [book, 'ready'],
          );
          if (rows.length != 1) throw StateError('请先下载教材');
          return textOf(rows.single, 'folder');
        });
    safeName(folder);
    _audioFolders[book] = folder;
    final path = '${host.rootPath}/resources/$folder/mp3/$filename';
    if (!await File(path).exists()) throw StateError('音频文件缺失，请重新下载教材');
    return path;
  }
}

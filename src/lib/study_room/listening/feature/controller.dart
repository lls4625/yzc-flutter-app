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
      SystemErrors.record(e, caughtStack, module: 'listening', operation: '页面操作', context: {'source': 'study_room/listening/feature/controller.dart'});
    if (context.mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(GlassSnackBar(content: Text(featureError(e))));
  }
}

class ListeningController extends ChangeNotifier {
  ListeningController(this.host, this.access)
    : catalog = ListeningCatalog(host);
  final StudyRoomHost host;
  final StudyRoomAccess access;
  final ListeningCatalog catalog;
  Map<String, dynamic> _settings = {};
  bool _loaded = false, _disposed = false;
  Future<void> _writes = Future.value();
  bool get unlocked => host.isUnlocked();
  bool get purchaseSaving => host.isPurchaseSaving();
  String get selectedBook => _settings['book'] as String? ?? '';
  double get speed => (_settings['playback_speed'] as num? ?? 10) / 10;
  bool get ruby => _settings['show_ruby'] != 0;
  bool get source => _settings['show_source'] != 0;
  bool get translation => _settings['show_definition'] != 0;
  Future<void> load() async {
    if (_loaded) return;
    final rows = await host.database.query('yzc_study_listening_setting',
      where: 'user_id=?', whereArgs: [host.userId]);
    _settings = rows.isEmpty ? {} : Map<String, dynamic>.from(rows.single);
    _loaded = true;
  }

  Future<void> setting(String key, Object value) {
    if (!{
      'book',
      'playback_speed',
      'show_ruby',
      'show_source',
      'show_definition',
    }.contains(key)) {
      return Future.error(ArgumentError('未知功能设置'));
    }
    if ((key == 'book' && value is! String) ||
        (key == 'playback_speed' &&
            (value is! int || value < 5 || value > 30)) ||
        (key.startsWith('show_') && ![0, 1].contains(value))) {
      return Future.error(ArgumentError('设置值无效'));
    }
    final result = _writes.then((_) async {
      final next = {..._settings, key: value};
      await host.write(() => host.database.transaction((tx) async {
        await tx.insert('yzc_study_listening_setting', {'user_id': host.userId},
          conflictAlgorithm: ConflictAlgorithm.ignore);
        await tx.update('yzc_study_listening_setting', {key: value},
          where: 'user_id=?', whereArgs: [host.userId]);
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

class ListeningCatalog {
  ListeningCatalog(this.host);
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

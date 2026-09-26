import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

typedef DictationDemoRow = Map<String, Object?>;

/// Bundled samples only. No formal textbook database or learning storage.
class DictationDemoCatalog {
  static const _root = 'assets/demos';
  Map<String, Object?>? _data;
  Future<void>? _loading;
  final _paths = <String, String>{};

  Future<void> load() async {
    if (_data != null) return;
    final pending = _loading ??= _load();
    try {
      await pending;
    } finally {
      if (identical(_loading, pending)) _loading = null;
    }
  }

  Future<void> _load() async {
    final data = Map<String, Object?>.from(
      jsonDecode(await rootBundle.loadString('$_root/demo.json')) as Map,
    );
    final book = Map<String, Object?>.from(data['book'] as Map);
    final lesson = Map<String, Object?>.from(data['lesson'] as Map);
    if (book['id'] == null || lesson['id'] == null) {
      throw StateError('听写演示教材信息不完整');
    }
    final samples = [
      ...(data['words'] as List),
      ...(data['content'] as List),
    ];
    if (samples.isEmpty) throw StateError('听写演示样例为空');
    final directory = await (await getTemporaryDirectory())
        .createTemp('dictation-demo-');
    final paths = <String, String>{};
    for (final sample in samples) {
      final name = (sample as Map)['phonetic']?.toString() ?? '';
      if (!RegExp(r'^[A-Za-z0-9_-]+\.mp3$').hasMatch(name)) {
        throw StateError('听写演示音频名称无效');
      }
      if (paths.containsKey(name)) continue;
      final bytes = await rootBundle.load('$_root/$name');
      final file = File('${directory.path}/$name');
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      paths[name] = file.path;
    }
    _paths.addAll(paths);
    _data = data;
  }

  Future<List<DictationDemoRow>> textbooks() async {
    await load();
    return [Map<String, Object?>.from(_data!['book'] as Map)];
  }

  Future<void> _requireBook(String book) async {
    await load();
    if ((_data!['book'] as Map)['id'].toString() != book) {
      throw StateError('仅可使用内置听写演示教材');
    }
  }

  Future<List<DictationDemoRow>> lessons(String book) async {
    await _requireBook(book);
    return [Map<String, Object?>.from(_data!['lesson'] as Map)];
  }

  Future<String> version(String book) async {
    await _requireBook(book);
    return 'dictation-demo:${_data!['version']}';
  }

  Future<List<DictationDemoRow>> content(
    String table, String book, String lesson,
  ) async {
    await _requireBook(book);
    if ((_data!['lesson'] as Map)['id'].toString() != lesson) {
      throw StateError('仅可使用内置听写演示课程');
    }
    final key = switch (table) {
      'yzc_words' => 'words',
      'yzc_content' => 'content',
      _ => throw ArgumentError('未知演示内容类型'),
    };
    final rows = (_data![key] as List)
        .map((row) => Map<String, Object?>.from(row as Map)).toList();
    rows.sort((a, b) {
      if (key == 'content') {
        final category = (a['category']?.toString() ?? '')
            .compareTo(b['category']?.toString() ?? '');
        if (category != 0) return category;
      }
      final order = ((a['sort'] as num?) ?? 0)
          .compareTo((b['sort'] as num?) ?? 0);
      return order != 0 ? order : a['id'].toString().compareTo(b['id'].toString());
    });
    return rows;
  }

  Future<String> audioPath(String book, String name) async {
    await _requireBook(book);
    return _paths[name] ?? (throw StateError('听写演示音频不可用'));
  }
}

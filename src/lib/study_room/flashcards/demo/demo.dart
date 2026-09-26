import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Flashcard-owned bundled lesson and pronunciation; no installed book access.
class FlashDemoData {
  FlashDemoData(this.book, this.lesson, this.rows);
  final Map<String, Object?> book, lesson;
  final List<Map<String, Object?>> rows;
  final _audioPaths = <String, String>{};
  static const _root = 'assets/demos';
  static const _audioFiles = {'w_l01_01.mp3', 'w_l01_02.mp3'};

  static Future<FlashDemoData> load() async {
    final data =
        jsonDecode(await rootBundle.loadString('$_root/demo.json')) as Map;
    return FlashDemoData(
      Map<String, Object?>.from(data['book'] as Map),
      Map<String, Object?>.from(data['lesson'] as Map),
      (data['words'] as List)
          .map((row) => Map<String, Object?>.from(row as Map))
          .toList(),
    );
  }

  List<FlashDemoWord> words(Set<String> selectedLessons) {
    if (!selectedLessons.contains(lesson['id'].toString())) return [];
    final ordered = List<Map<String, Object?>>.of(rows)
      ..sort((a, b) => (a['sort'] as num).compareTo(b['sort'] as num));
    return [
      for (final row in ordered)
        FlashDemoWord(
          bookId: book['id'].toString(),
          lessonId: lesson['id'].toString(),
          id: row['id'].toString(),
          japanese: flashDemoText(row['kanji']),
          kana: flashDemoText(row['kana']).replaceFirst(RegExp(r'@.*$'), ''),
          chinese: flashDemoText(row['definition']),
          pos: flashDemoText(row['pos']),
          source:
              '${book['textbook']} ${book['volume']} · 第${lesson['num']}课 · 演示',
        ),
    ];
  }

  Future<String> pronunciation(FlashDemoWord word) async {
    if (word.bookId != book['id'].toString() ||
        word.lessonId != lesson['id'].toString()) {
      throw StateError('演示单词不可用');
    }
    final row = rows.firstWhere((row) => row['id'].toString() == word.id);
    final name = row['phonetic']?.toString() ?? '';
    if (!_audioFiles.contains(name)) throw StateError('演示录音不可用');
    final cached = _audioPaths[name];
    if (cached != null && await File(cached).exists()) return cached;
    final bytes = await rootBundle.load('$_root/$name');
    final directory = await Directory((await getTemporaryDirectory()).path)
        .createTemp('flashcards-demo-');
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
    _audioPaths[name] = file.path;
    return file.path;
  }
}

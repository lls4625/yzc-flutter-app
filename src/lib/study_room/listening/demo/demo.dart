import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Only the bundled sample can enter demo playback; no installed book is read.
class ListeningDemoData {
  ListeningDemoData(
    this.book,
    this.lesson,
    this.words,
    this.content,
    this.audioPaths,
  );
  final ListeningDemoRow book, lesson;
  final List<ListeningDemoRow> words, content;
  final Map<String, String> audioPaths;
  static const _assetRoot = 'assets/demos';
  static const _audioFiles = [
    'w_l01_01.mp3',
    'w_l01_02.mp3',
    'l_l01_01.mp3',
    'l_l01_02.mp3',
  ];

  static Future<ListeningDemoData> load() async {
    final json = Map<String, Object?>.from(
      jsonDecode(await rootBundle.loadString('$_assetRoot/demo.json')) as Map,
    );
    List<ListeningDemoRow> rows(String key) => (json[key] as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList();
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}/listening-demo-v1',
    );
    await directory.create(recursive: true);
    final paths = <String, String>{};
    for (final name in _audioFiles) {
      final bytes = await rootBundle.load('$_assetRoot/$name');
      final file = File('${directory.path}/$name');
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      paths[name] = file.path;
    }
    return ListeningDemoData(
      Map<String, Object?>.from(json['book'] as Map),
      Map<String, Object?>.from(json['lesson'] as Map),
      rows('words'),
      rows('content'),
      paths,
    );
  }

  List<ListeningDemoRow> rowsFor(ListeningDemoKind kind) =>
      kind == ListeningDemoKind.words ? words : content;

  String audioPath(String name) =>
      audioPaths[name] ?? (throw StateError('演示音频不可用'));
}


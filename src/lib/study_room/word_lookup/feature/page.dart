import 'dart:async';

import 'package:flutter/material.dart';

import '../../../glass_ui.dart';
import '../../../ios_lesson_playback.dart';
import '../../../playback_scaffold.dart';
import '../../../system_errors.dart';
import '../../../ui.dart' show plainJapanese;
import '../../host_contracts.dart';
import 'repository.dart';

class WordLookupPage extends StatefulWidget {
  const WordLookupPage(this.host, {super.key});
  final StudyRoomHost host;

  @override
  State<WordLookupPage> createState() => _WordLookupPageState();
}

class _WordLookupPageState extends State<WordLookupPage> {
  late final WordLookupRepository _repository = WordLookupRepository(widget.host);
  final _playback = IosLessonPlayback.instance;
  final _controller = TextEditingController();
  Timer? _debounce;
  List<WordLookupRow> _rows = const [];
  int _request = 0;
  bool _loading = false;
  bool _startingAudio = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _playback.addListener(_playbackChanged);
    unawaited(_refreshPlayback());
  }

  Future<void> _refreshPlayback() async {
    try {
      await _playback.refresh();
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'word_lookup', operation: '刷新单词音频状态');
    }
  }

  void _playbackChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _playback.removeListener(_playbackChanged);
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _request++;
      setState(() { _rows = const []; _loading = false; _error = null; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () => _search(value));
  }

  Future<void> _search(String value) async {
    final request = ++_request;
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await _repository.search(value);
      if (!mounted || request != _request) return;
      setState(() { _rows = rows; _loading = false; });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() { _rows = const []; _loading = false; _error = '查询失败，请重试。'; });
    }
  }

  String _text(WordLookupRow row, String key) => row[key]?.toString() ?? '';
  String _reading(WordLookupRow row) => _text(row, 'kana').replaceFirst(RegExp(r'@.*$'), '');
  String _source(WordLookupRow row) {
    final book = [_text(row, 'book_name'), _text(row, 'book_volume')]
      .where((value) => value.isNotEmpty).join('·');
    final lesson = _text(row, 'lesson_num');
    return [book, if (lesson.isNotEmpty) '第 $lesson 课']
      .where((value) => value.isNotEmpty).join(' · ');
  }

  String _audioIdentity(WordLookupRow row) => '${_text(row, 'textbook_id')}:word_lookup';
  String _audioId(WordLookupRow row) => 'word_lookup:${_text(row, 'id')}';
  bool _active(WordLookupRow row) => _playback.active &&
    _playback.lesson == _audioIdentity(row) && _playback.playingId == _audioId(row);

  Future<void> _play(WordLookupRow row) async {
    if (_startingAudio) return;
    final book = _text(row, 'textbook_id');
    final filename = _text(row, 'phonetic');
    if (book.isEmpty || filename.isEmpty) return;
    setState(() => _startingAudio = true);
    try {
      final id = _audioId(row);
      if (_active(row)) {
        await (_playback.paused ? _playback.resume() : _playback.stop());
        return;
      }
      final stopRevision = _playback.stopRevision;
      final path = await widget.host.audioPath(book, filename);
      if (!mounted || _playback.stopRevision != stopRevision ||
          _playback.stopping || widget.host.isBookUnavailable(book)) return;
      await _playback.start({
        'lesson': _audioIdentity(row),
        'title': plainJapanese(_text(row, 'word')),
        'albumTitle': '查单词',
        'words': true,
        'batch': false,
        'speed': widget.host.playbackSpeed(),
        'repeat': 1,
        'intervalSteps': 0,
        'startIndex': 0,
        'clips': [{'id': id, 'path': path}],
      });
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'word_lookup', operation: '播放单词音频',
        context: {'textbook_id': book, 'word_id': _text(row, 'id')});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        GlassSnackBar(content: const Text('音频播放失败，请重试。')));
    } finally {
      if (mounted) setState(() => _startingAudio = false);
    }
  }

  Widget _result(WordLookupRow row) {
    final word = _text(row, 'word').isNotEmpty ? plainJapanese(_text(row, 'word'))
      : _text(row, 'kanji').isNotEmpty ? _text(row, 'kanji') : _reading(row);
    final active = _active(row);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StudyCard(
        shape: active ? RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.primary, width: 2),
        ) : null,
        clipBehavior: Clip.antiAlias,
        child: StudyInkWell(
          onTap: _startingAudio || widget.host.isBookUnavailable(_text(row, 'textbook_id'))
            ? null : () => unawaited(_play(row)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(word, style: const TextStyle(fontFamily: 'Hiragino Sans',
                locale: Locale('ja', 'JP'), fontSize: 21, fontWeight: FontWeight.w600)),
              if (_reading(row).isNotEmpty && _reading(row) != word) ...[
                const SizedBox(height: 3),
                Text(_reading(row), style: const TextStyle(fontFamily: 'Hiragino Sans',
                  locale: Locale('ja', 'JP'), fontSize: 14, color: Color(0xFF32AA43))),
              ],
            ])),
            if (_text(row, 'jlpt').isNotEmpty || _text(row, 'pos').isNotEmpty)
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (_text(row, 'jlpt').isNotEmpty) Text(_text(row, 'jlpt').toUpperCase(),
                  style: const TextStyle(color: Color(0xFF32AA43), fontWeight: FontWeight.w600)),
                if (_text(row, 'pos').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('[${_text(row, 'pos')}]', style: const TextStyle(color: Color(0xFF32AA43))),
                ],
              ]),
          ]),
          if (_text(row, 'definition').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_text(row, 'definition'), style: const TextStyle(
              fontFamily: 'PingFang SC', locale: Locale('zh', 'CN'), fontSize: 16, height: 1.5)),
          ],
          if (_source(row).isNotEmpty) ...[
            const SizedBox(height: 12), const StudyDivider(height: 1), const SizedBox(height: 9),
            Text(_source(row), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
          ],
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PlaybackScaffold(
    appBar: StudyAppBar(title: const Text('查单词')),
    body: SafeArea(child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _changed,
          decoration: InputDecoration(
            hintText: '输入假名、汉字或中文释义',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _controller.text.isEmpty ? null : IconButton(
              tooltip: '清空', icon: const Icon(Icons.close_rounded),
              onPressed: () { _controller.clear(); _changed(''); }),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
      ),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      Expanded(child: _controller.text.trim().isEmpty
        ? const Center(child: Padding(padding: EdgeInsets.all(28),
            child: Text('查询已安装内容中的单词\n支持假名、汉字和中文释义', textAlign: TextAlign.center)))
        : _error != null ? Center(child: Text(_error!))
        : !_loading && _rows.isEmpty ? const Center(child: Text('没有找到匹配的单词'))
        : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
            Padding(padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
              child: Text('找到 ${_rows.length} 条结果', style: Theme.of(context).textTheme.bodySmall)),
            for (final row in _rows) _result(row),
          ])),
    ])),
  );
}

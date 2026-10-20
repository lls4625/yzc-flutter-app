import '../../../content_language.dart';
import '../../../content_typography.dart';
import '../../../l10n/l10n.dart';
import '../../demo_localization/ui.dart';
import '../../../lesson_presentation.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../glass_ui.dart';
import '../../../ios_lesson_playback.dart';
import '../../../playback_scaffold.dart';
import '../../../system_errors.dart';
import '../../host_contracts.dart';
import 'repository.dart';

class WordLookupPage extends StatefulWidget {
  const WordLookupPage(this.host, {super.key});
  final StudyRoomHost host;

  @override
  State<WordLookupPage> createState() => _WordLookupPageState();
}

class _WordLookupPageState extends State<WordLookupPage> {
  late final WordLookupRepository _repository = WordLookupRepository(
    widget.host,
  );
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
      SystemErrors.record(
        error,
        stack,
        module: 'word_lookup',
        operation: '刷新单词音频状态',
      );
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
      setState(() {
        _rows = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () => _search(value));
  }

  Future<void> _search(String value) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _repository.search(value);
      if (!mounted || request != _request) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _rows = const [];
        _loading = false;
        _error = '查询失败，请重试。';
      });
    }
  }

  ContentLanguage _language(Map<String, Object?> row) =>
      ContentLanguage.fromTextbook({...row, 'id': row['textbook_id']});
  String _text(WordLookupRow row, String key) => row[key]?.toString() ?? '';
  String _reading(WordLookupRow row) =>
      _text(row, 'kana').replaceFirst(RegExp(r'@.*$'), '');
  String _source(WordLookupRow row) {
    final book = [
      _text(row, 'book_name'),
      _text(row, 'book_volume'),
    ].where((value) => value.isNotEmpty).join('·');
    final lesson = _text(row, 'lesson_num');
    return [
      book,
      if (lesson.isNotEmpty || _text(row, 'lesson_code').isNotEmpty)
        lessonLabel(
          row,
          locale: Localizations.localeOf(context),
          lessonKey: 'lesson_code',
          numberKey: 'lesson_num',
        ),
    ].where((value) => value.isNotEmpty).join(' · ');
  }

  String _audioIdentity(WordLookupRow row) =>
      '${_text(row, 'textbook_id')}:word_lookup';
  String _audioId(WordLookupRow row) => 'word_lookup:${_text(row, 'id')}';
  bool _active(WordLookupRow row) =>
      _playback.active &&
      _playback.lesson == _audioIdentity(row) &&
      _playback.playingId == _audioId(row);

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
      if (!mounted ||
          _playback.stopRevision != stopRevision ||
          _playback.stopping ||
          widget.host.isBookUnavailable(book))
        return;
      await _playback.start({
        'lesson': _audioIdentity(row),
        'title': plainContentText(
          _text(row, 'word'),
          _language(row).sourceLanguage,
        ),
        'albumTitle': studyUi(context, '查单词'),
        'words': true,
        'batch': false,
        'speed': widget.host.playbackSpeed(),
        'repeat': 1,
        'intervalSteps': 0,
        'startIndex': 0,
        'clips': [
          {'id': id, 'path': path},
        ],
      });
    } catch (error, stack) {
      SystemErrors.record(
        error,
        stack,
        module: 'word_lookup',
        operation: '播放单词音频',
        context: {'textbook_id': book, 'word_id': _text(row, 'id')},
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          GlassSnackBar(
            content: Text(
              context.tr(
                '音频播放失败，请重试。',
                '音訊播放失敗，請重試。',
                'Audio playback failed. Try again.',
                '音声を再生できませんでした。再試行してください。',
              ),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _startingAudio = false);
    }
  }

  Widget _result(WordLookupRow row) {
    if (ContentLanguage.tryFromTextbook({...row, 'id': row['textbook_id']}) ==
        null)
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          context.tr(
            '内容包语言配置无效，请下载修正版。',
            '內容包語言設定無效，請下載修正版。',
            'Invalid package language settings. Download a corrected package.',
            'パッケージの言語設定が無効です。修正版をダウンロードしてください。',
          ),
        ),
      );
    final word = _text(row, 'word').isNotEmpty
        ? plainContentText(_text(row, 'word'), _language(row).sourceLanguage)
        : _text(row, 'kanji').isNotEmpty
        ? _text(row, 'kanji')
        : _reading(row);
    final active = _active(row);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StudyCard(
        shape: active
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: scheme.primary, width: 2),
              )
            : null,
        clipBehavior: Clip.antiAlias,
        child: StudyInkWell(
          onTap:
              _startingAudio ||
                  widget.host.isBookUnavailable(_text(row, 'textbook_id'))
              ? null
              : () => unawaited(_play(row)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            word,
                            style:
                                contentTextStyle(_language(row).sourceLanguage)
                                    .copyWith(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                          if (_language(row).sourceLanguage == 'ja' &&
                              _reading(row).isNotEmpty &&
                              _reading(row) != word) ...[
                            const SizedBox(height: 3),
                            Text(
                              _reading(row),
                              style: const TextStyle(
                                fontFamily: 'Hiragino Sans',
                                locale: Locale('ja', 'JP'),
                                fontSize: 14,
                                color: Color(0xFF32AA43),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_text(row, 'jlpt').isNotEmpty ||
                        _text(row, 'pos').isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (_text(row, 'jlpt').isNotEmpty)
                            Text(
                              _text(row, 'jlpt').toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFF32AA43),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (_text(row, 'pos').isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              '[${_text(row, 'pos')}]',
                              style: const TextStyle(color: Color(0xFF32AA43)),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
                if (_text(row, 'definition').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _text(row, 'definition'),
                    style: contentTextStyle(_language(row).explanationLanguage)
                        .copyWith(fontSize: 16, height: 1.5),
                  ),
                ],
                if (_source(row).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const StudyDivider(height: 1),
                  const SizedBox(height: 9),
                  Text(
                    _source(row),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PlaybackScaffold(
    appBar: StudyAppBar(
      title: Text(context.tr('查单词', '查單字', 'Word search', '単語検索')),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _changed,
              decoration: InputDecoration(
                hintText: context.tr(
                  '输入原文或释义',
                  '輸入原文或釋義',
                  'Enter a word or meaning',
                  '単語または意味を入力',
                ),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.tr('清空', '清除', 'Clear', 'クリア'),
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _controller.clear();
                          _changed('');
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _controller.text.trim().isEmpty
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                        context.tr(
                          '查询已安装内容中的单词\n支持原文和释义',
                          '搜尋已安裝內容的單字\n支援原文和釋義',
                          'Search installed content\nEnter original text or a meaning',
                          'インストール済みの単語を検索\n原文または意味で検索できます',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _error != null
                ? Center(child: Text(studyUi(context, _error!)))
                : !_loading && _rows.isEmpty
                ? Center(
                    child: Text(
                      context.tr(
                        '没有找到匹配的单词',
                        '找不到相符的單字',
                        'No matching words',
                        '一致する単語はありません',
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
                        child: Text(
                          studyUi(context, '找到 ${_rows.length} 条结果'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      for (final row in _rows) _result(row),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
}

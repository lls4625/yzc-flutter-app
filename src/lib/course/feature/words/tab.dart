import 'dart:async';
import 'package:flutter/material.dart';
import '../../../content_typography.dart';
import '../../../data.dart';
import '../../../ios_lesson_playback.dart';
import '../../../system_errors.dart';
import '../../../ui.dart';
import '../../../user_error.dart';
import '../host.dart';
import 'image_interaction_config.dart';
import 'media_widgets.dart';
import '../video_controller.dart';

/// Independent implementation of the course words tab.
class CourseWordsTab extends StatefulWidget {
  const CourseWordsTab({required this.host, required this.book, required this.lesson, super.key});
  final CourseTabHost host;
  final RowData book, lesson;

  @override
  State<CourseWordsTab> createState() => _CourseWordsTabState();
}

class _CourseWordsTabState extends State<CourseWordsTab> with WidgetsBindingObserver {
  final _playback = IosLessonPlayback.instance;
  final _video = CourseVideoController();
  final _anchors = <String, GlobalKey>{};
  List<RowData> _rows = [];
  Set<String> _completed = {};
  bool _loading = true, _busy = false, _batchMode = false, _completing = false;
  int _repeat = 1, _interval = 0;
  String? _error, _batchStartId;
  bool _resourceUpdating = false;

  String get _bookId => textOf(widget.book, 'id');
  String get _lessonId => textOf(widget.lesson, 'id');
  String get _identity => '$_bookId:$_lessonId:words';
  bool get _owns => _playback.lesson == _identity;
  bool get _blocked => widget.host.resources.unavailable.contains(_bookId) ||
    widget.host.resources.activeBook == _bookId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.host.addListener(_hostChanged);
    widget.host.resources.addListener(_resourceChanged);
    _playback.addListener(_playChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.host.removeListener(_hostChanged);
    widget.host.resources.removeListener(_resourceChanged);
    _playback.removeListener(_playChanged);
    if (_owns) unawaited(_playback.stop());
    _video.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_perform(_playback.refresh));
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_words', operation: '单词页操作',
        context: {'textbook_id': _bookId, 'lesson_id': _lessonId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          GlassSnackBar(content: Text(userError(error))),
        );
      }
    }
  }

  void _hostChanged() { if (mounted) setState(() {}); }
  void _playChanged() { if (mounted) setState(() {}); }
  void _resourceChanged() {
    if (widget.host.resources.activeBook == _bookId) _resourceUpdating = true;
    if (_resourceUpdating && widget.host.resources.activeBook == null) {
      _resourceUpdating = false;
      unawaited(_load());
    }
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final rows = await widget.host.store.content('yzc_words', _bookId, _lessonId);
      final progress = await widget.host.store.progress(_bookId);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _completed = progress.where((row) => row['lessons_id'] == _lessonId)
          .map((row) => textOf(row, 'category')).toSet();
        _loading = false;
        _error = null;
      });
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_words', operation: '读取单词页签',
        context: {'textbook_id': _bookId, 'lesson_id': _lessonId});
      if (mounted) setState(() { _loading = false; _error = userError(error, fallback: '单词内容读取失败'); });
    }
  }

  String _itemId(RowData row) => 'word:${row['id']}';

  Future<void> _playRows(List<RowData> rows, bool all) async {
    if (_busy || _blocked) return;
    setState(() => _busy = true);
    try {
      await _video.stop();
      final clips = <RowData>[];
      for (final row in rows) {
        final type = textOf(row, 'media_type');
        String source;
        if (type == 'audio') {
          source = textOf(row, 'media_src');
          if (source.isEmpty) continue;
          clips.add({'id': _itemId(row), 'path': await widget.host.resources.mediaPath(_bookId, source, 'audio')});
        } else if (type.isEmpty || type == 'text') {
          source = textOf(row, 'phonetic');
          if (source.isEmpty) continue;
          clips.add({'id': _itemId(row), 'path': await widget.host.resources.audioPath(_bookId, source)});
        }
      }
      if (clips.isEmpty) throw StateError('当前没有可播放的单词音频');
      final wanted = all ? _batchStartId : null;
      final start = wanted == null ? -1 : clips.indexWhere((clip) => clip['id'] == wanted);
      if (!all && _owns && _playback.active && _playback.playingId == clips.first['id']) {
        await (_playback.paused ? _playback.resume() : _playback.stop());
        return;
      }
      await _playback.start({
        'lesson': _identity,
        'title': textOf(widget.lesson, 'title'),
        'words': true,
        'batch': all,
        'speed': widget.host.speed,
        'repeat': _repeat,
        'intervalSteps': _interval,
        'startIndex': start < 0 ? 0 : start,
        'clips': all ? clips : [clips.first],
      });
      if (mounted) setState(() => _batchStartId = clips[start < 0 ? 0 : start]['id'] as String);
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_words', operation: '播放单词媒体');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        GlassSnackBar(content: Text(userError(error, fallback: '单词媒体播放失败'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _playHotspot(RowData row, CourseImageHotspot hotspot) async {
    if (_busy || _blocked) return;
    setState(() => _busy = true);
    try {
      await _video.stop();
      if (_playback.active) await _playback.stop();
      final path = await widget.host.resources.audioPath(_bookId, hotspot.audioSource);
      await _playback.start({
        'lesson': _identity, 'title': hotspot.label, 'words': true, 'batch': false,
        'speed': widget.host.speed, 'repeat': 1, 'intervalSteps': 0, 'startIndex': 0,
        'clips': [{'id': 'word-hotspot:${row['id']}:${hotspot.id}', 'path': path}],
      });
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_words', operation: '播放互动单词音频');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        GlassSnackBar(content: Text(userError(error, fallback: '单词媒体播放失败'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startVideo(RowData row) async {
    if (_busy || _blocked) return;
    await _video.play(id: textOf(row, 'id'), book: _bookId,
      resolvePath: () => widget.host.resources.mediaPath(_bookId, textOf(row, 'media_src'), 'video'),
      beforePlay: () async { if (_playback.active) await _playback.stop(); });
  }

  Future<void> _complete() async {
    if (_completing || _completed.contains('word') || _rows.isEmpty) return;
    setState(() => _completing = true);
    try {
      final confirmed = await showGlassDialog<bool>(context: context, builder: (context) => GlassAlertDialog(
        title: const Text('操作提示'), content: const Text('确定将本课的单词标记为已完成吗？\n确认后将更新学习进度。'),
        actions: [
          StudyButton.text(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          StudyButton.filled(onPressed: () => Navigator.pop(context, true), child: const Text('确认')),
        ],
      ));
      if (confirmed != true || !mounted) return;
      await widget.host.store.complete(widget.book, widget.lesson, 'word');
      if (mounted) setState(() => _completed.add('word'));
      await widget.host.reload();
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_words', operation: '标记单词完成');
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  Widget _card({Key? key, required Widget child, VoidCallback? onTap, bool active = false}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(key: key, padding: const EdgeInsets.only(bottom: 12), child: StudyPanel(
      color: active ? (dark ? const Color(0xFF154D38) : const Color(0xFFC5F2D6))
        : (dark ? const Color(0xFF252525) : Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: active ? (dark ? const Color(0xFF71E5A4) : const Color(0xFF16864B))
          : Colors.transparent, width: 2)),
      clipBehavior: Clip.antiAlias,
      child: StudyInkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17), child: child)),
    ));
  }

  Widget _row(RowData row) {
    final type = textOf(row, 'media_type');
    if (type == 'image') {
      return CourseImageCard(key: ValueKey('word-image:${row['id']}'), source: textOf(row, 'media_src'),
        label: '单词插图', resolvePath: () => widget.host.resources.mediaPath(_bookId, textOf(row, 'media_src'), 'image'));
    }
    if (type == 'interactive_image') {
      return CourseInteractiveImageCard(key: ValueKey('word-interactive:${row['id']}'),
        source: textOf(row, 'media_src'), label: '互动单词插图', mediaConfig: textOf(row, 'media_config'),
        resolvePath: () => widget.host.resources.mediaPath(_bookId, textOf(row, 'media_src'), 'interactive_image'),
        onActivate: (hotspot) => _playHotspot(row, hotspot), interactionEnabled: !_busy && !_blocked);
    }
    if (type == 'video') {
      return CourseVideoCard(key: ValueKey('word-video:${row['id']}'), controller: _video,
        id: textOf(row, 'id'), source: textOf(row, 'media_src'),
        resolvePath: () => widget.host.resources.mediaPath(_bookId, textOf(row, 'media_src'), 'video'),
        onPlay: () => _startVideo(row), enabled: !_busy && !_blocked);
    }
    if (type.isNotEmpty && type != 'text' && type != 'audio') {
      return _card(child: const Text('此单词媒体类型暂不支持'));
    }
    final id = _itemId(row);
    final reading = textOf(row, 'kana').replaceFirst(RegExp(r'@.*$'), '');
    final surface = plainJapanese(textOf(row, 'word'));
    return _card(key: _anchors.putIfAbsent(id, GlobalKey.new), active: _owns && _playback.playingId == id,
      onTap: !_busy && !_blocked ? () => _playRows([row], false) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Align(alignment: Alignment.centerLeft, child: Column(mainAxisSize: MainAxisSize.min, children: [
            keepSpace(widget.host.ruby, Text(reading, style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'), fontSize: 12, height: 1.3, color: Color(0xFF32AA43)))),
            keepSpace(widget.host.source, Text(surface.isNotEmpty ? surface : textOf(row, 'kanji').isNotEmpty ? textOf(row, 'kanji') : reading,
              style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'), fontSize: 19, height: 1.5))),
          ]))),
          if (textOf(row, 'pos').isNotEmpty) ...[
            const SizedBox(width: 10),
            ConstrainedBox(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .3),
              child: Text('[${row['pos']}]', textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 16, height: 1.5, color: Color(0xFF32AA43)))),
          ],
        ]),
        const SizedBox(height: 5),
        keepSpace(widget.host.translation, Align(alignment: Alignment.centerRight,
          child: Text(textOf(row, 'definition'), textAlign: TextAlign.right,
            style: const TextStyle(fontFamily: 'PingFang SC', locale: Locale('zh', 'CN'), fontSize: 16, color: Colors.grey)))),
        if (type == 'audio' || textOf(row, 'phonetic').isEmpty)
          Text(type == 'audio' ? '附加音频' : '暂无音频', style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    );
  }

  Widget _bottom() {
    if (_batchMode) {
      final active = _owns && _playback.active;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: StudyButton.text(onPressed: _busy ? null : active ? _playback.stop : () => _playRows(_rows, true),
            child: Text(active ? '结束' : '全部播放'))),
          const SizedBox(width: 12),
          Expanded(child: StudyButton.text(onPressed: _busy ? null : () => setState(() => _repeat = _repeat % 5 + 1),
            child: Text('循环 $_repeat 次'))),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: StudyButton.text(onPressed: active || _busy ? null : () => setState(() => _batchMode = false),
            child: const Text('返回'))),
          const SizedBox(width: 12),
          Expanded(child: StudyButton.text(onPressed: _busy ? null : () => setState(() => _interval = (_interval + 1) % 7),
            child: Text('间隔 ${(_interval * .5).toStringAsFixed(1)} 秒'))),
        ]),
      ]);
    }
    final complete = _completed.contains('word');
    return Row(children: [
      Expanded(child: StudyButton.textIcon(icon: const Icon(Icons.playlist_play), label: const Text('全部播放'),
        onPressed: _busy || _blocked ? null : () => setState(() => _batchMode = true))),
      const SizedBox(width: 12),
      Expanded(child: StudyButton.textIcon(icon: Icon(complete ? Icons.check_circle : Icons.radio_button_unchecked),
        label: Text(complete ? '已完成' : '标记完成'),
        onPressed: complete || _busy || _blocked || _rows.isEmpty ? null : _complete)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: StudyCircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 16),
        StudyButton.filled(onPressed: _load, child: const Text('重新读取单词')),
      ])));
    return Column(children: [
      Expanded(child: _rows.isEmpty
        ? const Center(child: Text('本课暂无单词数据'))
        : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 20), children: [
            const Padding(padding: EdgeInsets.fromLTRB(8, 8, 8, 12), child: Text('单词表', style: TextStyle(fontSize: 15, color: Colors.grey))),
            for (final row in _rows) _row(row),
          ])),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: _bottom())),
    ]);
  }
}

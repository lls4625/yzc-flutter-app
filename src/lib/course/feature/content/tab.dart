import 'dart:async';
import 'package:flutter/material.dart';
import '../../../data.dart';
import '../../../ios_lesson_playback.dart';
import '../../../system_errors.dart';
import '../../../ui.dart';
import '../../../user_error.dart';
import '../host.dart';
import 'image_interaction_config.dart';
import 'media_widgets.dart';
import '../video_controller.dart';

/// Independent implementation of the course content tab.
class CourseContentTab extends StatefulWidget {
  const CourseContentTab({required this.host, required this.book, required this.lesson, super.key});
  final CourseTabHost host;
  final RowData book, lesson;

  @override
  State<CourseContentTab> createState() => _CourseContentTabState();
}

class _CourseContentTabState extends State<CourseContentTab> with WidgetsBindingObserver {
  final _playback = IosLessonPlayback.instance;
  final _video = CourseVideoController();
  final _scroll = ScrollController();
  final _mediaViewport = GlobalKey();
  final _videoAnchors = <String, GlobalKey>{};
  List<RowData> _rows = [];
  Set<String> _completed = {};
  bool _loading = true, _busy = false, _batchMode = false, _completing = false;
  int _repeat = 1, _interval = 0;
  String? _error, _batchStartId;
  bool _resourceUpdating = false, _showVideoBar = false, _visibilityScheduled = false;

  String get _bookId => textOf(widget.book, 'id');
  String get _lessonId => textOf(widget.lesson, 'id');
  String get _identity => '$_bookId:$_lessonId:content';
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
    _video.addListener(_videoChanged);
    _scroll.addListener(_scheduleVideoVisibility);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.host.removeListener(_hostChanged);
    widget.host.resources.removeListener(_resourceChanged);
    _playback.removeListener(_playChanged);
    _video.removeListener(_videoChanged);
    _scroll.removeListener(_scheduleVideoVisibility);
    _scroll.dispose();
    if (_owns) unawaited(_playback.stop());
    _video.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(perform(context, _playback.refresh));
  }

  void _hostChanged() { if (mounted) setState(() {}); }
  void _playChanged() { if (mounted) setState(() {}); }
  void _videoChanged() {
    if (mounted) setState(() {});
    _scheduleVideoVisibility();
  }
  void _scheduleVideoVisibility() {
    if (!mounted || _visibilityScheduled) return;
    _visibilityScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityScheduled = false;
      if (!mounted) return;
      var show = false;
      if (_video.active && !_video.fullscreen) {
        final card = _videoAnchors[_video.rowId]?.currentContext?.findRenderObject();
        final viewport = _mediaViewport.currentContext?.findRenderObject();
        if (card is RenderBox && viewport is RenderBox && card.hasSize && viewport.hasSize) {
          final top = card.localToGlobal(Offset.zero).dy;
          final viewportTop = viewport.localToGlobal(Offset.zero).dy;
          show = top + card.size.height <= viewportTop || top >= viewportTop + viewport.size.height;
        }
      }
      if (show != _showVideoBar) setState(() => _showVideoBar = show);
    });
  }
  void _locateVideo() {
    final target = _videoAnchors[_video.rowId]?.currentContext;
    if (target != null) unawaited(Scrollable.ensureVisible(target,
      duration: const Duration(milliseconds: 250), alignment: .2));
  }
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
      final rows = await widget.host.store.content('yzc_content', _bookId, _lessonId);
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
      SystemErrors.record(error, stack, module: 'course_content', operation: '读取课文页签',
        context: {'textbook_id': _bookId, 'lesson_id': _lessonId});
      if (mounted) setState(() { _loading = false; _error = userError(error, fallback: '课文内容读取失败'); });
    }
  }

  String _itemId(RowData row) => 'content:${row['id']}';

  Future<void> _playRows(List<RowData> rows, bool all) async {
    if (_busy || _blocked) return;
    setState(() => _busy = true);
    try {
      await _video.stop();
      final clips = <RowData>[];
      for (final row in rows) {
        final type = textOf(row, 'media_type');
        if (type.isNotEmpty && type != 'text' && type != 'audio') continue;
        final file = type == 'audio' ? textOf(row, 'media_src') : textOf(row, 'phonetic');
        if (file.isEmpty) continue;
        final path = type == 'audio'
          ? await widget.host.resources.mediaPath(_bookId, file, 'audio')
          : await widget.host.resources.audioPath(_bookId, file);
        clips.add({'id': _itemId(row), 'path': path});
      }
      if (clips.isEmpty) throw StateError('当前没有可播放的课文音频');
      final wanted = all ? _batchStartId : null;
      final start = wanted == null ? -1 : clips.indexWhere((clip) => clip['id'] == wanted);
      if (!all && _owns && _playback.active && _playback.playingId == clips.first['id']) {
        await (_playback.paused ? _playback.resume() : _playback.stop());
        return;
      }
      await _playback.start({
        'lesson': _identity, 'title': textOf(widget.lesson, 'title'), 'words': false,
        'batch': all, 'speed': widget.host.speed, 'repeat': _repeat,
        'intervalSteps': _interval, 'startIndex': start < 0 ? 0 : start,
        'clips': all ? clips : [clips.first],
      });
      if (mounted) setState(() => _batchStartId = clips[start < 0 ? 0 : start]['id'] as String);
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_content', operation: '播放课文媒体');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        GlassSnackBar(content: Text(userError(error, fallback: '课文媒体播放失败'))));
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
        'lesson': _identity, 'title': hotspot.label, 'words': false, 'batch': false,
        'speed': widget.host.speed, 'repeat': 1, 'intervalSteps': 0, 'startIndex': 0,
        'clips': [{'id': 'content-hotspot:${row['id']}:${hotspot.id}', 'path': path}],
      });
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_content', operation: '播放互动课文音频');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        GlassSnackBar(content: Text(userError(error, fallback: '课文媒体播放失败'))));
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
    if (_completing || _completed.contains('content') || _rows.isEmpty) return;
    setState(() => _completing = true);
    try {
      final confirmed = await showGlassDialog<bool>(context: context, builder: (context) => GlassAlertDialog(
        title: const Text('操作提示'), content: const Text('确定将本课的课文标记为已完成吗？\n确认后将更新学习进度。'),
        actions: [
          StudyButton.text(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          StudyButton.filled(onPressed: () => Navigator.pop(context, true), child: const Text('确认')),
        ],
      ));
      if (confirmed != true || !mounted) return;
      await widget.host.store.complete(widget.book, widget.lesson, 'content');
      if (mounted) setState(() => _completed.add('content'));
      await widget.host.reload();
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_content', operation: '标记课文完成');
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  Widget _card({required Widget child, VoidCallback? onTap, bool active = false}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: StudyPanel(
      color: active ? (dark ? const Color(0xFF154D38) : const Color(0xFFC5F2D6))
        : (dark ? const Color(0xFF252525) : Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: active ? (dark ? const Color(0xFF71E5A4) : const Color(0xFF16864B))
          : Colors.transparent, width: 2)),
      clipBehavior: Clip.antiAlias,
      child: StudyInkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17), child: child)),
    ));
  }

  Widget _utterance(RowData row) {
    final id = _itemId(row);
    return StudyInkWell(onTap: !_busy && !_blocked ? () => _playRows([row], false) : null,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (textOf(row, 'role').isNotEmpty) Padding(padding: const EdgeInsets.only(right: 10),
          child: _RubyText('${row['role']}：', ruby: widget.host.ruby, fontSize: 17, color: Colors.orange)),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _RubyText(textOf(row, 'content'), ruby: widget.host.ruby, source: widget.host.source,
            active: _owns && _playback.playingId == id),
          if (textOf(row, 'definition').isNotEmpty) ...[
            const SizedBox(height: 7),
            keepSpace(widget.host.translation, Text(textOf(row, 'definition'),
              style: TextStyle(fontFamily: 'PingFang SC', locale: const Locale('zh', 'CN'),
                fontSize: 16, height: 1.5, color: row['category'] == '02' ? null : Colors.grey))),
          ],
        ])),
      ]));
  }

  List<Widget> _contentRows() {
    final widgets = <Widget>[];
    String? previousCategory;
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final category = textOf(row, 'category');
      if (category != previousCategory && category != '04') {
        widgets.add(Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Text(switch (category) {
            '01' => '文型', '02' => '例句', '03' => '应用课文', '05' => '对话', '06' => '课文', _ => category,
          }, style: const TextStyle(fontSize: 15, color: Colors.grey))));
      }
      previousCategory = category;
      final mediaType = textOf(row, 'media_type');
      if (mediaType == 'image') {
        widgets.add(CourseImageCard(key: ValueKey('content-image:${row['id']}'),
          source: textOf(row, 'media_src'), label: category == '05' ? '对话插图' : '课文插图',
          resolvePath: () => widget.host.resources.mediaPath(_bookId, textOf(row, 'media_src'), 'image')));
        continue;
      }
      if (mediaType == 'interactive_image') {
        widgets.add(CourseInteractiveImageCard(key: ValueKey('content-interactive:${row['id']}'),
          source: textOf(row, 'media_src'), label: category == '05' ? '互动对话插图' : '互动课文插图',
          mediaConfig: textOf(row, 'media_config'),
          resolvePath: () => widget.host.resources.mediaPath(_bookId, textOf(row, 'media_src'), 'interactive_image'),
          onActivate: (hotspot) => _playHotspot(row, hotspot), interactionEnabled: !_busy && !_blocked));
        continue;
      }
      if (mediaType == 'video') {
        final id = textOf(row, 'id');
        widgets.add(CourseVideoCard(key: _videoAnchors.putIfAbsent(id, GlobalKey.new), controller: _video,
          id: id, source: textOf(row, 'media_src'),
          resolvePath: () => widget.host.resources.mediaPath(_bookId, textOf(row, 'media_src'), 'video'),
          onPlay: () => _startVideo(row), enabled: !_busy && !_blocked));
        continue;
      }
      if (mediaType.isNotEmpty && mediaType != 'text' && mediaType != 'audio') {
        widgets.add(_card(child: const Text('此课文媒体类型暂不支持')));
        continue;
      }
      if (category == '03') {
        widgets.add(Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: StudyInkWell(
          onTap: !_busy && !_blocked ? () => _playRows([row], false) : null,
          child: Column(children: [
            _RubyText(textOf(row, 'content'), ruby: widget.host.ruby, source: widget.host.source,
              centered: true, active: _owns && _playback.playingId == _itemId(row)),
            keepSpace(widget.host.translation, Text(textOf(row, 'definition'),
              style: const TextStyle(fontFamily: 'PingFang SC', locale: Locale('zh', 'CN'), color: Colors.grey, fontSize: 16))),
          ]))));
        continue;
      }
      final group = <RowData>[row];
      if (category == '02' && textOf(row, 'org').isNotEmpty) {
        while (i + 1 < _rows.length && _rows[i + 1]['category'] == category && _rows[i + 1]['org'] == row['org'] &&
            ['text', ''].contains(textOf(_rows[i + 1], 'media_type'))) {
          group.add(_rows[++i]);
        }
      }
      widgets.add(_card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var j = 0; j < group.length; j++) ...[if (j > 0) const SizedBox(height: 24), _utterance(group[j])],
      ])));
    }
    return widgets;
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
          Expanded(child: StudyButton.text(onPressed: active || _busy ? null : () => setState(() => _batchMode = false), child: const Text('返回'))),
          const SizedBox(width: 12),
          Expanded(child: StudyButton.text(onPressed: _busy ? null : () => setState(() => _interval = (_interval + 1) % 7),
            child: Text('间隔 ${(_interval * .5).toStringAsFixed(1)} 秒'))),
        ]),
      ]);
    }
    final complete = _completed.contains('content');
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
        StudyButton.filled(onPressed: _load, child: const Text('重新读取课文')),
      ])));
    return Column(children: [
      Expanded(child: _rows.isEmpty ? const Center(child: Text('本课暂无课文数据'))
        : NotificationListener<ScrollMetricsNotification>(onNotification: (_) { _scheduleVideoVisibility(); return false; },
            child: ListView(key: _mediaViewport, controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20), children: _contentRows()))),
      SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_showVideoBar && _video.active && !_video.fullscreen)
          CourseVideoBar(controller: _video, onLocate: _locateVideo),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: _bottom()),
      ])),
    ]);
  }
}

class _RubyText extends StatelessWidget {
  const _RubyText(this.text, {required this.ruby, this.source = true, this.centered = false,
    this.active = false, this.fontSize = 19, this.color});
  final String text;
  final bool ruby, source, centered, active;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = <Widget>[];
    void add(String surface, String reading) {
      final highlighted = active && surface.trim().isNotEmpty;
      tokens.add(Column(mainAxisSize: MainAxisSize.min, children: [
        keepSpace(ruby, Text(reading.isEmpty ? ' ' : reading,
          style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'),
            fontSize: 12, height: 1.3, color: Color(0xFF32AA43)))),
        keepSpace(source, Text(surface, style: TextStyle(fontFamily: 'Hiragino Sans',
          locale: const Locale('ja', 'JP'), fontSize: fontSize, height: 1.5,
          color: highlighted ? (dark ? const Color(0xFFFFB366) : const Color(0xFFB85C00)) : color))),
      ]));
    }
    var offset = 0;
    for (final match in RegExp(r'!([^!\s()]+)\(([^)]*)\)').allMatches(text)) {
      for (final rune in text.substring(offset, match.start).runes) { add(String.fromCharCode(rune), ''); }
      add(match.group(1)!, match.group(2)!);
      offset = match.end;
    }
    for (final rune in text.substring(offset).runes) { add(String.fromCharCode(rune), ''); }
    return Wrap(alignment: centered ? WrapAlignment.center : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.end, children: tokens);
  }
}

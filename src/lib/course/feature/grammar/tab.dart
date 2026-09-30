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

/// Independent implementation of the course grammar tab.
class CourseGrammarTab extends StatefulWidget {
  const CourseGrammarTab({required this.host, required this.book, required this.lesson, super.key});
  final CourseTabHost host;
  final RowData book, lesson;

  @override
  State<CourseGrammarTab> createState() => _CourseGrammarTabState();
}

class _CourseGrammarTabState extends State<CourseGrammarTab> {
  final _playback = IosLessonPlayback.instance;
  final _video = CourseVideoController();
  final _expanded = <String>{};
  List<RowData> _rows = [];
  Set<String> _completed = {};
  bool _loading = true, _busy = false, _completing = false, _resourceUpdating = false;
  String? _error;

  String get _bookId => textOf(widget.book, 'id');
  String get _lessonId => textOf(widget.lesson, 'id');
  String get _identity => '$_bookId:$_lessonId:grammar';
  bool get _blocked => widget.host.resources.unavailable.contains(_bookId) ||
    widget.host.resources.activeBook == _bookId;

  @override
  void initState() {
    super.initState();
    widget.host.addListener(_hostChanged);
    widget.host.resources.addListener(_resourceChanged);
    _playback.addListener(_playChanged);
    _video.addListener(_videoChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.host.removeListener(_hostChanged);
    widget.host.resources.removeListener(_resourceChanged);
    _playback.removeListener(_playChanged);
    _video.removeListener(_videoChanged);
    if (_playback.lesson == _identity) unawaited(_playback.stop());
    _video.dispose();
    super.dispose();
  }

  void _hostChanged() { if (mounted) setState(() {}); }
  void _playChanged() { if (mounted) setState(() {}); }
  void _videoChanged() { if (mounted) setState(() {}); }
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
      final rows = await widget.host.store.content('yzc_grammar', _bookId, _lessonId);
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
      SystemErrors.record(error, stack, module: 'course_grammar', operation: '读取文法页签',
        context: {'textbook_id': _bookId, 'lesson_id': _lessonId});
      if (mounted) setState(() { _loading = false; _error = userError(error, fallback: '文法内容读取失败'); });
    }
  }

  Future<void> _playAudio(RowData row, {String? filename, String? title}) async {
    if (_busy || _blocked) return;
    setState(() => _busy = true);
    try {
      await _video.stop();
      if (_playback.active) await _playback.stop();
      final source = filename ?? textOf(row, 'media_src');
      final path = filename == null
        ? await widget.host.resources.mediaPath(_bookId, source, 'audio')
        : await widget.host.resources.audioPath(_bookId, source);
      await _playback.start({
        'lesson': _identity, 'title': title ?? '文法例句', 'words': false, 'batch': false,
        'speed': widget.host.speed, 'repeat': 1, 'intervalSteps': 0, 'startIndex': 0,
        'clips': [{'id': 'grammar:${row['id']}:${filename ?? source}', 'path': path}],
      });
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_grammar', operation: '播放文法媒体');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        GlassSnackBar(content: Text(userError(error, fallback: '文法媒体播放失败'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _playHotspot(RowData row, CourseImageHotspot hotspot) =>
    _playAudio(row, filename: hotspot.audioSource, title: hotspot.label);

  Future<void> _startVideo(RowData row) async {
    if (_busy || _blocked) return;
    await _video.play(id: textOf(row, 'id'), book: _bookId,
      resolvePath: () => widget.host.resources.mediaPath(_bookId, textOf(row, 'media_src'), 'video'),
      beforePlay: () async { if (_playback.active) await _playback.stop(); });
  }

  Future<void> _complete() async {
    if (_completing || _completed.contains('grammar') || _rows.isEmpty) return;
    setState(() => _completing = true);
    try {
      final confirmed = await showGlassDialog<bool>(context: context, builder: (context) => GlassAlertDialog(
        title: const Text('操作提示'), content: const Text('确定将本课的文法标记为已完成吗？\n确认后将更新学习进度。'),
        actions: [
          StudyButton.text(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          StudyButton.filled(onPressed: () => Navigator.pop(context, true), child: const Text('确认')),
        ],
      ));
      if (confirmed != true || !mounted) return;
      await widget.host.store.complete(widget.book, widget.lesson, 'grammar');
      if (mounted) setState(() => _completed.add('grammar'));
      await widget.host.reload();
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_grammar', operation: '标记文法完成');
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  Widget _media(RowData row) {
    final type = textOf(row, 'media_type');
    if (type == 'image') {
      return CourseImageCard(key: ValueKey('grammar-image:${row['id']}'), source: textOf(row, 'media_src'),
        label: '文法插图', resolvePath: () => widget.host.resources.mediaPath(_bookId, textOf(row, 'media_src'), 'image'));
    }
    if (type == 'interactive_image') {
      return CourseInteractiveImageCard(key: ValueKey('grammar-interactive:${row['id']}'),
        source: textOf(row, 'media_src'), label: '互动文法插图', mediaConfig: textOf(row, 'media_config'),
        resolvePath: () => widget.host.resources.mediaPath(_bookId, textOf(row, 'media_src'), 'interactive_image'),
        onActivate: (hotspot) => _playHotspot(row, hotspot), interactionEnabled: !_busy && !_blocked);
    }
    if (type == 'video') {
      return CourseVideoCard(key: ValueKey('grammar-video:${row['id']}'), controller: _video,
        id: textOf(row, 'id'), source: textOf(row, 'media_src'),
        resolvePath: () => widget.host.resources.mediaPath(_bookId, textOf(row, 'media_src'), 'video'),
        onPlay: () => _startVideo(row), enabled: !_busy && !_blocked);
    }
    if (type == 'audio') {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: StudyButton.outlined(
        onPressed: _busy || _blocked ? null : () => _playAudio(row),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.volume_up_outlined), SizedBox(width: 8), Text('播放文法音频'),
        ])));
    }
    return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('此文法媒体类型暂不支持'));
  }

  Widget _grammarBody() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? const Color(0xFFDDDDDD) : const Color(0xFF595959);
    final titleColor = dark ? const Color(0xFFFFB366) : const Color(0xFFB85C00);
    final border = dark ? const Color(0xFF454545) : const Color(0xFFDDDDDD);
    final byId = {for (final row in _rows) textOf(row, 'id'): row};
    final children = <String, List<RowData>>{};
    final roots = <RowData>[];
    for (final row in _rows) {
      final parent = textOf(row, 'pid');
      if (parent.isEmpty || !byId.containsKey(parent) || parent == textOf(row, 'id')) {
        roots.add(row);
      } else {
        children.putIfAbsent(parent, () => []).add(row);
      }
    }
    final visited = <String>{};

    Widget grammarText(RowData row, String key) {
      final subtitle = textOf(row, 'type') == '4' && key == 'content';
      final example = textOf(row, 'type') == '3' || key == 'example' || key == 'example_definition';
      return Padding(padding: EdgeInsets.only(left: example ? 16 : 0, top: subtitle ? 16 : 10),
        child: Text.rich(contentTextSpan(plainJapanese(textOf(row, key)),
          japanese: key == 'example' || (key == 'content' && textOf(row, 'content').contains('▶∫'))),
          style: TextStyle(fontSize: subtitle ? 17 : example ? 14 : 16, height: 1.6,
            fontWeight: subtitle ? FontWeight.w600 : FontWeight.normal,
            color: subtitle ? titleColor : foreground)));
    }

    List<Widget> paragraphs(RowData row) {
      final id = textOf(row, 'id');
      if (!visited.add(id)) return [];
      final type = textOf(row, 'media_type');
      final result = <Widget>[];
      if (type.isNotEmpty && type != 'text') {
        result.add(_media(row));
      } else {
        for (final key in ['content', 'definition', 'connection', 'example', 'example_definition', 'tip']) {
          if (textOf(row, key).isNotEmpty) result.add(grammarText(row, key));
        }
      }
      for (final child in children[id] ?? <RowData>[]) { result.addAll(paragraphs(child)); }
      return result;
    }

    var number = 0;
    Widget section(RowData row) {
      final id = textOf(row, 'id');
      final mediaType = textOf(row, 'media_type');
      final mainTitle = textOf(row, 'type') == '1' && (mediaType.isEmpty || mediaType == 'text');
      if (!mainTitle) {
        return Padding(padding: const EdgeInsets.only(bottom: 20), child: Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
          decoration: BoxDecoration(color: dark ? const Color(0xFF252525) : Colors.white,
            border: Border.all(color: border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: paragraphs(row))));
      }
      visited.add(id);
      final title = '${++number}. ${plainJapanese(textOf(row, 'content'))}';
      final body = <Widget>[
        for (final key in ['definition', 'connection', 'example', 'example_definition', 'tip'])
          if (textOf(row, key).isNotEmpty) grammarText(row, key),
        for (final child in children[id] ?? <RowData>[]) ...paragraphs(child),
      ];
      final expanded = _expanded.contains(id);
      return Padding(key: ValueKey(id), padding: const EdgeInsets.only(bottom: 24), child: StudyPanel(
        color: dark ? const Color(0xFF252525) : Colors.white,
        shape: RoundedRectangleBorder(side: BorderSide(color: border)), clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(button: true, expanded: expanded, child: StudyInkWell(
            onTap: () => setState(() { expanded ? _expanded.remove(id) : _expanded.add(id); }),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: Row(children: [
              Expanded(child: Text.rich(contentTextSpan(title), style: TextStyle(fontSize: 18, height: 1.4,
                fontWeight: FontWeight.w600, color: titleColor))),
              const SizedBox(width: 12),
              Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: foreground, size: 22),
            ])))),
          if (expanded && body.isNotEmpty) ...[
            StudyDivider(height: 1, thickness: 1, color: border),
            Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body)),
          ],
        ])));
    }

    return ColoredBox(color: dark ? const Color(0xFF1B1B1B) : const Color(0xFFF1F1F1),
      child: DefaultTextStyle.merge(style: TextStyle(color: foreground),
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 20), children: [
          const Padding(padding: EdgeInsets.only(bottom: 12),
            child: Text('• 语法解释', style: TextStyle(fontSize: 18, height: 1.5))),
          for (final row in roots) section(row),
          for (final row in _rows) if (!visited.contains(textOf(row, 'id'))) section(row),
        ])));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: StudyCircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 16),
        StudyButton.filled(onPressed: _load, child: const Text('重新读取文法')),
      ])));
    final complete = _completed.contains('grammar');
    return Column(children: [
      Expanded(child: _rows.isEmpty ? const Center(child: Text('本课暂无文法数据')) : _grammarBody()),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          const Spacer(),
          Expanded(flex: 2, child: StudyButton.textIcon(
            icon: Icon(complete ? Icons.check_circle : Icons.radio_button_unchecked),
            label: Text(complete ? '已完成' : '标记完成'),
            onPressed: complete || _busy || _blocked || _rows.isEmpty ? null : _complete)),
          const Spacer(),
        ]))),
    ]);
  }
}

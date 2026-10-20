import '../../../l10n/l10n.dart';
import '../../../content_language.dart';

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
import '../tab_coordinator.dart';

/// Independent implementation of the course grammar tab.
class CourseGrammarTab extends StatefulWidget {
  const CourseGrammarTab({
    required this.host,
    required this.book,
    required this.lesson,
    required this.coordinator,
    super.key,
  });
  final CourseTabHost host;
  final RowData book, lesson;
  final CourseTabCoordinator coordinator;

  @override
  State<CourseGrammarTab> createState() => _CourseGrammarTabState();
}

class _CourseGrammarTabState extends State<CourseGrammarTab> {
  final _playback = IosLessonPlayback.instance;
  final _video = CourseVideoController();
  final _expanded = <String>{};
  List<RowData> _rows = [];
  Set<String> _completed = {};
  bool _loading = true,
      _busy = false,
      _completing = false,
      _resourceUpdating = false;
  String? _error;

  ContentLanguage get _language => ContentLanguage.fromTextbook(widget.book);
  String get _bookId => textOf(widget.book, 'id');
  String get _lessonId => textOf(widget.lesson, 'id');
  String get _identity => '$_bookId:$_lessonId:grammar';
  bool get _blocked =>
      widget.host.resources.unavailable.contains(_bookId) ||
      widget.host.resources.activeBook == _bookId;

  @override
  void initState() {
    super.initState();
    widget.host.addListener(_hostChanged);
    widget.host.resources.addListener(_resourceChanged);
    _playback.addListener(_playChanged);
    _video.addListener(_videoChanged);
    widget.coordinator.attach(
      this,
      bottomBuilder: (_) => _bottomBar(),
      stopForTabChange: _stopForTabChange,
      stopVideo: _video.stop,
      videoFullscreen: () => _video.fullscreen,
      busy: _busy,
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.coordinator.detach(this);
    widget.host.removeListener(_hostChanged);
    widget.host.resources.removeListener(_resourceChanged);
    _playback.removeListener(_playChanged);
    _video.removeListener(_videoChanged);
    _video.dispose();
    super.dispose();
  }

  void _syncCoordinator() => widget.coordinator.update(
    this,
    busy: _busy || _video.busy || _playback.stopping,
  );
  void _hostChanged() {
    if (mounted) {
      setState(() {});
      _syncCoordinator();
    }
  }

  void _playChanged() {
    if (mounted) {
      setState(() {});
      _syncCoordinator();
    }
  }

  void _videoChanged() {
    if (mounted) {
      setState(() {});
      _syncCoordinator();
    }
  }

  void _resourceChanged() {
    if (widget.host.resources.activeBook == _bookId) _resourceUpdating = true;
    if (_resourceUpdating && widget.host.resources.activeBook == null) {
      _resourceUpdating = false;
      unawaited(_load());
    }
    if (mounted) {
      setState(() {});
      _syncCoordinator();
    }
  }

  Future<void> _load() async {
    try {
      final rows = await widget.host.store.content(
        'yzc_grammar',
        _bookId,
        _lessonId,
      );
      final progress = await widget.host.store.progress(_bookId);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _completed = progress
            .where((row) => row['lessons_id'] == _lessonId)
            .map((row) => textOf(row, 'category'))
            .toSet();
        _loading = false;
        _error = null;
      });
      _syncCoordinator();
    } catch (error, stack) {
      SystemErrors.record(
        error,
        stack,
        module: 'course_grammar',
        operation: '读取文法页签',
        context: {'textbook_id': _bookId, 'lesson_id': _lessonId},
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _error = userError(error, fallback: '文法内容读取失败');
        });
        _syncCoordinator();
      }
    }
  }

  Future<void> _stopForTabChange() async {
    await _video.stop();
    if (_playback.lesson == _identity) await _playback.stop();
  }

  Future<void> _playAudio(
    RowData row, {
    String? filename,
    String? title,
  }) async {
    if (_busy || _blocked) return;
    setState(() => _busy = true);
    _syncCoordinator();
    try {
      await _video.stop();
      if (_playback.active) await _playback.stop();
      final source = filename ?? textOf(row, 'media_src');
      final path = filename == null
          ? await widget.host.resources.mediaPath(_bookId, source, 'audio')
          : await widget.host.resources.audioPath(_bookId, source);
      await _playback.start({
        'lesson': _identity,
        'title': title ?? context.tr('文法例句', '文法例句', 'Grammar example', '文法例文'),
        'words': false,
        'batch': false,
        'speed': widget.host.speed,
        'repeat': 1,
        'intervalSteps': 0,
        'startIndex': 0,
        'clips': [
          {'id': 'grammar:${row['id']}:${filename ?? source}', 'path': path},
        ],
      });
    } catch (error, stack) {
      SystemErrors.record(
        error,
        stack,
        module: 'course_grammar',
        operation: '播放文法媒体',
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          GlassSnackBar(
            content: Builder(
              builder: (context) =>
                  Text(context.ui(userError(error, fallback: '文法媒体播放失败'))),
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _syncCoordinator();
      }
    }
  }

  Future<void> _playHotspot(RowData row, CourseImageHotspot hotspot) =>
      _playAudio(row, filename: hotspot.audioSource, title: hotspot.label);

  Future<void> _startVideo(RowData row) async {
    if (_busy || _blocked) return;
    await _video.play(
      id: textOf(row, 'id'),
      book: _bookId,
      resolvePath: () => widget.host.resources.mediaPath(
        _bookId,
        textOf(row, 'media_src'),
        'video',
      ),
      beforePlay: () async {
        if (_playback.active) await _playback.stop();
      },
    );
  }

  Future<void> _complete() async {
    if (_completing || _completed.contains('grammar') || _rows.isEmpty) return;
    setState(() => _completing = true);
    _syncCoordinator();
    try {
      final confirmed = await showGlassDialog<bool>(
        context: context,
        builder: (context) => GlassAlertDialog(
          title: Text(context.tr('操作提示', '操作提示', 'Confirm action', '操作の確認')),
          content: Text(
            context.tr(
              '确定将本课的文法标记为已完成吗？\n确认后将更新学习进度。',
              '確定將本課的文法標記為已完成嗎？\n確認後將更新學習進度。',
              'Mark this lesson’s grammar complete?\nYour learning progress will be updated.',
              'この課の文法を完了にしますか？\n学習進捗が更新されます。',
            ),
          ),
          actions: [
            StudyButton.text(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('取消', '取消', 'Cancel', 'キャンセル')),
            ),
            StudyButton.filled(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('确认', '確認', 'Confirm', '確認')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.host.store.complete(widget.book, widget.lesson, 'grammar');
      if (mounted) setState(() => _completed.add('grammar'));
      _syncCoordinator();
      await widget.host.reload();
    } catch (error, stack) {
      SystemErrors.record(
        error,
        stack,
        module: 'course_grammar',
        operation: '标记文法完成',
      );
    } finally {
      if (mounted) {
        setState(() => _completing = false);
        _syncCoordinator();
      }
    }
  }

  Future<void> _cancelCompletion() async {
    if (_completing || !_completed.contains('grammar')) return;
    setState(() => _completing = true);
    _syncCoordinator();
    try {
      final confirmed = await showGlassDialog<bool>(
        context: context,
        builder: (context) => GlassAlertDialog(
          title: Text(context.tr('取消提示', '取消提示', 'Undo completion', '完了を取り消す')),
          content: Text(
            context.tr(
              '是否取消本课文法的已完成状态？\n取消后将恢复为“标记完成”。\n学习进度和课程状态会同步更新，历史学习记录保留。',
              '是否取消本課文法的已完成狀態？\n取消後將恢復為「標記完成」。\n學習進度和課程狀態會同步更新，歷史學習紀錄保留。',
              'Undo completion of this lesson’s grammar?\nYou can mark it complete again. Progress and lesson status will update; learning history is kept.',
              'この課の文法の完了を取り消しますか？\n再び「完了にする」と表示されます。学習進捗と課の状態は更新されますが、学習履歴は保持されます。',
            ),
          ),
          actions: [
            StudyButton.text(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('取消', '取消', 'Cancel', 'キャンセル')),
            ),
            StudyButton.filled(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('确认', '確認', 'Confirm', '確認')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.host.store.cancelCompletion(
        widget.book,
        widget.lesson,
        'grammar',
      );
      if (mounted) setState(() => _completed.remove('grammar'));
      await widget.host.reload();
    } catch (error, stack) {
      SystemErrors.record(
        error,
        stack,
        module: 'course_grammar',
        operation: '取消文法完成状态',
      );
    } finally {
      if (mounted) {
        setState(() => _completing = false);
        _syncCoordinator();
      }
    }
  }

  Widget _bottomBar() {
    final complete = _completed.contains('grammar');
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Spacer(),
            Expanded(
              flex: 2,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: complete && !_completing && !_busy && !_blocked
                    ? _cancelCompletion
                    : null,
                child: StudyButton.textIcon(
                  icon: Icon(
                    complete
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                  ),
                  label: Text(
                    complete
                        ? context.tr('已完成', '已完成', 'Completed', '完了')
                        : context.tr('标记完成', '標記完成', 'Mark complete', '完了にする'),
                  ),
                  onPressed: complete || _busy || _blocked || _rows.isEmpty
                      ? null
                      : _complete,
                ),
              ),
            ),
            Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _media(RowData row) {
    final type = textOf(row, 'media_type');
    if (type == 'image') {
      return CourseImageCard(
        key: ValueKey('grammar-image:${row['id']}'),
        source: textOf(row, 'media_src'),
        label: '文法插图',
        resolvePath: () => widget.host.resources.mediaPath(
          _bookId,
          textOf(row, 'media_src'),
          'image',
        ),
      );
    }
    if (type == 'interactive_image') {
      return CourseInteractiveImageCard(
        key: ValueKey('grammar-interactive:${row['id']}'),
        source: textOf(row, 'media_src'),
        label: '互动文法插图',
        mediaConfig: textOf(row, 'media_config'),
        resolvePath: () => widget.host.resources.mediaPath(
          _bookId,
          textOf(row, 'media_src'),
          'interactive_image',
        ),
        hotspotAvailable: (hotspot) =>
            widget.host.resources.hasAudio(_bookId, hotspot.audioSource),
        onActivate: (hotspot) => _playHotspot(row, hotspot),
        interactionEnabled: !_busy && !_blocked,
      );
    }
    if (type == 'video') {
      return CourseVideoCard(
        key: ValueKey('grammar-video:${row['id']}'),
        controller: _video,
        id: textOf(row, 'id'),
        source: textOf(row, 'media_src'),
        resolvePath: () => widget.host.resources.mediaPath(
          _bookId,
          textOf(row, 'media_src'),
          'video',
        ),
        onPlay: () => _startVideo(row),
        enabled: !_busy && !_blocked,
      );
    }
    if (type == 'audio') {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: StudyButton.outlined(
          onPressed: _busy || _blocked ? null : () => _playAudio(row),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.volume_up_outlined),
              SizedBox(width: 8),
              Text(
                context.tr(
                  '播放文法音频',
                  '播放文法音訊',
                  'Play grammar audio',
                  '文法の音声を再生',
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text(
        context.tr(
          '此文法媒体类型暂不支持',
          '此文法媒體類型暫不支援',
          'This grammar media type is not supported',
          'この文法のメディア形式には対応していません',
        ),
      ),
    );
  }

  Widget _grammarBody() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? Color(0xFFDDDDDD) : Color(0xFF595959);
    final titleColor = dark ? Color(0xFFFFB366) : Color(0xFFB85C00);
    final border = dark ? Color(0xFF454545) : Color(0xFFDDDDDD);
    final byId = {for (final row in _rows) textOf(row, 'id'): row};
    final children = <String, List<RowData>>{};
    final roots = <RowData>[];
    for (final row in _rows) {
      final parent = textOf(row, 'pid');
      if (parent.isEmpty ||
          !byId.containsKey(parent) ||
          parent == textOf(row, 'id')) {
        roots.add(row);
      } else {
        children.putIfAbsent(parent, () => []).add(row);
      }
    }
    final visited = <String>{};

    Widget grammarText(RowData row, String key) {
      final subtitle = textOf(row, 'type') == '4' && key == 'content';
      final example =
          textOf(row, 'type') == '3' ||
          key == 'example' ||
          key == 'example_definition';
      return Padding(
        padding: EdgeInsets.only(
          left: example ? 16 : 0,
          top: subtitle ? 16 : 10,
        ),
        child: Text.rich(
          contentTextSpan(
            plainContentText(
              textOf(row, key),
              grammarFieldLanguage(
                _language,
                key,
                type: textOf(row, 'type'),
                content: textOf(row, 'content'),
              ),
            ),
            language: grammarFieldLanguage(
              _language,
              key,
              type: textOf(row, 'type'),
              content: textOf(row, 'content'),
            ),
          ),
          style: TextStyle(
            fontSize: subtitle
                ? 17
                : example
                ? 14
                : 16,
            height: 1.6,
            fontWeight: subtitle ? FontWeight.w600 : FontWeight.normal,
            color: subtitle ? titleColor : foreground,
          ),
        ),
      );
    }

    List<Widget> paragraphs(RowData row) {
      final id = textOf(row, 'id');
      if (!visited.add(id)) return [];
      final type = textOf(row, 'media_type');
      final result = <Widget>[];
      if (type.isNotEmpty && type != 'text') {
        result.add(_media(row));
      } else {
        for (final key in [
          'content',
          'definition',
          'connection',
          'example',
          'example_definition',
          'tip',
        ]) {
          if (textOf(row, key).isNotEmpty) result.add(grammarText(row, key));
        }
      }
      for (final child in children[id] ?? <RowData>[]) {
        result.addAll(paragraphs(child));
      }
      return result;
    }

    var number = 0;
    Widget section(RowData row) {
      final id = textOf(row, 'id');
      final mediaType = textOf(row, 'media_type');
      final mainTitle =
          textOf(row, 'type') == '1' &&
          (mediaType.isEmpty || mediaType == 'text');
      if (!mainTitle) {
        return Padding(
          padding: EdgeInsets.only(bottom: 20),
          child: Container(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 20),
            decoration: BoxDecoration(
              color: dark ? Color(0xFF252525) : Colors.white,
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: paragraphs(row),
            ),
          ),
        );
      }
      visited.add(id);
      final title =
          '${++number}. ${plainContentText(textOf(row, 'content'), _language.sourceLanguage)}';
      final body = <Widget>[
        for (final key in [
          'definition',
          'connection',
          'example',
          'example_definition',
          'tip',
        ])
          if (textOf(row, key).isNotEmpty) grammarText(row, key),
        for (final child in children[id] ?? <RowData>[]) ...paragraphs(child),
      ];
      final expanded = _expanded.contains(id);
      return Padding(
        key: ValueKey(id),
        padding: EdgeInsets.only(bottom: 24),
        child: StudyPanel(
          color: dark ? Color(0xFF252525) : Colors.white,
          shape: RoundedRectangleBorder(side: BorderSide(color: border)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                expanded: expanded,
                child: StudyInkWell(
                  onTap: () => setState(() {
                    expanded ? _expanded.remove(id) : _expanded.add(id);
                  }),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            contentTextSpan(
                              title,
                              language: _language.sourceLanguage,
                            ),
                            style: TextStyle(
                              fontSize: 18,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: foreground,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (expanded && body.isNotEmpty) ...[
                StudyDivider(height: 1, thickness: 1, color: border),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 10, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: body,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ColoredBox(
      color: dark ? Color(0xFF1B1B1B) : Color(0xFFF1F1F1),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: foreground),
        child: ListView(
          padding: EdgeInsets.fromLTRB(14, 14, 14, 20),
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                context.tr(
                  '• 语法解释',
                  '• 文法解釋',
                  '• Grammar explanations',
                  '• 文法解説',
                ),
                style: TextStyle(fontSize: 18, height: 1.5),
              ),
            ),
            for (final row in roots) section(row),
            for (final row in _rows)
              if (!visited.contains(textOf(row, 'id'))) section(row),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Center(child: StudyCircularProgressIndicator());
    if (_error != null)
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.ui(_error!), textAlign: TextAlign.center),
              SizedBox(height: 16),
              StudyButton.filled(
                onPressed: _load,
                child: Text(
                  context.tr('重新读取文法', '重新讀取文法', 'Reload grammar', '文法を再読み込み'),
                ),
              ),
            ],
          ),
        ),
      );
    return _rows.isEmpty
        ? Center(
            child: Text(
              context.tr(
                '本课暂无文法数据',
                '本課暫無文法資料',
                'No grammar in this lesson',
                'この課の文法はありません',
              ),
            ),
          )
        : _grammarBody();
  }
}

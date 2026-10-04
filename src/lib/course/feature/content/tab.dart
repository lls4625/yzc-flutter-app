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
import '../tab_coordinator.dart';

/// Independent implementation of the course content tab.
class CourseContentTab extends StatefulWidget {
  const CourseContentTab({required this.host, required this.book, required this.lesson,
    required this.coordinator, super.key});
  final CourseTabHost host;
  final RowData book, lesson;
  final CourseTabCoordinator coordinator;

  @override
  State<CourseContentTab> createState() => _CourseContentTabState();
}

class _CourseContentTabState extends State<CourseContentTab> with WidgetsBindingObserver {
  final _playback = IosLessonPlayback.instance;
  final _video = CourseVideoController();
  final _scroll = ScrollController();
  final _mediaViewport = GlobalKey();
  final _videoAnchors = <String, GlobalKey>{};
  final _anchors = <String, GlobalKey>{};
  List<RowData> _rows = [];
  Set<String> _completed = {};
  bool _loading = true, _busy = false, _batchMode = false, _completing = false;
  bool _startingBatch = false, _stopping = false, _coolingDown = false;
  int _repeat = 1, _interval = 0;
  String? _error, _batchStartId, _lastPlaying;
  bool _resourceUpdating = false, _showVideoBar = false, _visibilityScheduled = false;
  Timer? _cooldownTimer;

  String get _bookId => textOf(widget.book, 'id');
  String get _lessonId => textOf(widget.lesson, 'id');
  String get _identity => '$_bookId:$_lessonId:content';
  bool get _owns => _playback.lesson == _identity;
  bool get _batchPlaybackActive => _owns && _playback.active && _playback.batch;
  bool get _playbackLocked => _busy || _stopping || _coolingDown || _playback.stopping;
  bool get _controlsDisabled => _loading || _error != null || _blocked || _playbackLocked;
  bool get _canPlayItem => !_batchPlaybackActive && !_playbackLocked && !_video.busy && !_blocked;
  bool get _blocked => widget.host.resources.unavailable.contains(_bookId) ||
    widget.host.resources.activeBook == _bookId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.host.addListener(_hostChanged);
    widget.host.resources.addListener(_resourceChanged);
    _playback.addListener(_playChanged);
    if (_batchPlaybackActive) {
      _batchMode = true;
      _repeat = _playback.repeat;
      _interval = _playback.intervalSteps;
      _batchStartId = _playback.playingId ?? _playback.queuedId;
    }
    _video.addListener(_videoChanged);
    _scroll.addListener(_scheduleVideoVisibility);
    widget.coordinator.attach(this, bottomBuilder: (_) => _bottomBar(),
      stopForTabChange: _stopForTabChange, stopVideo: _video.stop,
      videoFullscreen: () => _video.fullscreen,
      busy: _playbackLocked);
    unawaited(_load());
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    widget.coordinator.detach(this);
    WidgetsBinding.instance.removeObserver(this);
    widget.host.removeListener(_hostChanged);
    widget.host.resources.removeListener(_resourceChanged);
    _playback.removeListener(_playChanged);
    _video.removeListener(_videoChanged);
    _scroll.removeListener(_scheduleVideoVisibility);
    _scroll.dispose();
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
      SystemErrors.record(error, stack, module: 'course_content', operation: '课文页操作',
        context: {'textbook_id': _bookId, 'lesson_id': _lessonId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          GlassSnackBar(content: Text(userError(error))),
        );
      }
    }
  }

  void _syncCoordinator() => widget.coordinator.update(this, busy: _playbackLocked);
  void _hostChanged() { if (mounted) { setState(() {}); _syncCoordinator(); } }
  void _playChanged() {
    if (!mounted) return;
    setState(() {
      if (_batchPlaybackActive) {
        _batchMode = true;
        _repeat = _playback.repeat;
        _interval = _playback.intervalSteps;
        _batchStartId = _playback.playingId ?? _playback.queuedId ?? _batchStartId;
      }
    });
    final id = _owns ? _playback.playingId : null;
    if (_batchPlaybackActive && id != null && id != _lastPlaying) {
      _ensurePlayingItemVisible(id);
    }
    _lastPlaying = id;
    _syncCoordinator();
  }

  void _ensurePlayingItemVisible(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_batchPlaybackActive || _playback.playingId != id ||
          ModalRoute.of(context)?.isCurrent != true) return;
      final target = _anchors[id]?.currentContext;
      if (target == null) return;
      final scrollable = Scrollable.maybeOf(target);
      final targetBox = target.findRenderObject();
      final viewportBox = scrollable?.context.findRenderObject();
      if (scrollable == null || targetBox is! RenderBox || viewportBox is! RenderBox) return;
      final targetTop = targetBox.localToGlobal(Offset.zero).dy;
      final targetBottom = targetTop + targetBox.size.height;
      final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
      final viewportBottom = viewportTop + viewportBox.size.height;
      const margin = 12.0;
      final safeTop = viewportTop + margin;
      final safeBottom = viewportBottom - margin;
      if (safeBottom <= safeTop) return;
      final position = scrollable.position;
      double destination = position.pixels;
      if (targetBox.size.height >= safeBottom - safeTop || targetTop < safeTop) {
        destination += targetTop - safeTop;
      } else if (targetBottom > safeBottom) {
        destination += targetBottom - safeBottom;
      } else {
        return;
      }
      destination = destination.clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
      if ((destination - position.pixels).abs() < .5) return;
      unawaited(position.animateTo(destination,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic));
    });
  }
  void _videoChanged() {
    if (mounted) setState(() {});
    _scheduleVideoVisibility();
    if (mounted) _syncCoordinator();
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
      if (show != _showVideoBar) {
        setState(() => _showVideoBar = show);
        _syncCoordinator();
      }
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
    if (mounted) { setState(() {}); _syncCoordinator(); }
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
      _syncCoordinator();
      final playing = _batchPlaybackActive ? _playback.playingId : null;
      if (playing != null) _ensurePlayingItemVisible(playing);
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_content', operation: '读取课文页签',
        context: {'textbook_id': _bookId, 'lesson_id': _lessonId});
      if (mounted) {
        setState(() { _loading = false; _error = userError(error, fallback: '课文内容读取失败'); });
        _syncCoordinator();
      }
    }
  }

  String _itemId(RowData row) => 'content:${row['id']}';

  Widget _guardPlaybackTouches(Widget child) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) { if (_playbackLocked) _extendCooldown(); },
    onPointerUp: (_) { if (_playbackLocked) _extendCooldown(); },
    child: child,
  );

  void _extendCooldown() {
    if (!mounted) return;
    _cooldownTimer?.cancel();
    setState(() => _coolingDown = true);
    _syncCoordinator();
    _cooldownTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) { setState(() => _coolingDown = false); _syncCoordinator(); }
    });
  }

  Future<void> _runPlaybackAction(Future<void> Function() action,
      {bool startingBatch = false, bool stopping = false}) async {
    if (_playbackLocked) { _extendCooldown(); return; }
    setState(() { _busy = true; _startingBatch = startingBatch; _stopping = stopping; });
    _syncCoordinator();
    try {
      await _perform(action);
    } finally {
      if (mounted) {
        setState(() { _busy = false; _startingBatch = false; _stopping = false; });
        _syncCoordinator();
        _extendCooldown();
      }
    }
  }

  Future<void> _stopForTabChange() async {
    await _video.stop();
    if (_owns) await _playback.stop();
    if (mounted) { setState(() => _batchMode = false); _syncCoordinator(); }
  }

  Future<void> _changeBatchMode(bool enabled) => _runPlaybackAction(() async {
    final activeId = _playback.playingId ?? _playback.queuedId;
    final activeStart = enabled && _owns && _playback.active && activeId?.startsWith('content:') == true
      ? activeId : null;
    final savedStart = _batchStartId?.startsWith('content:') == true ? _batchStartId : null;
    if (_owns) await _playback.stop();
    if (mounted && !(_owns && _playback.active)) {
      setState(() {
        _batchMode = enabled;
        _batchStartId = enabled ? activeStart ?? savedStart : null;
        if (enabled) { _repeat = 1; _interval = 0; }
      });
      _syncCoordinator();
    }
  });

  Future<void> _endPlayback() => _runPlaybackAction(() async {
    final start = _owns && _playback.active
      ? _playback.playingId ?? _playback.queuedId ?? _batchStartId : _batchStartId;
    if (_owns && _playback.active) await _playback.stop();
    if (mounted) { setState(() => _batchStartId = start); _syncCoordinator(); }
  }, stopping: true);

  Future<void> _playRows(List<RowData> rows, bool all) async {
    if (_blocked || !all && _batchPlaybackActive) return;
    await _runPlaybackAction(() async {
      try {
        await _video.stop();
        final stopRevision = _playback.stopRevision;
        final clips = <RowData>[];
        for (final row in rows) {
          final type = textOf(row, 'media_type');
          if (type.isNotEmpty && type != 'text' && type != 'audio') continue;
          final file = type == 'audio' ? textOf(row, 'media_src') : textOf(row, 'phonetic');
          if (file.isEmpty && all) continue;
          if (file.isEmpty) throw StateError('本条暂无音频');
          final path = type == 'audio'
            ? await widget.host.resources.mediaPath(_bookId, file, 'audio')
            : await widget.host.resources.audioPath(_bookId, file);
          clips.add({'id': _itemId(row), 'path': path});
        }
        if (clips.isEmpty) throw StateError('当前没有可播放的课文音频');
        final wanted = all ? _batchStartId : null;
        final start = wanted == null ? -1 : clips.indexWhere((clip) => clip['id'] == wanted);
        if (!mounted || _playback.stopRevision != stopRevision || _playback.stopping || _blocked) return;
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
      }
    }, startingBatch: all);
  }

  Future<void> _playHotspot(RowData row, CourseImageHotspot hotspot) async {
    if (_playbackLocked || _blocked) return;
    setState(() => _busy = true);
    _syncCoordinator();
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
      if (mounted) { setState(() => _busy = false); _syncCoordinator(); }
    }
  }

  Future<void> _startVideo(RowData row) async {
    if (_playbackLocked || _blocked) return;
    await _video.play(id: textOf(row, 'id'), book: _bookId,
      resolvePath: () => widget.host.resources.mediaPath(_bookId, textOf(row, 'media_src'), 'video'),
      beforePlay: () async {
        final start = _owns ? _playback.playingId ?? _playback.queuedId : _batchStartId;
        if (_playback.active) await _playback.stop();
        if (mounted) { setState(() { _batchStartId = start; _batchMode = false; }); _syncCoordinator(); }
      });
  }

  Future<void> _complete() async {
    if (_completing || _completed.contains('content') || _rows.isEmpty) return;
    setState(() => _completing = true);
    _syncCoordinator();
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
      _syncCoordinator();
      await widget.host.reload();
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_content', operation: '标记课文完成');
    } finally {
      if (mounted) { setState(() => _completing = false); _syncCoordinator(); }
    }
  }

  Future<void> _cancelCompletion() async {
    if (_completing || !_completed.contains('content')) return;
    setState(() => _completing = true);
    _syncCoordinator();
    try {
      final confirmed = await showGlassDialog<bool>(context: context, builder: (context) => GlassAlertDialog(
        title: const Text('取消提示'),
        content: const Text('是否取消本课课文的已完成状态？\n取消后将恢复为“标记完成”。\n学习进度和课程状态会同步更新，历史学习记录保留。'),
        actions: [
          StudyButton.text(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          StudyButton.filled(onPressed: () => Navigator.pop(context, true), child: const Text('确认')),
        ],
      ));
      if (confirmed != true || !mounted) return;
      await widget.host.store.cancelCompletion(widget.book, widget.lesson, 'content');
      if (mounted) setState(() => _completed.remove('content'));
      await widget.host.reload();
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_content', operation: '取消课文完成状态');
    } finally {
      if (mounted) { setState(() => _completing = false); _syncCoordinator(); }
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
      child: StudyInkWell(onTap: onTap, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        child: DefaultTextStyle.merge(style: active
          ? TextStyle(fontWeight: FontWeight.w700,
              color: dark ? Colors.white : const Color(0xFF083B24))
          : const TextStyle(), child: child))),
    ));
  }

  int _roleSlots(String role) {
    final partLengths = <int>[];
    var offset = 0;
    for (final match in RegExp(r'!([^!\s()]+)\(([^)]*)\)').allMatches(role)) {
      for (final _ in role.substring(offset, match.start).runes) {
        partLengths.add(1);
      }
      partLengths.add(match.group(1)!.runes.length);
      offset = match.end;
    }
    for (final _ in role.substring(offset).runes) {
      partLengths.add(1);
    }
    final surfaceLength = partLengths.fold<int>(0, (sum, length) => sum + length);
    var consumed = 0;
    var canSplitAfterTwo = false;
    for (final length in partLengths) {
      consumed += length;
      if (consumed == 2) canSplitAfterTwo = true;
    }
    if (surfaceLength == 4 && canSplitAfterTwo) return 3;
    final roleLength = surfaceLength < 1 ? 1 : surfaceLength > 3 ? 3 : surfaceLength;
    return roleLength + 1;
  }

  Color get _translationColor => Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF9E9E9E)
    : const Color(0xFF616161);

  Widget _utterance(RowData row, double roleWidth) {
    final id = _itemId(row);
    final role = textOf(row, 'role');
    return StudyInkWell(key: _anchors.putIfAbsent(id, GlobalKey.new),
      onTap: _canPlayItem ? () => _playRows([row], false) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (roleWidth > 0) Padding(padding: const EdgeInsets.only(right: 8),
            child: SizedBox(width: roleWidth,
              child: role.isEmpty ? const SizedBox.shrink() : _RubyText(role,
                ruby: false, reserveRubyHeight: widget.host.ruby,
                fontSize: 16, color: Colors.orange,
                endAligned: true, trailingSuffix: '：', balanceFourCharacters: true))),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _RubyText(textOf(row, 'content'), ruby: widget.host.ruby,
              source: widget.host.source, active: _owns && _playback.playingId == id,
              fontSize: 16),
            if (textOf(row, 'definition').isNotEmpty) ...[
              const SizedBox(height: 7),
              keepSpace(widget.host.translation, Text(textOf(row, 'definition'),
                style: TextStyle(fontFamily: 'PingFang SC', locale: const Locale('zh', 'CN'),
                  fontSize: 15, height: 1.5, color: _translationColor))),
            ],
          ])),
        ]),
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
        final id = _itemId(row);
        widgets.add(Padding(key: _anchors.putIfAbsent(id, GlobalKey.new),
          padding: const EdgeInsets.symmetric(vertical: 20), child: StudyInkWell(
          onTap: _canPlayItem ? () => _playRows([row], false) : null,
          child: Column(children: [
            _RubyText(textOf(row, 'content'), ruby: widget.host.ruby, source: widget.host.source,
              centered: true, active: _owns && _playback.playingId == _itemId(row)),
            keepSpace(widget.host.translation, Text(textOf(row, 'definition'),
              style: TextStyle(fontFamily: 'PingFang SC', locale: const Locale('zh', 'CN'),
                color: _translationColor, fontSize: 15))),
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
      var roleSlots = 0;
      for (final item in group) {
        final role = textOf(item, 'role');
        if (role.isNotEmpty) {
          final slots = _roleSlots(role);
          if (slots > roleSlots) roleSlots = slots;
        }
      }
      final roleWidth = roleSlots == 0
        ? 0.0
        : MediaQuery.textScalerOf(context).scale(16) * roleSlots + 2;
      widgets.add(_card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var j = 0; j < group.length; j++) ...[
          if (j > 0) const SizedBox(height: 24),
          _utterance(group[j], roleWidth),
        ],
      ])));
    }
    return widgets;
  }

  Widget _bottom() {
    if (_batchMode) {
      final active = _owns && _playback.active;
      final showEnd = _startingBatch || active || _stopping;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: StudyButton.text(onPressed: showEnd
              ? _playbackLocked ? null : _endPlayback
              : _playbackLocked ? null : () => _playRows(_rows, true),
            child: Text(showEnd ? '结束' : '全部播放'))),
          const SizedBox(width: 12),
          Expanded(child: StudyButton.text(onPressed: _controlsDisabled ? null : () {
            setState(() => _repeat = _repeat % 5 + 1);
            _syncCoordinator();
            if (_owns) unawaited(_perform(() => _playback.configure(repeat: _repeat)));
          },
            child: Text('循环 $_repeat 次'))),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Visibility(visible: !showEnd, maintainState: true, maintainAnimation: true,
            maintainSize: true, child: StudyButton.text(
              onPressed: _playbackLocked || showEnd ? null : () => _changeBatchMode(false),
              child: const Text('返回')))),
          const SizedBox(width: 12),
          Expanded(child: StudyButton.text(onPressed: _controlsDisabled ? null : () {
            setState(() => _interval = (_interval + 1) % 7);
            _syncCoordinator();
            if (_owns) unawaited(_perform(() => _playback.configure(intervalSteps: _interval)));
          },
            child: Text('间隔 ${(_interval * .5).toStringAsFixed(1)} 秒'))),
        ]),
      ]);
    }
    final complete = _completed.contains('content');
    return Row(children: [
      Expanded(child: StudyButton.textIcon(icon: const Icon(Icons.playlist_play), label: const Text('全部播放'),
        onPressed: _controlsDisabled || _rows.isEmpty ? null : () => _changeBatchMode(true))),
      const SizedBox(width: 12),
      Expanded(child: GestureDetector(behavior: HitTestBehavior.opaque,
        onDoubleTap: complete && !_completing && !_controlsDisabled ? _cancelCompletion : null,
        child: StudyButton.textIcon(icon: Icon(complete ? Icons.check_circle : Icons.radio_button_unchecked),
          label: Text(complete ? '已完成' : '标记完成'),
          onPressed: complete || _controlsDisabled || _rows.isEmpty ? null : _complete))),
    ]);
  }

  Widget _bottomBar() => SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
    if (_showVideoBar && _video.active && !_video.fullscreen)
      CourseVideoBar(controller: _video, onLocate: _locateVideo),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: _guardPlaybackTouches(_bottom())),
  ]));

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: StudyCircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 16),
        StudyButton.filled(onPressed: _load, child: const Text('重新读取课文')),
      ])));
    return Column(children: [
      Expanded(child: _guardPlaybackTouches(_rows.isEmpty ? const Center(child: Text('本课暂无课文数据'))
        : NotificationListener<ScrollMetricsNotification>(onNotification: (_) { _scheduleVideoVisibility(); return false; },
            child: SingleChildScrollView(key: _mediaViewport, controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _contentRows()))))),
    ]);
  }
}

class _RubyText extends StatelessWidget {
  const _RubyText(this.text, {required this.ruby, this.source = true, this.centered = false,
    this.endAligned = false, this.active = false, this.fontSize = 19, this.color,
    this.trailingSuffix, this.balanceFourCharacters = false, this.reserveRubyHeight = false});
  final String text;
  final bool ruby, source, centered, active;
  final bool endAligned, balanceFourCharacters, reserveRubyHeight;
  final double fontSize;
  final Color? color;
  final String? trailingSuffix;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final parts = <({String surface, String reading})>[];
    void add(String surface, String reading) {
      parts.add((surface: surface, reading: reading));
    }
    Widget token(String surface, String reading) {
      final highlighted = active && surface.trim().isNotEmpty;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        if (reserveRubyHeight)
          SizedBox(height: MediaQuery.textScalerOf(context).scale(12) * 1.3)
        else
          keepSpace(ruby, Text(reading.isEmpty ? ' ' : reading,
            style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'),
              fontSize: 12, height: 1.3, color: Color(0xFF32AA43)))),
        keepSpace(source, Text(surface, style: TextStyle(fontFamily: 'Hiragino Sans',
          locale: const Locale('ja', 'JP'), fontSize: fontSize, height: 1.5,
          color: highlighted ? (dark ? const Color(0xFFFFB366) : const Color(0xFFB85C00)) : color))),
      ]);
    }
    var offset = 0;
    for (final match in RegExp(r'!([^!\s()]+)\(([^)]*)\)').allMatches(text)) {
      for (final rune in text.substring(offset, match.start).runes) { add(String.fromCharCode(rune), ''); }
      add(match.group(1)!, match.group(2)!);
      offset = match.end;
    }
    for (final rune in text.substring(offset).runes) { add(String.fromCharCode(rune), ''); }
    List<Widget> tokens(int start, int end, {required bool suffix}) => [
      for (var index = start; index < end; index++)
        if (index == end - 1 && suffix && trailingSuffix != null)
          Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            token(parts[index].surface, parts[index].reading), token(trailingSuffix!, ''),
          ])
        else
          token(parts[index].surface, parts[index].reading),
    ];
    final alignment = centered ? WrapAlignment.center
      : endAligned ? WrapAlignment.end : WrapAlignment.start;
    var surfaceLength = 0;
    var splitIndex = -1;
    for (var index = 0; index < parts.length; index++) {
      surfaceLength += parts[index].surface.runes.length;
      if (surfaceLength == 2) splitIndex = index + 1;
    }
    if (balanceFourCharacters && surfaceLength == 4 && splitIndex > 0 && splitIndex < parts.length) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(alignment: alignment, crossAxisAlignment: WrapCrossAlignment.end,
          children: tokens(0, splitIndex, suffix: false)),
        Wrap(alignment: alignment, crossAxisAlignment: WrapCrossAlignment.end,
          children: tokens(splitIndex, parts.length, suffix: true)),
      ]);
    }
    if (balanceFourCharacters && surfaceLength <= 3) {
      return Row(mainAxisAlignment: endAligned ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: tokens(0, parts.length, suffix: true));
    }
    return Wrap(alignment: alignment, crossAxisAlignment: WrapCrossAlignment.end,
      children: tokens(0, parts.length, suffix: true));
  }
}

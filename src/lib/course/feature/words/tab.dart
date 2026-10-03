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

/// Independent implementation of the course words tab.
class CourseWordsTab extends StatefulWidget {
  const CourseWordsTab({required this.host, required this.book, required this.lesson,
    required this.coordinator, super.key});
  final CourseTabHost host;
  final RowData book, lesson;
  final CourseTabCoordinator coordinator;

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
  bool _startingBatch = false, _stopping = false, _coolingDown = false;
  int _repeat = 1, _interval = 0;
  String? _error, _batchStartId, _lastPlaying;
  bool _resourceUpdating = false;
  final Set<String> _mediaOpening = {};
  Timer? _cooldownTimer;

  String get _bookId => textOf(widget.book, 'id');
  String get _lessonId => textOf(widget.lesson, 'id');
  String get _identity => '$_bookId:$_lessonId:words';
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
      _syncCoordinator();
      final playing = _batchPlaybackActive ? _playback.playingId : null;
      if (playing != null) _ensurePlayingItemVisible(playing);
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_words', operation: '读取单词页签',
        context: {'textbook_id': _bookId, 'lesson_id': _lessonId});
      if (mounted) {
        setState(() { _loading = false; _error = userError(error, fallback: '单词内容读取失败'); });
        _syncCoordinator();
      }
    }
  }

  String _itemId(RowData row) => 'word:${row['id']}';

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
    final activeStart = enabled && _owns && _playback.active && activeId?.startsWith('word:') == true
      ? activeId : null;
    final savedStart = _batchStartId?.startsWith('word:') == true ? _batchStartId : null;
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
          final source = textOf(row, 'phonetic').trim();
          if (source.isEmpty && all) continue;
          if (source.isEmpty) throw StateError('本条暂无音频');
          clips.add({'id': _itemId(row), 'path': await widget.host.resources.audioPath(_bookId, source)});
        }
        if (clips.isEmpty) throw StateError('当前没有可播放的单词音频');
        final wanted = all ? _batchStartId : null;
        final start = wanted == null ? -1 : clips.indexWhere((clip) => clip['id'] == wanted);
        if (!mounted || _playback.stopRevision != stopRevision || _playback.stopping || _blocked) return;
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
      }
    }, startingBatch: all);
  }

  Future<void> _playHotspot(RowData row, CourseImageHotspot hotspot) async {
    if (_playbackLocked || _blocked || _batchPlaybackActive) return;
    setState(() => _busy = true);
    _syncCoordinator();
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
    } finally {
      if (mounted) { setState(() => _busy = false); _syncCoordinator(); }
    }
  }

  Future<void> _startVideo(RowData row, String path) async {
    if (_playbackLocked || _blocked || _batchPlaybackActive) return;
    await _video.play(id: textOf(row, 'id'), book: _bookId,
      resolvePath: () async => path,
      beforePlay: () async { if (_playback.active) await _playback.stop(); });
  }

  Future<void> _openMedia(RowData row) async {
    final id = textOf(row, 'id');
    final type = textOf(row, 'media_type').trim();
    final source = textOf(row, 'media_src').trim();
    if (_playbackLocked || _blocked || _batchPlaybackActive || type.isEmpty || source.isEmpty || !_mediaOpening.add(id)) return;
    try {
      if (type == 'image') {
        final media = await loadCourseWordImageMedia(
          resolvePath: () => widget.host.resources.mediaPath(_bookId, source, 'image'));
        if (!mounted) return;
        await openCourseWordImagePage(context, media: media, label: '单词插图');
        return;
      }
      if (type == 'interactive_image') {
        final media = await loadCourseWordImageMedia(
          resolvePath: () => widget.host.resources.mediaPath(_bookId, source, 'interactive_image'),
          mediaConfig: textOf(row, 'media_config'));
        if (!mounted) return;
        final hotspotPrefix = 'word-hotspot:$id:';
        await openCourseWordImagePage(context, media: media, label: '互动单词插图',
          onActivate: (hotspot) => _playHotspot(row, hotspot));
        if (_owns && _playback.active && _playback.playingId?.startsWith(hotspotPrefix) == true) {
          await _playback.stop();
        }
        return;
      }
      if (type == 'video') {
        final path = await widget.host.resources.mediaPath(_bookId, source, 'video');
        final poster = await _video.poster(() async => path);
        if (!mounted || poster == null) return;
        await openCourseWordVideoPage(context,
          controller: _video,
          id: id,
          posterPath: poster.$1,
          posterAspectRatio: poster.$2,
          onPlay: () => _startVideo(row, path));
      }
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_words', operation: '打开单词多媒体',
        context: {'textbook_id': _bookId, 'lesson_id': _lessonId, 'word_id': id, 'media_type': type});
    } finally {
      _mediaOpening.remove(id);
    }
  }

  Future<void> _complete() async {
    if (_completing || _completed.contains('word') || _rows.isEmpty) return;
    setState(() => _completing = true);
    _syncCoordinator();
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
      _syncCoordinator();
      await widget.host.reload();
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_words', operation: '标记单词完成');
    } finally {
      if (mounted) setState(() => _completing = false);
      if (mounted) _syncCoordinator();
    }
  }

  Future<void> _cancelCompletion() async {
    if (_completing || !_completed.contains('word')) return;
    setState(() => _completing = true);
    _syncCoordinator();
    try {
      final confirmed = await showGlassDialog<bool>(context: context, builder: (context) => GlassAlertDialog(
        title: const Text('取消提示'),
        content: const Text('是否取消本课单词的已完成状态？\n取消后将恢复为“标记完成”。\n学习进度和课程状态会同步更新，历史学习记录保留。'),
        actions: [
          StudyButton.text(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          StudyButton.filled(onPressed: () => Navigator.pop(context, true), child: const Text('确认')),
        ],
      ));
      if (confirmed != true || !mounted) return;
      await widget.host.store.cancelCompletion(widget.book, widget.lesson, 'word');
      if (mounted) setState(() => _completed.remove('word'));
      await widget.host.reload();
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_words', operation: '取消单词完成状态');
    } finally {
      if (mounted) { setState(() => _completing = false); _syncCoordinator(); }
    }
  }

  Widget _card({Key? key, required Widget child, bool active = false}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(key: key, padding: const EdgeInsets.only(bottom: 12), child: StudyPanel(
      color: active ? (dark ? const Color(0xFF154D38) : const Color(0xFFC5F2D6))
        : (dark ? const Color(0xFF252525) : Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: active ? (dark ? const Color(0xFF71E5A4) : const Color(0xFF16864B))
          : Colors.transparent, width: 2)),
      clipBehavior: Clip.antiAlias,
      child: DefaultTextStyle.merge(style: active
        ? TextStyle(fontWeight: FontWeight.w700,
            color: dark ? Colors.white : const Color(0xFF083B24))
        : const TextStyle(), child: child),
    ));
  }

  Widget _row(RowData row) {
    final id = _itemId(row);
    final translationColor = Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF9E9E9E)
      : const Color(0xFF616161);
    final mediaType = textOf(row, 'media_type').trim();
    final mediaSource = textOf(row, 'media_src').trim();
    final hasMediaIndicator = mediaType.isNotEmpty && mediaSource.isNotEmpty;
    final reading = textOf(row, 'kana').replaceFirst(RegExp(r'@.*$'), '');
    final surface = plainJapanese(textOf(row, 'word'));
    return _card(key: _anchors.putIfAbsent(id, GlobalKey.new), active: _owns && _playback.playingId == id,
      child: Stack(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Align(alignment: Alignment.centerLeft, child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  keepSpace(widget.host.ruby, Text(reading, style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'), fontSize: 12, height: 1.3, color: Color(0xFF32AA43)))),
                  keepSpace(widget.host.source, Text(surface.isNotEmpty ? surface : textOf(row, 'kanji').isNotEmpty ? textOf(row, 'kanji') : reading,
                    style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'), fontSize: 16, height: 1.5))),
                ],
              ))),
              if (hasMediaIndicator || textOf(row, 'pos').isNotEmpty) ...[
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .3),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    SizedBox(height: 15.6, child: hasMediaIndicator
                      ? const Align(alignment: Alignment.centerRight,
                          child: Icon(Icons.perm_media_outlined, size: 14, color: Color(0xFF32AA43)))
                      : null),
                    if (textOf(row, 'pos').isNotEmpty)
                      Text('[${row['pos']}]', textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 16, height: 1.5, color: Color(0xFF32AA43))),
                  ]),
                ),
              ],
            ]),
            const SizedBox(height: 5),
            keepSpace(widget.host.translation, Align(alignment: Alignment.centerRight,
              child: Text(textOf(row, 'definition'), textAlign: TextAlign.right,
                style: TextStyle(fontFamily: 'PingFang SC', locale: const Locale('zh', 'CN'),
                  fontSize: 15, color: translationColor)))),
            if (textOf(row, 'phonetic').trim().isEmpty)
              const Text('暂无音频', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ])),
        Positioned.fill(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: Semantics(
            button: true,
            enabled: _canPlayItem,
            label: '播放当前单词读音',
            child: InkWell(onTap: _canPlayItem ? () => _playRows([row], false) : null),
          )),
          Expanded(child: Semantics(
            button: hasMediaIndicator,
            enabled: hasMediaIndicator && !_playbackLocked && !_blocked && !_batchPlaybackActive,
            label: hasMediaIndicator ? '打开单词多媒体' : null,
            child: InkWell(onTap: hasMediaIndicator && !_playbackLocked && !_blocked && !_batchPlaybackActive
              ? () => _openMedia(row) : null),
          )),
        ])),
      ]),
    );
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
    final complete = _completed.contains('word');
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

  Widget _bottomBar() => SafeArea(top: false, child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: _guardPlaybackTouches(_bottom())));

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: StudyCircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 16),
        StudyButton.filled(onPressed: _load, child: const Text('重新读取单词')),
      ])));
    return Column(children: [
      Expanded(child: _guardPlaybackTouches(_rows.isEmpty
        ? const Center(child: Text('本课暂无单词数据'))
        : SingleChildScrollView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Padding(padding: EdgeInsets.fromLTRB(8, 8, 8, 12), child: Text('单词表', style: TextStyle(fontSize: 15, color: Colors.grey))),
              for (final row in _rows) _row(row),
            ])))),
    ]);
  }
}

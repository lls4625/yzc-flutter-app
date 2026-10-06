import '../../lesson_presentation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../data.dart';
import '../../ios_lesson_playback.dart';
import '../../playback_scaffold.dart';
import '../../route_observer.dart';
import '../../system_errors.dart';
import '../../ui.dart';
import '../../user_error.dart';
import 'host.dart';
import 'words/tab.dart';
import 'content/tab.dart';
import 'grammar/tab.dart';
import 'practice/tab.dart';
import 'tab_coordinator.dart';

typedef OpenCoursePractice = Future<void> Function(BuildContext context, String id);

/// Keeps the existing four-tab course page while delegating every tab's data,
/// state, media, and error handling to an independent module.
class CourseLessonPage extends StatefulWidget {
  const CourseLessonPage(this.host, this.book, this.lesson, {
    required this.openPractice,
    super.key,
  });

  final CourseTabHost host;
  final RowData book, lesson;
  final OpenCoursePractice openPractice;

  @override
  State<CourseLessonPage> createState() => _CourseLessonPageState();
}

class _CourseLessonPageState extends State<CourseLessonPage> with WidgetsBindingObserver, RouteAware {
  final _playback = IosLessonPlayback.instance;
  final _tabs = List.generate(4, (_) => CourseTabCoordinator());
  int _tab = 0;
  double _dragDistance = 0;
  int? _dragOrigin;
  PageRoute<dynamic>? _route;
  Timer? _cooldownTimer;
  bool _switching = false, _coolingDown = false, _checkingLesson = true;
  String? _lessonError, _lastPlaybackError;

  String get _bookId => textOf(widget.book, 'id');
  String get _lessonId => textOf(widget.lesson, 'id');
  String get _playbackPrefix => '$_bookId:$_lessonId:';
  bool get _ownsPlayback => _playback.lesson?.startsWith(_playbackPrefix) == true;
  bool get _batchPlayback => _ownsPlayback && _playback.active && _playback.batch;
  bool get _interactionLocked => _switching || _coolingDown || _playback.stopping || _tabs[_tab].busy;
  int? get _playbackTab {
    final lesson = _playback.lesson;
    if (lesson == '${_playbackPrefix}words') return 0;
    if (lesson == '${_playbackPrefix}content') return 1;
    if (lesson == '${_playbackPrefix}grammar') return 2;
    if (lesson == '${_playbackPrefix}open-practice') return 3;
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.host.addListener(_hostChanged);
    widget.host.resources.addListener(_resourceChanged);
    _playback.addListener(_playbackChanged);
    for (final tab in _tabs) { tab.addListener(_tabStateChanged); }
    if (_playback.active && _playbackTab != null) _tab = _playbackTab!;
    unawaited(_validateLesson(showLoading: true));
    unawaited(_perform(_playback.refresh));
    unawaited(_remember());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && _route != route) {
      courseRouteObserver.unsubscribe(this);
      _route = route;
      courseRouteObserver.subscribe(this, route);
    }
  }

  Future<void> _remember() async {
    final host = widget.host;
    final book = widget.book;
    final lesson = widget.lesson;
    try {
      await host.store.remember(book, lesson);
      await host.reload();
    } catch (_) {
      // Position persistence must never prevent any of the four tabs loading.
    }
  }

  @override
  void didUpdateWidget(CourseLessonPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final courseChanged = oldWidget.host != widget.host ||
      oldWidget.book['id'] != widget.book['id'] ||
      oldWidget.lesson['id'] != widget.lesson['id'];
    if (oldWidget.host != widget.host) {
      oldWidget.host.removeListener(_hostChanged);
      oldWidget.host.resources.removeListener(_resourceChanged);
      widget.host.addListener(_hostChanged);
      widget.host.resources.addListener(_resourceChanged);
    }
    if (courseChanged) {
      _cooldownTimer?.cancel();
      _switching = false;
      _coolingDown = false;
      _dragDistance = 0;
      _dragOrigin = null;
      _lessonError = null;
      _lastPlaybackError = null;
      _tab = _playback.active && _playbackTab != null ? _playbackTab! : 0;
      unawaited(_validateLesson(showLoading: true));
      unawaited(_remember());
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    courseRouteObserver.unsubscribe(this);
    widget.host.removeListener(_hostChanged);
    widget.host.resources.removeListener(_resourceChanged);
    _playback.removeListener(_playbackChanged);
    for (final tab in _tabs) {
      tab.removeListener(_tabStateChanged);
      tab.dispose();
    }
    super.dispose();
  }

  void _hostChanged() {
    if (mounted) setState(() {});
  }

  void _resourceChanged() {
    if (widget.host.resources.activeBook == null) unawaited(_validateLesson());
    if (mounted) setState(() {});
  }

  void _tabStateChanged() {
    if (mounted) setState(() {});
  }

  void _playbackChanged() {
    if (!mounted) return;
    if (_batchPlayback && _tab != (_playback.words ? 0 : 1)) {
      setState(() => _tab = _playback.words ? 0 : 1);
    } else {
      setState(() {});
    }
    final error = _ownsPlayback ? _playback.error : null;
    if (error != null && error != _lastPlaybackError) {
      _lastPlaybackError = error;
      SystemErrors.record(StateError(error), StackTrace.current,
        module: 'course_page', operation: '课程音频状态异常',
        context: {'textbook_id': _bookId, 'lesson_id': _lessonId,
          'playing_id': _playback.playingId, 'stack_origin': '原生状态回调，不含原生堆栈'});
      ScaffoldMessenger.of(context).showSnackBar(
        GlassSnackBar(content: Text(userError(StateError(error), fallback: '音频播放失败'))));
    }
  }

  Future<void> _validateLesson({bool showLoading = false}) async {
    final host = widget.host;
    final bookId = _bookId;
    final lessonId = _lessonId;
    if (mounted && showLoading) setState(() { _checkingLesson = true; _lessonError = null; });
    try {
      final rows = await host.store.db.query('yzc_lessons',
        where: 'id=? AND textbook_id=?', whereArgs: [lessonId, bookId]);
      if (!mounted || widget.host != host || _bookId != bookId || _lessonId != lessonId) return;
      setState(() {
        _checkingLesson = false;
        _lessonError = rows.isEmpty ? '原课程已不在当前内容中，学习历史已保留' : null;
      });
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_page', operation: '校验课程',
        context: {'textbook_id': bookId, 'lesson_id': lessonId});
      if (mounted && widget.host == host && _bookId == bookId && _lessonId == lessonId) setState(() {
        _checkingLesson = false;
        _lessonError = userError(error, fallback: '课程读取失败');
      });
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_page', operation: '课程页操作');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          GlassSnackBar(content: Text(userError(error))),
        );
      }
    }
  }

  void _extendCooldown() {
    if (!mounted) return;
    _cooldownTimer?.cancel();
    setState(() => _coolingDown = true);
    _cooldownTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _coolingDown = false);
    });
  }

  Future<void> _changeTab(int? value) async {
    if (value == null || value < 0 || value > 3 || value == _tab || _batchPlayback) return;
    if (_interactionLocked) { _extendCooldown(); return; }
    setState(() => _switching = true);
    try {
      await _tabs[_tab].stopForTabChange();
      if (mounted) setState(() => _tab = value);
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'course_page', operation: '切换课程页签');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        GlassSnackBar(content: Text(userError(error, fallback: '页签切换失败'))));
    } finally {
      if (mounted) {
        setState(() => _switching = false);
        _extendCooldown();
      }
    }
  }

  void _startDrag(DragStartDetails details) {
    _dragDistance = 0;
    _dragOrigin = _batchPlayback || _interactionLocked ? null : _tab;
  }

  void _cancelDrag() {
    _dragDistance = 0;
    _dragOrigin = null;
  }

  void _endDrag(DragEndDetails details) {
    final origin = _dragOrigin;
    final distance = _dragDistance;
    final velocity = details.primaryVelocity ?? 0;
    _cancelDrag();
    if (origin == null || origin != _tab || _batchPlayback || _interactionLocked) return;
    final threshold = (MediaQuery.sizeOf(context).width * .18).clamp(24.0, 80.0);
    final fast = distance.abs() >= 24 && velocity.abs() >= 500 && distance * velocity > 0;
    if (distance.abs() < threshold && !fast) return;
    unawaited(_changeTab(origin + (distance < 0 ? 1 : -1)));
  }

  @override
  void didPushNext() {
    final tab = _tabs[_tab];
    if (!tab.videoFullscreen) unawaited(_perform(tab.stopVideo));
  }

  @override
  void didPop() {
    unawaited(_perform(_tabs[_tab].stopVideo));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_perform(_playback.refresh));
  }

  Future<void> _speed() async {
    var value = (widget.host.speed * 10).round();
    final selected = await showGlassDialog<int>(context: context,
      builder: (context) => StatefulBuilder(builder: (context, update) => GlassAlertDialog(
        title: const Text('播放速度'),
        content: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8, children: [
            StudyIconButton(tooltip: '减少 0.1', onPressed: value <= 5 ? null : () => update(() => value--),
              icon: const Icon(Icons.remove)),
            SizedBox(width: MediaQuery.textScalerOf(context).scale(24) * 3,
              child: Text((value / 10).toStringAsFixed(1), textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24))),
            StudyIconButton(tooltip: '增加 0.1', onPressed: value >= 30 ? null : () => update(() => value++),
              icon: const Icon(Icons.add)),
          ]),
        actions: [
          StudyButton.text(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          StudyButton.filled(onPressed: () => Navigator.pop(context, value), child: const Text('确定')),
        ],
      )),
    );
    if (selected == null || !mounted) return;
    await _perform(() async {
      await widget.host.setting('playback_speed', selected);
      if (_ownsPlayback && IosLessonPlayback.instance.active) {
        await IosLessonPlayback.instance.configure(speed: selected / 10);
      }
    });
  }

  Future<void> _displayOptions() async {
    await showGlassBottomSheet<void>(context: context, showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(builder: (context, update) {
        Widget option(String label, String key, bool enabled, Color color) => StudySwitchListTile(
          secondary: Container(width: 12, height: 12,
            decoration: BoxDecoration(color: enabled ? color : Colors.grey, shape: BoxShape.circle)),
          title: Text(label), value: enabled,
          onChanged: (value) async {
            await _perform(() => widget.host.setting(key, value ? 1 : 0));
            if (sheetContext.mounted) update(() {});
          },
        );
        return SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const StudyListTile(title: Text('显示内容', style: TextStyle(fontWeight: FontWeight.w600))),
          option('原文', 'show_source', widget.host.source, const Color(0xFFB55343)),
          option('注音', 'show_ruby', widget.host.ruby, const Color(0xFF32AA43)),
          option('翻译', 'show_definition', widget.host.translation, const Color(0xFF397CC6)),
          const SizedBox(height: 8),
        ]));
      }),
    );
  }

  List<Widget> _tabPages() => [
    CourseWordsTab(host: widget.host, book: widget.book, lesson: widget.lesson,
      coordinator: _tabs[0],
      key: ValueKey('${identityHashCode(widget.host)}:$_bookId:$_lessonId:words')),
    CourseContentTab(host: widget.host, book: widget.book, lesson: widget.lesson,
      coordinator: _tabs[1],
      key: ValueKey('${identityHashCode(widget.host)}:$_bookId:$_lessonId:content')),
    CourseGrammarTab(host: widget.host, book: widget.book, lesson: widget.lesson,
      coordinator: _tabs[2],
      key: ValueKey('${identityHashCode(widget.host)}:$_bookId:$_lessonId:grammar')),
    CoursePracticeTab(host: widget.host, book: widget.book, lesson: widget.lesson,
      coordinator: _tabs[3], openPractice: widget.openPractice,
      key: ValueKey('${identityHashCode(widget.host)}:$_bookId:$_lessonId:practice')),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bookId = textOf(widget.book, 'id');
    final blocked = widget.host.resources.unavailable.contains(bookId);
    final bottom = _tab == 3 || _checkingLesson || _lessonError != null
      ? null : _tabs[_tab].buildBottom(context);
    return PlaybackScaffold(
      controlledLesson: _batchPlayback ? _playback.lesson : null,
      backgroundColor: dark ? const Color(0xFF171817) : const Color(0xFFF5F5F5),
      appBar: StudyAppBar(centerTitle: true, title: Text(lessonLabel(widget.lesson)),
        backgroundColor: dark ? const Color(0xFF222322) : Colors.white,
        actions: [
          StudySpeedButton(onPressed: _speed, speed: widget.host.speed),
          StudyIconButton.transparent(tooltip: '显示内容', onPressed: _displayOptions,
            showPressHighlight: false, padding: const EdgeInsets.all(2),
            icon: StudyDisplayRingIcon(source: widget.host.source, ruby: widget.host.ruby,
              translation: widget.host.translation)),
        ],
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: SizedBox(width: 380, child: StudySegments<int>(selected: _tab,
            values: const {0: '单词', 1: '课文', 2: '文法', 3: '练习'},
            onChanged: (value) => unawaited(_changeTab(value))))),
        if (blocked) const Padding(padding: EdgeInsets.all(12),
          child: Text('内容正在同步或需要重新下载，暂时无法播放。')),
        Expanded(child: _checkingLesson ? const Center(child: StudyCircularProgressIndicator())
          : _lessonError != null ? Center(child: Padding(padding: const EdgeInsets.all(24),
              child: Text(_lessonError!, textAlign: TextAlign.center)))
          : GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _startDrag,
          onHorizontalDragUpdate: (details) => _dragDistance += details.primaryDelta ?? 0,
          onHorizontalDragEnd: _endDrag,
          onHorizontalDragCancel: _cancelDrag,
          child: IndexedStack(index: _tab, children: _tabPages()),
        )),
      ]),
      bottomNavigationBar: bottom,
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import '../../data.dart';
import '../../ios_lesson_playback.dart';
import '../../playback_scaffold.dart';
import '../../ui.dart';
import 'host.dart';
import 'words/tab.dart';
import 'content/tab.dart';
import 'grammar/tab.dart';
import 'practice/tab.dart';

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

class _CourseLessonPageState extends State<CourseLessonPage> {
  int _tab = 0;
  double _dragDistance = 0;
  int? _dragOrigin;

  @override
  void initState() {
    super.initState();
    widget.host.addListener(_hostChanged);
    unawaited(_remember());
  }

  Future<void> _remember() async {
    try {
      await widget.host.store.remember(widget.book, widget.lesson);
      await widget.host.reload();
    } catch (_) {
      // Position persistence must never prevent any of the four tabs loading.
    }
  }

  @override
  void didUpdateWidget(CourseLessonPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host) {
      oldWidget.host.removeListener(_hostChanged);
      widget.host.addListener(_hostChanged);
    }
  }

  @override
  void dispose() {
    widget.host.removeListener(_hostChanged);
    super.dispose();
  }

  void _hostChanged() {
    if (mounted) setState(() {});
  }

  void _changeTab(int? value) {
    if (value == null || value < 0 || value > 3 || value == _tab) return;
    setState(() => _tab = value);
  }

  void _startDrag(DragStartDetails details) {
    _dragDistance = 0;
    _dragOrigin = _tab;
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
    if (origin == null || origin != _tab) return;
    final threshold = (MediaQuery.sizeOf(context).width * .18).clamp(24.0, 80.0);
    final fast = distance.abs() >= 24 && velocity.abs() >= 500 && distance * velocity > 0;
    if (distance.abs() < threshold && !fast) return;
    _changeTab(origin + (distance < 0 ? 1 : -1));
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
    await perform(context, () async {
      await widget.host.setting('playback_speed', selected);
      if (IosLessonPlayback.instance.active) {
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
            await perform(context, () => widget.host.setting(key, value ? 1 : 0));
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

  Widget _currentTab() => switch (_tab) {
    0 => CourseWordsTab(host: widget.host, book: widget.book, lesson: widget.lesson),
    1 => CourseContentTab(host: widget.host, book: widget.book, lesson: widget.lesson),
    2 => CourseGrammarTab(host: widget.host, book: widget.book, lesson: widget.lesson),
    _ => CoursePracticeTab(host: widget.host, book: widget.book, lesson: widget.lesson,
      openPractice: widget.openPractice),
  };

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bookId = textOf(widget.book, 'id');
    final blocked = widget.host.resources.unavailable.contains(bookId);
    return PlaybackScaffold(
      backgroundColor: dark ? const Color(0xFF171817) : const Color(0xFFF5F5F5),
      appBar: StudyAppBar(centerTitle: true, title: Text('第${widget.lesson['num'] ?? ''}课'),
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
            values: const {0: '单词', 1: '课文', 2: '文法', 3: '练习'}, onChanged: _changeTab))),
        if (blocked) const Padding(padding: EdgeInsets.all(12),
          child: Text('内容正在同步或需要重新下载，暂时无法播放。')),
        Expanded(child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _startDrag,
          onHorizontalDragUpdate: (details) => _dragDistance += details.primaryDelta ?? 0,
          onHorizontalDragEnd: _endDrag,
          onHorizontalDragCancel: _cancelDrag,
          child: KeyedSubtree(key: ValueKey<int>(_tab), child: _currentTab()),
        )),
      ]),
    );
  }
}

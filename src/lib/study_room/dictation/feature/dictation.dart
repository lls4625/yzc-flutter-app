import '../../demo_localization/ui.dart';
import '../../../l10n/l10n.dart';
import '../../../content_language.dart';
import '../../../content_typography.dart';
import '../../../lesson_presentation.dart';
import '../../../system_errors.dart';

import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import '../../../foundation/native_audio_transport.dart';

import 'package:flutter/material.dart';

import '../../../glass_ui.dart';
import '../../host_contracts.dart';
import '../../access/access.dart';
import 'controller.dart';
import 'scaffold.dart';

part 'practice.dart';

class DictationFeature extends StatefulWidget {
  const DictationFeature(this.host, this.access, {super.key});
  final StudyRoomHost host;
  final StudyRoomAccess access;

  @override
  State<DictationFeature> createState() => _DictationFeatureState();
}

class _DictationFeatureState extends State<DictationFeature> {
  late final controller = DictationController(widget.host, widget.access);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DictationSelectionPage(controller);
}

class _DictationCard {
  const _DictationCard(this.lesson, this.words);
  final RowData lesson;
  final bool words;
  String get key => '${lesson['id']}:${words ? 'word' : 'content'}';
  String course(BuildContext context) =>
      lessonLabel(lesson, locale: Localizations.localeOf(context));
  int get count => lesson[words ? 'word_count' : 'content_count'] as int? ?? 0;
  String label(BuildContext context) => words
      ? context.tr('单词', '單詞', 'Words', '単語')
      : context.tr('课文', '課文', 'Texts', '本文');
  IconData get icon =>
      words ? Icons.headphones_rounded : Icons.menu_book_rounded;
}

class DictationSelectionPage extends StatefulWidget {
  const DictationSelectionPage(this.controller, {super.key});
  final DictationController controller;
  @override
  State<DictationSelectionPage> createState() => _DictationSelectionPageState();
}

class _DictationSelectionPageState extends State<DictationSelectionPage> {
  RowData? book;
  String? selectionVersion;
  List<_DictationCard> cards = [], selected = [];
  bool loading = true;
  String? error;
  final _queueScroll = ScrollController();
  final _queueViewport = GlobalKey();
  Timer? _dragScrollTimer;
  Offset? _dragPosition;
  bool confirming = false, choosingBook = false, savingRule = false;

  @override
  void dispose() {
    _dragScrollTimer?.cancel();
    _queueScroll.dispose();
    super.dispose();
  }

  void _selectType(bool words) => setState(() {
    final selectedKeys = selected.map((item) => item.key).toSet();
    for (final card in cards.where((item) => item.words == words)) {
      if (selectedKeys.add(card.key)) selected.add(card);
    }
  });

  void _selectAll() => setState(() => selected = List.of(cards));

  void _cancelAll() => setState(() => selected.clear());

  void _finishDrag() {
    _dragScrollTimer?.cancel();
    _dragScrollTimer = null;
    _dragPosition = null;
  }

  void _startDrag() {
    _finishDrag();
    _dragScrollTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!mounted || _dragPosition == null || !_queueScroll.hasClients) return;
      final box = _queueViewport.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final point = box.globalToLocal(_dragPosition!);
      if (point.dx < 0 || point.dx > box.size.width) return;
      final delta = point.dy < 40
          ? -12.0
          : point.dy > box.size.height - 40
          ? 12.0
          : 0.0;
      if (delta == 0) return;
      final next = (_queueScroll.offset + delta)
          .clamp(0.0, _queueScroll.position.maxScrollExtent)
          .toDouble();
      if (next != _queueScroll.offset) _queueScroll.jumpTo(next);
    });
  }

  void _drop(String source, String target) {
    _finishDrag();
    final from = selected.indexWhere((item) => item.key == source);
    final to = selected.indexWhere((item) => item.key == target);
    if (from < 0 || to < 0 || from == to) return;
    setState(() => selected.insert(to, selected.removeAt(from)));
  }

  Widget _selectedTile(
    _DictationCard item,
    int index, {
    bool highlighted = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return StudyPanel(
      color: highlighted ? scheme.primaryContainer : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: highlighted ? scheme.primary : scheme.outlineVariant,
          width: highlighted ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 5, 2, 5),
        child: Row(
          children: [
            Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 12,
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      item.course(context),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(item.icon, size: 14, color: scheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          '${item.label(context)} ${item.count}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.drag_indicator_rounded, size: 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            StudyIconButton(
              tooltip: context.tr(
                '取消选择${item.course(context)}${item.label(context)}',
                '取消選擇${item.course(context)}${item.label(context)}',
                'Deselect ${item.course(context)} ${item.label(context)}',
                '${item.course(context)} ${item.label(context)} の選択を解除',
              ),
              onPressed: () => _toggle(item),
              icon: const Icon(Icons.close_rounded, size: 18),
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectedGrid() => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - 24 - 8) / 2;
      return SizedBox(
        key: _queueViewport,
        child: GridView.builder(
          controller: _queueScroll,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 68,
            crossAxisSpacing: 8,
            mainAxisSpacing: 6,
          ),
          itemCount: selected.length,
          itemBuilder: (context, index) {
            final item = selected[index];
            return DragTarget<String>(
              key: ValueKey(item.key),
              onWillAcceptWithDetails: (details) => details.data != item.key,
              onAcceptWithDetails: (details) => _drop(details.data, item.key),
              builder: (context, candidates, rejected) =>
                  LongPressDraggable<String>(
                    data: item.key,
                    maxSimultaneousDrags: 1,
                    onDragStarted: _startDrag,
                    onDragUpdate: (details) =>
                        _dragPosition = details.globalPosition,
                    onDragEnd: (_) => _finishDrag(),
                    onDraggableCanceled: (_, __) => _finishDrag(),
                    feedback: SizedBox(
                      width: width,
                      height: 68,
                      child: _selectedTile(item, index, highlighted: true),
                    ),
                    childWhenDragging: Opacity(
                      opacity: .25,
                      child: _selectedTile(item, index),
                    ),
                    child: _selectedTile(
                      item,
                      index,
                      highlighted: candidates.isNotEmpty,
                    ),
                  ),
            );
          },
        ),
      );
    },
  );

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (!widget.controller.unlocked || widget.controller.purchaseSaving) {
        throw StateError('自习室尚未解锁，请在“我的”页面购买或恢复购买');
      }
      await widget.controller.load();
      final id = widget.controller.selectedBook;
      final books = await widget.controller.catalog.textbooks();
      final matches = books.where((row) => textOf(row, 'id') == id);
      final current = matches.isEmpty ? null : matches.first;
      final version = current == null
          ? null
          : await widget.controller.catalog.version(id);
      final lessons = current == null
          ? <RowData>[]
          : await widget.controller.catalog.lessons(id);
      if (current != null &&
          version != await widget.controller.catalog.version(id)) {
        throw StateError('内容已更新，请重新读取课程');
      }
      if (!mounted) return;
      setState(() {
        book = current;
        selectionVersion = version;
        cards = [
          for (final lesson in lessons) ...[
            if ((lesson['word_count'] as int? ?? 0) > 0)
              _DictationCard(lesson, true),
            if ((lesson['content_count'] as int? ?? 0) > 0)
              _DictationCard(lesson, false),
          ],
        ];
        selected = [];
        loading = false;
      });
    } catch (e, caughtStack) {
      SystemErrors.record(
        e,
        caughtStack,
        module: 'dictation',
        operation: '读取听写课程',
        context: {'source': 'study_room/dictation/feature/dictation.dart'},
      );
      if (mounted)
        setState(() {
          loading = false;
          error = featureError(e, fallback: '课程读取失败');
        });
    }
  }

  Future<void> _chooseBook() async {
    if (loading || confirming || choosingBook) return;
    setState(() => choosingBook = true);
    try {
      await perform(context, () async {
        final books = await widget.controller.catalog.textbooks();
        if (!mounted) return;
        final chosen = await showGlassDialog<String>(
          context: context,
          builder: (dialogContext) => GlassAlertDialog(
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    dialogContext.tr('选择内容', '選擇內容', 'Choose content', '教材を選択'),
                  ),
                ),
                const SizedBox(width: 12),
                StudyIconButton(
                  tooltip: dialogContext.tr('关闭', '關閉', 'Close', '閉じる'),
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (books.isEmpty)
                  Text(
                    dialogContext.tr(
                      '暂无可用内容，请先在内容库完成下载。',
                      '暫無可用內容，請先在內容庫完成下載。',
                      'No content available. Download a package from the library first.',
                      '利用できる教材がありません。先にライブラリからダウンロードしてください。',
                    ),
                  ),
                for (final row in books) ...[
                  if (row != books.first) const SizedBox(height: 12),
                  Semantics(
                    selected: textOf(row, 'id') == textOf(book ?? {}, 'id'),
                    child: textOf(row, 'id') == textOf(book ?? {}, 'id')
                        ? StudyButton.filled(
                            onPressed: () =>
                                Navigator.pop(dialogContext, textOf(row, 'id')),
                            child: Text(
                              '${row['textbook']} ${row['volume'] ?? ''}',
                            ),
                          )
                        : StudyButton.text(
                            onPressed: () =>
                                Navigator.pop(dialogContext, textOf(row, 'id')),
                            child: Text(
                              '${row['textbook']} ${row['volume'] ?? ''}',
                            ),
                          ),
                  ),
                ],
              ],
            ),
            actions: const [],
          ),
        );
        if (chosen == null || !mounted || chosen == textOf(book ?? {}, 'id'))
          return;
        await widget.controller.setting('book', chosen);
        if (mounted) await _load();
      });
    } finally {
      if (mounted) setState(() => choosingBook = false);
    }
  }

  void _toggle(_DictationCard card) {
    if (loading || choosingBook || confirming || savingRule) return;
    setState(() {
      final index = selected.indexWhere((item) => item.key == card.key);
      if (index < 0) {
        selected.add(card);
      } else {
        selected.removeAt(index);
      }
    });
  }

  Future<void> _confirm() async {
    if (loading || choosingBook || confirming || savingRule) return;
    if (!await widget.controller.access.ensure(context)) return;
    if (!mounted) return;
    if (book == null || selected.isEmpty || confirming) return;
    final queue = List<_DictationCard>.unmodifiable(selected);
    setState(() => confirming = true);
    try {
      final version = await widget.controller.catalog.version(
        textOf(book!, 'id'),
      );
      if (!mounted) return;
      if (version != selectionVersion) {
        await _load();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            GlassSnackBar(
              content: Text(
                context.tr(
                  '内容已更新，数量已刷新，请重新选择',
                  '內容已更新，數量已重新整理，請重新選擇',
                  'Content updated. Counts refreshed; please select again.',
                  '教材が更新され、件数を再取得しました。選び直してください。',
                ),
              ),
            ),
          );
        return;
      }
      await Navigator.of(context).push(
        PageRouteBuilder<void>(
          pageBuilder: (_, __, ___) =>
              _DictationPage(widget.controller, book!, queue, version),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    } catch (error, stack) {
      SystemErrors.record(
        error,
        stack,
        module: 'dictation',
        operation: '校验课程数量',
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          GlassSnackBar(
            content: Builder(
              builder: (context) => Text(
                studyUi(context, featureError(error, fallback: '课程校验失败，请重新读取')),
              ),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => confirming = false);
    }
  }

  Future<void> _saveRule(String key, Object value) async {
    if (savingRule || confirming) return;
    setState(() => savingRule = true);
    try {
      await perform(context, () => widget.controller.setting(key, value));
    } finally {
      if (mounted) setState(() => savingRule = false);
    }
  }

  Widget _stepper(
    String label,
    String key,
    int value,
    int min,
    int max,
    String unit,
  ) {
    final disabled = savingRule || confirming;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StudyIconButton(
              tooltip: context.tr(
                '减少$label',
                '減少$label',
                'Decrease $label',
                '$label を減らす',
              ),
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              padding: EdgeInsets.zero,
              onPressed: disabled || value <= min
                  ? null
                  : () => _saveRule(key, value - 1),
              icon: const Icon(Icons.remove_rounded, size: 20),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('$value$unit', textAlign: TextAlign.center),
              ),
            ),
            StudyIconButton(
              tooltip: context.tr(
                '增加$label',
                '增加$label',
                'Increase $label',
                '$label を増やす',
              ),
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              padding: EdgeInsets.zero,
              onPressed: disabled || value >= max
                  ? null
                  : () => _saveRule(key, value + 1),
              icon: const Icon(Icons.add_rounded, size: 20),
            ),
          ],
        ),
      ],
    );
  }

  Widget _rules() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      children: [
        Row(
          children: [
            Text(
              context.tr('停顿方式', '停頓方式', 'Pause mode', '停止方法'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AbsorbPointer(
                absorbing: savingRule || confirming,
                child: StudySegments<bool>(
                  values: {
                    false: context.tr('整体停顿', '整體停頓', 'After repeats', '繰り返し後'),
                    true: context.tr('每句停顿', '每句停頓', 'After each play', '再生ごと'),
                  },
                  selected: widget.controller.pauseEach,
                  onChanged: (value) => _saveRule('pause_each', value),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              context.tr('听写顺序', '聽寫順序', 'Dictation order', '書き取り順'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AbsorbPointer(
                absorbing: savingRule || confirming,
                child: StudySegments<bool>(
                  values: {
                    false: context.tr('顺序', '順序', 'In order', '順番'),
                    true: context.tr('随机', '隨機', 'Random', 'ランダム'),
                  },
                  selected: widget.controller.randomOrder,
                  onChanged: (value) => _saveRule('random_order', value),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _stepper(
                context.tr('重复次数', '重複次數', 'Repeats', '繰り返し'),
                'repeats',
                widget.controller.repeats,
                1,
                5,
                context.tr('次', '次', ' times', '回'),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _stepper(
                context.tr('间隔时间', '間隔時間', 'Interval', '間隔'),
                'interval',
                widget.controller.interval,
                1,
                10,
                context.tr('秒', '秒', ' s', '秒'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedKeys = selected.map((card) => card.key).toSet();
    return DictationScaffold(
      appBar: StudyAppBar(
        centerTitle: true,
        title: Text(context.tr('课程排序', '課程排序', 'Arrange lessons', 'レッスンの順番')),
        actions: [
          StudyIconButton(
            tooltip: context.tr('选择内容', '選擇內容', 'Choose content', '教材を選択'),
            onPressed: loading || confirming || choosingBook
                ? null
                : _chooseBook,
            icon: const Icon(Icons.library_books_outlined),
          ),
          StudyIconButton(
            tooltip: context.tr('开始听写', '開始聽寫', 'Start dictation', '書き取りを開始'),
            onPressed:
                loading ||
                    choosingBook ||
                    selected.isEmpty ||
                    confirming ||
                    savingRule
                ? null
                : _confirm,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                selected.isEmpty
                    ? Icons.play_circle_outline_rounded
                    : Icons.play_circle_fill_rounded,
                key: ValueKey(selected.isNotEmpty),
                size: 30,
                color: selected.isEmpty || loading || confirming
                    ? scheme.onSurface.withValues(alpha: .38)
                    : scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: loading
          ? const Center(child: StudyCircularProgressIndicator())
          : error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.ui(error!)),
                  StudyButton.text(
                    onPressed: _load,
                    child: Text(context.tr('重新读取', '重新讀取', 'Reload', '再読み込み')),
                  ),
                ],
              ),
            )
          : book == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.tr(
                      '请先选择本次听写的内容',
                      '請先選擇本次聽寫的內容',
                      'Choose content for this dictation session first.',
                      '今回の書き取りで使う教材を選んでください。',
                    ),
                  ),
                  StudyButton.filled(
                    onPressed: () async {
                      await _chooseBook();
                    },
                    child: Text(
                      context.tr('选择内容', '選擇內容', 'Choose content', '教材を選択'),
                    ),
                  ),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, bounds) => SingleChildScrollView(
                child: SizedBox(
                  height: max(
                    bounds.maxHeight,
                    460.0 +
                        (MediaQuery.textScalerOf(context).scale(14) - 14) * 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Text(
                          '${textOf(book!, 'textbook')} ${textOf(book!, 'volume')}'
                              .trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      _rules(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          context.tr(
                            '播放顺序 · 已选 ${selected.length} 项　长按拖动排序',
                            '播放順序 · 已選 ${selected.length} 項　長按拖曳排序',
                            'Queue · ${selected.length} selected · Hold and drag to reorder',
                            '再生順 · ${selected.length} 件選択 · 長押しして並べ替え',
                          ),
                        ),
                      ),
                      Expanded(
                        child: selected.isEmpty
                            ? Center(
                                child: Text(
                                  context.tr(
                                    '从下方选择课程，组成你的听写顺序',
                                    '從下方選擇課程，組成你的聽寫順序',
                                    'Choose lessons below to build your dictation queue.',
                                    '下からレッスンを選び、書き取りの順番を作ってください。',
                                  ),
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : _selectedGrid(),
                      ),
                      const StudyDivider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Text(
                          context.tr(
                            '本内容课程 · 点击勾选 / 再次点击取消',
                            '本內容課程 · 點選勾選 / 再次點選取消',
                            'Lessons · Tap to select; tap again to remove',
                            'レッスン · タップで選択、もう一度タップで解除',
                          ),
                        ),
                      ),
                      Expanded(
                        child: cards.isEmpty
                            ? Center(
                                child: Text(
                                  context.tr(
                                    '本内容暂无课程',
                                    '本內容暫無課程',
                                    'No lessons in this package',
                                    'この教材にはレッスンがありません',
                                  ),
                                ),
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final columns = constraints.maxWidth >= 320
                                      ? 6
                                      : 4;
                                  return GridView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      0,
                                      8,
                                      8,
                                    ),
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: columns,
                                          mainAxisExtent: 78,
                                          crossAxisSpacing: 4,
                                          mainAxisSpacing: 4,
                                        ),
                                    itemCount: cards.length,
                                    itemBuilder: (context, index) {
                                      final item = cards[index];
                                      final checked = selectedKeys.contains(
                                        item.key,
                                      );
                                      return Semantics(
                                        selected: checked,
                                        button: true,
                                        label:
                                            '${item.course(context)}${item.label(context)} ${item.count}',
                                        child: StudyPanel(
                                          color: checked
                                              ? scheme.primaryContainer
                                              : scheme.surfaceContainerLow,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            side: BorderSide(
                                              color: checked
                                                  ? scheme.primary
                                                  : scheme.outlineVariant,
                                              width: checked ? 2 : 1,
                                            ),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: StudyInkWell(
                                            onTap: () => _toggle(item),
                                            child: Padding(
                                              padding: const EdgeInsets.all(4),
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text(
                                                      item.course(context),
                                                      style: const TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    '${item.count}',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          item.icon,
                                                          size: 13,
                                                          color: scheme.primary,
                                                        ),
                                                        const SizedBox(
                                                          width: 2,
                                                        ),
                                                        Text(
                                                          item.label(context),
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 10,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          width: 2,
                                                        ),
                                                        Icon(
                                                          checked
                                                              ? Icons
                                                                    .check_circle_rounded
                                                              : Icons
                                                                    .radio_button_unchecked,
                                                          size: 12,
                                                          color: checked
                                                              ? scheme.primary
                                                              : scheme
                                                                    .onSurfaceVariant,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StudyButton.outlined(
                      onPressed: loading || cards.isEmpty ? null : _selectAll,
                      child: Text(context.tr('全部', '全部', 'All', 'すべて')),
                    ),
                    const SizedBox(height: 4),
                    StudyButton.outlined(
                      onPressed: selected.isEmpty ? null : _cancelAll,
                      child: Text(context.tr('取消', '取消', 'Clear', '解除')),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StudyButton.outlined(
                      onPressed: loading || cards.isEmpty
                          ? null
                          : () => _selectType(true),
                      child: Text(
                        context.tr('全部单词', '全部單詞', 'All words', 'すべての単語'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    StudyButton.outlined(
                      onPressed: loading || cards.isEmpty
                          ? null
                          : () => _selectType(false),
                      child: Text(
                        context.tr('全部课文', '全部課文', 'All texts', 'すべての本文'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

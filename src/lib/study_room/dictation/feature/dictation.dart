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
  String get course => lessonLabel(lesson);
  int get count => lesson[words ? 'word_count' : 'content_count'] as int? ?? 0;
  String get label => words ? '单词' : '课文';
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
                      item.course,
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
                        Text('${item.label} ${item.count}', style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 4),
                        const Icon(Icons.drag_indicator_rounded, size: 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            StudyIconButton(
              tooltip: '取消选择${item.course}${item.label}',
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
      final version = current == null ? null : await widget.controller.catalog.version(id);
      final lessons = current == null
          ? <RowData>[]
          : await widget.controller.catalog.lessons(id);
      if (current != null && version != await widget.controller.catalog.version(id)) {
        throw StateError('内容已更新，请重新读取课程');
      }
      if (!mounted) return;
      setState(() {
        book = current;
        selectionVersion = version;
        cards = [
          for (final lesson in lessons) ...[
            if ((lesson['word_count'] as int? ?? 0) > 0) _DictationCard(lesson, true),
            if ((lesson['content_count'] as int? ?? 0) > 0) _DictationCard(lesson, false),
          ],
        ];
        selected = [];
        loading = false;
      });
    } catch (e, caughtStack) {
      SystemErrors.record(e, caughtStack, module: 'dictation', operation: '读取听写课程', context: {'source': 'study_room/dictation/feature/dictation.dart'});
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
                const Expanded(child: Text('选择内容')),
                const SizedBox(width: 12),
                StudyIconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (books.isEmpty) const Text('暂无可用内容，请先在内容库完成下载。'),
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
      final version = await widget.controller.catalog.version(textOf(book!, 'id'));
      if (!mounted) return;
      if (version != selectionVersion) {
        await _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          GlassSnackBar(content: const Text('内容已更新，数量已刷新，请重新选择')),
        );
        return;
      }
      await Navigator.of(context).push(
        PageRouteBuilder<void>(
          pageBuilder: (_, __, ___) => _DictationPage(widget.controller, book!, queue, version),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'dictation', operation: '校验课程数量');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        GlassSnackBar(content: Text(featureError(error, fallback: '课程校验失败，请重新读取'))),
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

  Widget _stepper(String label, String key, int value, int min, int max, String unit) {
    final disabled = savingRule || confirming;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        StudyIconButton(
          tooltip: '减少$label',
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: EdgeInsets.zero,
          onPressed: disabled || value <= min ? null : () => _saveRule(key, value - 1),
          icon: const Icon(Icons.remove_rounded, size: 20),
        ),
        Flexible(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('$value$unit', textAlign: TextAlign.center),
        )),
        StudyIconButton(
          tooltip: '增加$label',
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: EdgeInsets.zero,
          onPressed: disabled || value >= max ? null : () => _saveRule(key, value + 1),
          icon: const Icon(Icons.add_rounded, size: 20),
        ),
      ]),
    ]);
  }

  Widget _rules() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(children: [
      Row(children: [
        Text('停顿方式', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(width: 12),
        Expanded(child: AbsorbPointer(
          absorbing: savingRule || confirming,
          child: StudySegments<bool>(
            values: const {false: '整体停顿', true: '每句停顿'},
            selected: widget.controller.pauseEach,
            onChanged: (value) => _saveRule('pause_each', value),
          ),
        )),
      ]),
      const SizedBox(height: 4),
      Row(children: [
        Text('听写顺序', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(width: 12),
        Expanded(child: AbsorbPointer(
          absorbing: savingRule || confirming,
          child: StudySegments<bool>(
            values: const {false: '顺序', true: '随机'},
            selected: widget.controller.randomOrder,
            onChanged: (value) => _saveRule('random_order', value),
          ),
        )),
      ]),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _stepper('重复次数', 'repeats', widget.controller.repeats, 1, 5, '次')),
        const SizedBox(width: 20),
        Expanded(child: _stepper('间隔时间', 'interval', widget.controller.interval, 1, 10, '秒')),
      ]),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedKeys = selected.map((card) => card.key).toSet();
    return DictationScaffold(
      appBar: StudyAppBar(
        centerTitle: true,
        title: const Text('课程排序'),
        actions: [
          StudyIconButton(
            tooltip: '选择内容',
            onPressed: loading || confirming || choosingBook
                ? null
                : _chooseBook,
            icon: const Icon(Icons.library_books_outlined),
          ),
          StudyIconButton(
            tooltip: '开始听写',
            onPressed: loading || choosingBook || selected.isEmpty || confirming || savingRule
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
                  Text(error!),
                  StudyButton.text(onPressed: _load, child: const Text('重新读取')),
                ],
              ),
            )
          : book == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('请先选择本次听写的内容'),
                  StudyButton.filled(
                    onPressed: () async {
                      await _chooseBook();
                    },
                    child: const Text('选择内容'),
                  ),
                ],
              ),
            )
          : LayoutBuilder(builder: (context, bounds) => SingleChildScrollView(
              child: SizedBox(
                height: max(bounds.maxHeight, 460.0 +
                    (MediaQuery.textScalerOf(context).scale(14) - 14) * 8),
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
                  child: Text('播放顺序 · 已选 ${selected.length} 项　长按拖动排序'),
                ),
                Expanded(
                  child: selected.isEmpty
                      ? Center(
                          child: Text(
                            '从下方选择课程，组成你的听写顺序',
                            style: TextStyle(color: scheme.onSurfaceVariant),
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
                  child: const Text('本内容课程 · 点击勾选 / 再次点击取消'),
                ),
                Expanded(
                  child: cards.isEmpty
                      ? const Center(child: Text('本内容暂无课程'))
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth >= 320 ? 6 : 4;
                            return GridView.builder(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
                                final checked = selectedKeys.contains(item.key);
                                return Semantics(
                                  selected: checked,
                                  button: true,
                                  label: '${item.course}${item.label} ${item.count}',
                                  child: StudyPanel(
                                    color: checked
                                        ? scheme.primaryContainer
                                        : scheme.surfaceContainerLow,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
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
                                                item.course,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text('${item.count}', style: const TextStyle(fontSize: 11)),
                                            const SizedBox(height: 3),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    item.icon,
                                                    size: 13,
                                                    color: scheme.primary,
                                                  ),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    item.label,
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 2),
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
            )),
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
                      child: const Text('全部'),
                    ),
                    const SizedBox(height: 4),
                    StudyButton.outlined(
                      onPressed: selected.isEmpty ? null : _cancelAll,
                      child: const Text('取消'),
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
                      child: const Text('全部单词'),
                    ),
                    const SizedBox(height: 4),
                    StudyButton.outlined(
                      onPressed: loading || cards.isEmpty
                          ? null
                          : () => _selectType(false),
                      child: const Text('全部课文'),
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

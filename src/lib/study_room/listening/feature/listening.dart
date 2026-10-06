import '../../../lesson_presentation.dart';
import '../../../system_errors.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../../glass_ui.dart';
import '../../host_contracts.dart';
import '../../access/access.dart';
import 'controller.dart';
import '../../../foundation/native_audio_transport.dart';
import 'scaffold.dart';
import 'text.dart';

class ListeningFeature extends StatefulWidget {
  const ListeningFeature(
    this.host,
    this.access, {
    super.key,
  });
  final StudyRoomHost host;
  final StudyRoomAccess access;
  @override
  State<ListeningFeature> createState() => _ListeningFeatureState();
}

class _ListeningFeatureState extends State<ListeningFeature> {
  late final controller = ListeningController(widget.host, widget.access);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ListeningSelectionPage(controller);
}

class _ListeningCard {
  const _ListeningCard(this.lesson, this.words);
  final RowData lesson;
  final bool words;
  String get key => '${lesson['id']}:${words ? 'word' : 'content'}';
  String get course => lessonLabel(lesson);
  int get count => lesson[words ? 'word_count' : 'content_count'] as int? ?? 0;
  String get label => words ? '单词' : '课文';
  IconData get icon =>
      words ? Icons.headphones_rounded : Icons.menu_book_rounded;
}

class ListeningSelectionPage extends StatefulWidget {
  const ListeningSelectionPage(this.controller, {super.key});
  final ListeningController controller;
  @override
  State<ListeningSelectionPage> createState() => _ListeningSelectionPageState();
}

class _ListeningSelectionPageState extends State<ListeningSelectionPage> {
  RowData? book;
  String? selectionVersion;
  List<_ListeningCard> cards = [], selected = [];
  bool loading = true;
  String? error;
  final _queueScroll = ScrollController();
  final _queueViewport = GlobalKey();
  Timer? _dragScrollTimer;
  Offset? _dragPosition;
  bool confirming = false, choosingBook = false;

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
    _ListeningCard item,
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
            if ((lesson['word_count'] as int? ?? 0) > 0) _ListeningCard(lesson, true),
            if ((lesson['content_count'] as int? ?? 0) > 0) _ListeningCard(lesson, false),
          ],
        ];
        selected = [];
        loading = false;
      });
    } catch (e, caughtStack) {
      SystemErrors.record(e, caughtStack, module: 'listening', operation: '读取课程与准备音频', context: {'source': 'study_room/listening/feature/listening.dart'});
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

  void _toggle(_ListeningCard card) {
    if (loading || choosingBook || confirming) return;
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
    if (loading || choosingBook || confirming) return;
    if (!await widget.controller.access.ensure(context)) return;
    if (!mounted) return;
    if (book == null || selected.isEmpty || confirming) return;
    final queue = List<_ListeningCard>.unmodifiable(selected);
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
          pageBuilder: (_, __, ___) => _ListeningPlayerPage(
            widget.controller,
            book!,
            queue,
            version,
          ),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'listening', operation: '校验课程数量');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        GlassSnackBar(content: Text(featureError(error, fallback: '课程校验失败，请重新读取'))),
      );
    } finally {
      if (mounted) setState(() => confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedKeys = selected.map((card) => card.key).toSet();
    return ListeningScaffold(
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
            tooltip: '确认并开始循环播放',
            onPressed: loading || choosingBook || selected.isEmpty || confirming
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
                  const Text('请先选择本次收听的内容'),
                  StudyButton.filled(
                    onPressed: () async {
                      await _chooseBook();
                    },
                    child: const Text('选择内容'),
                  ),
                ],
              ),
            )
          : Column(
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
                            '从下方选择课程，组成你的收听顺序',
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
                  child: Text(
                    '本内容课程 · 点击勾选 / 再次点击取消',
                  ),
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

class _ListeningSection {
  const _ListeningSection(this.card, this.rows);
  final _ListeningCard card;
  final List<RowData> rows;
}

class _ListeningListItem {
  const _ListeningListItem(this.section, this.row);
  final int section;
  final RowData? row;
}

class _ListeningPlayerPage extends StatefulWidget {
  const _ListeningPlayerPage(
    this.controller,
    this.book,
    this.queue,
    this.selectionVersion,
  );
  final String selectionVersion;
  final ListeningController controller;
  final RowData book;
  final List<_ListeningCard> queue;
  @override
  State<_ListeningPlayerPage> createState() => _ListeningPlayerPageState();
}

class _ListeningPlayerPageState extends State<_ListeningPlayerPage>
    with WidgetsBindingObserver {
  double get speed => widget.controller.speed;
  bool get showRuby => widget.controller.ruby;
  bool get showSource => widget.controller.source;
  bool get showTranslation => widget.controller.translation;
  bool get resourceBlocked => widget.controller.host.isBookUnavailable(bookId);
  final playback = NativeAudioTransport.instance;
  final anchors = <String, GlobalKey>{};
  final sectionByClip = <String, int>{};
  final clipIndexById = <String, int>{};
  final listIndexById = <String, int>{};
  List<_ListeningListItem> listItems = [];
  int resumeIndex = 0, listOrigin = 0, listEpoch = 0;
  List<_ListeningSection> sections = [];
  List<RowData> clips = [];
  List<String> silentCards = [];
  late final String identity;
  bool loading = true, busy = false;
  bool coolingDown = false;
  Timer? cooldownTimer;
  int repeat = 1, intervalSeconds = 0;
  bool get playbackLocked => busy || coolingDown;
  int currentSection = 0, prepared = 0;
  String? error, lastPlaying;
  String? preparedVersion;
  String get bookId => textOf(widget.book, 'id');
  bool get owns => playback.lesson == identity;

  @override
  void initState() {
    super.initState();
    identity = '$bookId:listening:${DateTime.now().microsecondsSinceEpoch}';
    WidgetsBinding.instance.addObserver(this);
    playback.addListener(_changed);
    widget.controller.addListener(_settingsChanged);
    widget.controller.host.changes.addListener(_settingsChanged);
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    if (busy) return;
    setState(() {
      loading = true;
      busy = true;
      error = null;
      prepared = 0;
    });
    final stopRevision = playback.stopRevision;
    try {
      if (!widget.controller.unlocked || widget.controller.purchaseSaving) {
        throw StateError('自习室尚未解锁，请在“我的”页面购买或恢复购买');
      }
      final contentVersion = await widget.controller.catalog.version(bookId);
      if (contentVersion != widget.selectionVersion) {
        throw StateError('内容已更新，请返回课程选择页重新选择');
      }
      final nextSections = <_ListeningSection>[];
      final nextClips = <RowData>[];
      final nextIndex = <String, int>{};
      final nextSilentCards = <String>[];
      final pathCache = <String, String>{};
      for (final card in widget.queue) {
        final rows = await widget.controller.catalog.content(
                card.words ? 'yzc_words' : 'yzc_content',
                bookId,
                textOf(card.lesson, 'id'),
              );
        if (!mounted) return;
        final sectionIndex = nextSections.length;
        final clipStart = nextClips.length;
        nextSections.add(_ListeningSection(card, rows));
        for (final row in rows) {
          final file = listeningAudioSource(row);
          if (file.isEmpty) continue;
          final path =
              pathCache[file] ??
              await widget.controller.catalog.audioPath(bookId, file);
          if (!mounted) return;
          pathCache[file] = path;
          final id = '${card.key}:${row['id']}';
          nextIndex[id] = sectionIndex;
          nextClips.add({'id': id, 'path': path});
        }
        if (nextClips.length == clipStart)
          nextSilentCards.add('${card.course}${card.label}');
        if (!mounted) return;
        setState(() => prepared++);
      }
      if (nextClips.isEmpty) throw StateError('所选课程暂无可播放音频');
      if (resourceBlocked) throw StateError('内容正在同步或需要修复');
      if (contentVersion != await widget.controller.catalog.version(bookId)) {
        throw StateError('内容已更新，请重新准备播放');
      }
      if (!mounted) return;
      setState(() {
        sections = nextSections;
        clips = nextClips;
        silentCards = nextSilentCards;
        preparedVersion = contentVersion;
        sectionByClip
          ..clear()
          ..addAll(nextIndex);
        anchors.clear();
        currentSection = 0;
        loading = false;
        clipIndexById.clear();
        listIndexById.clear();
        listItems = [];
        for (var i = 0; i < clips.length; i++) {
          clipIndexById[textOf(clips[i], 'id')] = i;
        }
        for (var i = 0; i < sections.length; i++) {
          listItems.add(_ListeningListItem(i, null));
          for (final row in sections[i].rows) {
            listIndexById['${sections[i].card.key}:${row['id']}'] =
                listItems.length;
            listItems.add(_ListeningListItem(i, row));
          }
        }
        resumeIndex = 0;
        listOrigin = 0;
        listEpoch++;
        lastPlaying = null;
      });
      if (playback.stopRevision == stopRevision && !playback.stopping)
        await _start();
      _extendCooldown();
    } catch (e, caughtStack) {
      SystemErrors.record(e, caughtStack, module: 'listening', operation: '读取课程与准备音频', context: {'source': 'study_room/listening/feature/listening.dart'});
      if (mounted)
        setState(() {
          loading = false;
          error = featureError(e, fallback: '磨耳朵音频准备失败');
        });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _start({int startIndex = 0, bool single = false}) async {
    if (!mounted || clips.isEmpty || playback.stopping) return;
    final stopRevision = playback.stopRevision;
    if (!await widget.controller.access.ensure(context)) return;
    if (!mounted) return;
    if (preparedVersion != await widget.controller.catalog.version(bookId)) {
      if (mounted) setState(() => error = '内容已更新，请重新准备播放');
      return;
    }
    if (!mounted ||
        playback.stopping ||
        playback.stopRevision != stopRevision ||
        !widget.controller.access.available)
      return;
    final section = sectionByClip[textOf(clips[startIndex], 'id')]!;
    await playback.start({
      'lesson': identity,
      'title': '${textOf(widget.book, 'textbook')} ${textOf(widget.book, 'volume')} · 磨耳朵',
      'albumTitle': '磨耳朵 · 全内容循环',
      'words': sections[section].card.words,
      'batch': !single,
      'speed': speed,
      'repeat': single ? 1 : repeat,
      'intervalSteps': single ? 0 : intervalSeconds * 2,
      'clips': single ? [clips[startIndex]] : clips,
      'startIndex': single ? 0 : startIndex,
    });
  }

  void _settingsChanged() {
    if (mounted) setState(() {});
  }

  String? _lastReportedPlaybackError;
  void _changed() {
    if (!mounted) return;
    final nativeError = owns ? playback.error : null;
    if (nativeError != null && nativeError != _lastReportedPlaybackError) {
      SystemErrors.record(StateError(nativeError), StackTrace.current, module: 'listening', operation: '磨耳朵音频状态异常', hint: '音频播放失败', context: {'textbook_id': widget.book['id'], 'playing_id': playback.playingId, 'stack_origin': '原生状态回调，不含原生堆栈'});
    }
    _lastReportedPlaybackError = nativeError;
    final id = owns ? playback.playingId : null;
    final next = sectionByClip[id];
    setState(() {
      if (next != null) currentSection = next;
      final index = clipIndexById[id];
      if (index != null) resumeIndex = index;
    });
    if (id != null && id != lastPlaying) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !owns || ModalRoute.of(context)?.isCurrent != true)
          return;
        final target = anchors[id]?.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            alignment: .4,
            duration: const Duration(milliseconds: 220),
          );
        } else {
          final index = listIndexById[id];
          if (index != null)
            setState(() {
              listOrigin = index;
              listEpoch++;
            });
        }
      });
    }
    if (id != null) lastPlaying = id;
  }

  Future<void> _playFrom(int index, {bool single = false}) async {
    if (loading || clips.isEmpty || resourceBlocked) return;
    await _runPlaybackAction(() => _start(startIndex: index, single: single));
  }

  Future<void> _stopQueue() async {
    if (!owns || !playback.active || !playback.batch) return;
    await _runPlaybackAction(playback.stop);
  }

  void _extendCooldown() {
    if (!mounted) return;
    cooldownTimer?.cancel();
    setState(() => coolingDown = true);
    cooldownTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => coolingDown = false);
    });
  }

  Widget _guardTouches(Widget child) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) {
      if (playbackLocked) _extendCooldown();
    },
    onPointerUp: (_) {
      if (playbackLocked) _extendCooldown();
    },
    child: child,
  );

  Future<void> _runPlaybackAction(Future<void> Function() action) async {
    if (!mounted) return;
    if (playbackLocked) {
      _extendCooldown();
      return;
    }
    setState(() => busy = true);
    try {
      await perform(context, action);
    } finally {
      if (mounted) {
        setState(() => busy = false);
        _extendCooldown();
      }
    }
  }

  Future<void> _setRepeat(int value) async {
    if (owns && playback.active && playback.batch)
      await playback.configure(repeat: value);
    if (mounted) setState(() => repeat = value);
  }

  Future<void> _changeRepeat() =>
      _runPlaybackAction(() => _setRepeat(repeat % 5 + 1));

  Future<void> _setInterval(int value) async {
    if (owns && playback.active && playback.batch)
      await playback.configure(intervalSteps: value * 2);
    if (mounted) setState(() => intervalSeconds = value);
  }

  Future<void> _changeInterval() =>
      _runPlaybackAction(() => _setInterval((intervalSeconds + 1) % 6));

  Future<void> _setSpeed(int value) async {
    await widget.controller.setting('playback_speed', value);
    if (owns && playback.active) await playback.configure(speed: value / 10);
  }

  Future<void> _speed() async {
    var value = (speed * 10).round();
    final chosen = await showGlassDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => GlassAlertDialog(
          title: const Text('播放速度'),
          content: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              StudyIconButton(
                tooltip: '减少 0.1',
                onPressed: value <= 5 ? null : () => update(() => value--),
                icon: const Icon(Icons.remove),
              ),
              Text('${(value / 10).toStringAsFixed(1)}'),
              StudyIconButton(
                tooltip: '增加 0.1',
                onPressed: value >= 30 ? null : () => update(() => value++),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          actions: [
            StudyButton.text(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            StudyButton.filled(
              onPressed: () => Navigator.pop(context, value),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    await perform(context, () => _setSpeed(chosen));
  }

  Future<void> _displayOptions() async {
    await showGlassBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) {
          Widget option(String label, String key, bool enabled, Color color) =>
              StudySwitchListTile(
                secondary: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: enabled ? color : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(label),
                value: enabled,
                onChanged: (value) async {
                  await perform(
                    context,
                    () => widget.controller.setting(key, value ? 1 : 0),
                  );
                  if (sheetContext.mounted) update(() {});
                },
              );
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const StudyListTile(
                  title: Text(
                    '显示内容',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                option(
                  '原文',
                  'show_source',
                  showSource,
                  const Color(0xFFB55343),
                ),
                option('注音', 'show_ruby', showRuby, const Color(0xFF32AA43)),
                option(
                  '翻译',
                  'show_definition',
                  showTranslation,
                  const Color(0xFF397CC6),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed)
      unawaited(perform(context, playback.refresh));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cooldownTimer?.cancel();
    playback.removeListener(_changed);
    widget.controller.removeListener(_settingsChanged);
    widget.controller.host.changes.removeListener(_settingsChanged);
    super.dispose();
  }

  Widget _listItem(int index) {
    final item = listItems[index];
    final section = sections[item.section];
    return IndexedSemantics(
      index: index,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: item.row == null
            ? Semantics(
                header: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                  child: Row(
                    children: [
                      Icon(section.card.icon, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${section.card.course} · ${section.card.label}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : _row(section, item.row!),
      ),
    );
  }

  // Two lazy slivers meet at a movable origin. An unmounted playback target
  // can be reached directly without measuring thousands of variable-height rows.
  Widget _mixedList() {
    const center = ValueKey('listening-forward');
    return CustomScrollView(
      key: ValueKey(listEpoch),
      primary: false,
      center: center,
      anchor: listOrigin == 0 ? 0 : .4,
      scrollCacheExtent: const ScrollCacheExtent.pixels(400),
      semanticChildCount: listItems.length,
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _listItem(listOrigin - index - 1),
            childCount: listOrigin,
            addAutomaticKeepAlives: false,
            addSemanticIndexes: false,
          ),
        ),
        SliverList(
          key: center,
          delegate: SliverChildBuilderDelegate(
            (context, index) => _listItem(listOrigin + index),
            childCount: listItems.length - listOrigin,
            addAutomaticKeepAlives: false,
            addSemanticIndexes: false,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 160)),
      ],
    );
  }

  Widget _row(_ListeningSection section, RowData row) {
    final id = '${section.card.key}:${row['id']}';
    final active = owns && playback.playingId == id;
    final scheme = Theme.of(context).colorScheme;
    final reading = textOf(row, 'kana').replaceFirst(RegExp(r'@.*$'), '');
    final surface = plainJapanese(textOf(row, 'word'));
    final clipIndex = clipIndexById[id];
    return StudyCard(
      key: anchors.putIfAbsent(id, GlobalKey.new),
      color: active ? scheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: StudyInkWell(
        onTap: playbackLocked || clipIndex == null || resourceBlocked
            ? null
            : () => _playFrom(clipIndex, single: true),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (section.card.words) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            keepSpace(
                              showRuby,
                              Text(
                                reading,
                                style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'),
                                  fontSize: 12,
                                  height: 1.3,
                                  color: Color(0xFF32AA43),
                                ),
                              ),
                            ),
                            keepSpace(
                              showSource,
                              Text(
                                surface.isNotEmpty
                                    ? surface
                                    : textOf(row, 'kanji').isNotEmpty
                                    ? textOf(row, 'kanji')
                                    : reading,
                                style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'),
                                  fontSize: 19,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (textOf(row, 'pos').isNotEmpty) ...[
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * .3,
                        ),
                        child: Text(
                          '[${row['pos']}]',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.5,
                            color: Color(0xFF32AA43),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ] else ...[
                if (textOf(row, 'role').isNotEmpty)
                  ListeningRubyText(
                    '${row['role']}：',
                    ruby: showRuby,
                    fontSize: 16,
                    color: scheme.primary,
                  ),
                ListeningRubyText(
                  textOf(row, 'content'),
                  ruby: showRuby,
                  source: showSource,
                  active: active,
                ),
              ],
              const SizedBox(height: 6),
              keepSpace(
                showTranslation,
                Align(
                  alignment: section.card.words
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Text(
                    textOf(row, 'definition'),
                    textAlign: section.card.words
                        ? TextAlign.right
                        : TextAlign.left,
                    style: TextStyle(fontFamily: 'PingFang SC', locale: Locale('zh', 'CN'),
                      fontSize: 16,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              if (listeningAudioSource(row).isEmpty)
                const Text('暂无音频', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = sections.isEmpty ? null : sections[currentSection];
    final blocked = resourceBlocked;
    final playbackError = owns ? playback.error : null;
    final queueActive = owns && playback.active && playback.batch;
    final buttonsDisabled =
        playbackLocked ||
        (!queueActive && (loading || error != null || blocked));
    final settingsDisabled =
        playbackLocked || loading || error != null || blocked;
    return ListeningScaffold(
      controlledLesson: identity,
      appBar: StudyAppBar(
        centerTitle: true,
        title: const Text('磨耳朵'),
        actions: [
          StudySpeedButton(onPressed: _speed, speed: speed),
          StudyIconButton.transparent(
            tooltip: '显示内容',
            onPressed: _displayOptions,
            showPressHighlight: false,
            padding: const EdgeInsets.all(2),
            icon: StudyDisplayRingIcon(
              source: showSource,
              ruby: showRuby,
              translation: showTranslation,
            ),
          ),
        ],
      ),
      body: loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const StudyCircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('正在准备课程 $prepared / ${widget.queue.length}'),
                ],
              ),
            )
          : error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error!, textAlign: TextAlign.center),
                    StudyButton.text(
                      onPressed: busy ? null : _prepare,
                      child: const Text('重新准备'),
                    ),
                  ],
                ),
              ),
            )
          : current == null
          ? const SizedBox.shrink()
          : Column(
              children: [
                StudyListTile(
                  leading: Icon(current.card.icon),
                  title: Text('${current.card.course} · ${current.card.label}'),
                  subtitle: Text(
                    '${currentSection + 1} / ${sections.length} 项 · ${owns && playback.active
                        ? playback.batch
                              ? '按所选顺序循环播放'
                              : '单条播放，播完停止'
                        : '等待手动播放'}',
                  ),
                ),
                if (silentCards.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Text(
                      '暂无音频，自动跳过：${silentCards.join('、')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (blocked)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('内容正在同步或需要修复，暂时无法播放。'),
                  ),
                if (playbackError != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      featureError(
                        StateError(playbackError),
                        fallback: '音频播放失败',
                      ),
                    ),
                  ),
                Expanded(child: _guardTouches(_mixedList())),
              ],
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _guardTouches(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: queueActive
                      ? ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: StudyButton.text(
                            onPressed: buttonsDisabled ? null : _stopQueue,
                            child: const Text('停止播放'),
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: StudyButton.text(
                                onPressed: buttonsDisabled
                                    ? null
                                    : () => _playFrom(resumeIndex),
                                child: const Text('继续播放'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: StudyButton.text(
                                onPressed: buttonsDisabled
                                    ? null
                                    : () => _playFrom(0),
                                child: const Text('从头播放'),
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: StudyButton.text(
                          onPressed: settingsDisabled ? null : _changeRepeat,
                          child: Text('循环 $repeat 次'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: StudyButton.text(
                          onPressed: settingsDisabled ? null : _changeInterval,
                          child: Text('间隔 $intervalSeconds 秒'),
                        ),
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
  }
}

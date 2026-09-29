import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

import '../../../glass_ui.dart';
import '../../host_contracts.dart';
import 'controller.dart';
import 'lesson_selector.dart';
import 'models.dart';
import 'speaker.dart';

class FlashcardsPage extends StatefulWidget {
  const FlashcardsPage(this.host, {super.key});
  final StudyRoomHost host;
  @override
  State<FlashcardsPage> createState() => _FlashcardsPageState();
}

class _FlashcardsPageState extends State<FlashcardsPage> {
  late final FlashController c;
  bool _confirming = false;
  bool _choosingBook = false;
  @override
  void initState() {
    super.initState();
    c = FlashController(widget.host);
    unawaited(c.load());
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String message) async {
    if (_confirming) return false;
    _confirming = true;
    try {
      return await showGlassDialog<bool>(
            context: context,
            builder: (dialogContext) => GlassAlertDialog(
              title: const Text('未完成的复习'),
              content: Text(message),
              actions: [
                StudyButton.text(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                StudyButton.filled(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('确定'),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      _confirming = false;
    }
  }

  Future<void> _start() async {
    if (!c.validateSelection()) return;
    if (c.hasDraft && !await _confirm('新开一轮将放弃未完成队列，已经提交的认识／不熟标记保留。')) return;
    if (mounted) await c.start();
  }

  Future<void> _chooseBook() async {
    if (c.busy || _choosingBook || _confirming) return;
    setState(() => _choosingBook = true);
    try {
      final book = await showGlassDialog<String>(
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
              if (c.books.isEmpty) const Text('暂无可用内容，请先在内容库完成下载。'),
              for (final row in c.books) ...[
                if (row != c.books.first) const SizedBox(height: 12),
                Semantics(
                  selected: row['id'].toString() == c.bookId,
                  child: row['id'].toString() == c.bookId
                      ? StudyButton.filled(
                          onPressed: () => Navigator.pop(
                            dialogContext,
                            row['id'].toString(),
                          ),
                          child: Text(
                            '${row['textbook']} ${row['volume'] ?? ''}',
                          ),
                        )
                      : StudyButton.text(
                          onPressed: () => Navigator.pop(
                            dialogContext,
                            row['id'].toString(),
                          ),
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
      if (mounted && book != null && book != c.bookId) {
        await c.configure(book: book);
      }
    } finally {
      if (mounted) setState(() => _choosingBook = false);
    }
  }

  String get _bookTitle {
    for (final book in c.books) {
      if (book['id'].toString() == c.bookId) {
        return '${book['textbook']} ${book['volume'] ?? ''}'.trim();
      }
    }
    return '请通过右上角内容图标选择内容';
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 10),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _optionRow<T>(
    String title,
    Map<T, String> values,
    T selected,
    ValueChanged<T> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            enabled: !c.busy,
            child: AbsorbPointer(
              absorbing: c.busy,
              child: StudySegments<T>(
                values: values,
                selected: selected,
                onChanged: (value) {
                  if (!c.busy && value != selected) onChanged(value);
                },
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _message(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(text),
  );

  Widget _setup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(_bookTitle),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final heading =
                  TextPainter(
                    text: TextSpan(
                      text: '本内容课程 · 点击勾选 / 再次点击取消',
                      style: DefaultTextStyle.of(context).style,
                    ),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                  )..layout(
                    maxWidth: (constraints.maxWidth - 32).clamp(
                      0.0,
                      double.infinity,
                    ),
                  );
              final freeHeight = (constraints.maxHeight - heading.height - 25)
                  .clamp(0.0, constraints.maxHeight);
              heading.dispose();
              final optionsHeight = (freeHeight / 2 + 60).clamp(
                0.0,
                freeHeight * .75,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: optionsHeight, child: _setupOptions()),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const StudyDivider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Text('本内容课程 · 点击勾选 / 再次点击取消'),
                        ),
                        Expanded(
                          child: c.lessons.isEmpty
                              ? SingleChildScrollView(
                                  padding: const EdgeInsets.all(20),
                                  child: Text(
                                    c.books.isEmpty
                                        ? '暂无可用的已安装内容，请先在内容库下载，再重新进入闪卡复习。'
                                        : '请选择包含单词的内容。',
                                  ),
                                )
                              : Padding(
                                  padding: EdgeInsets.zero,
                                  child: FlashLessonSelector(
                                    key: ValueKey(c.bookId),
                                    lessons: [
                                      for (final lesson in c.lessons)
                                        (
                                          id: lesson['id'].toString(),
                                          title: '第${lesson['num']}课',
                                        ),
                                    ],
                                    selected: c.lessonIds,
                                    onToggle: c.busy
                                        ? null
                                        : (id) {
                                            final selected = Set<String>.of(
                                              c.lessonIds,
                                            );
                                            if (!selected.add(id))
                                              selected.remove(id);
                                            unawaited(
                                              c.configure(
                                                selectedLessons: selected,
                                              ),
                                            );
                                          },
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: StudyButton.text(
                    onPressed: c.busy || c.lessons.isEmpty
                        ? null
                        : () => c.configure(
                            selectedLessons: {
                              for (final lesson in c.lessons)
                                lesson['id'].toString(),
                            },
                          ),
                    child: const Text('全部单词'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StudyButton.text(
                    onPressed: c.busy || c.lessonIds.isEmpty
                        ? null
                        : () => c.configure(selectedLessons: <String>{}),
                    child: const Text('取消选择'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _setupOptions() => ListView(
    primary: false,
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
    children: [
      _optionRow<FlashDirection>(
        '回忆方向',
        {
          for (final direction in FlashDirection.values)
            direction: direction.label,
        },
        c.direction,
        (value) => unawaited(c.configure(nextDirection: value)),
      ),
      _optionRow<bool>(
        '复习范围',
        const {false: '全部单词', true: '仅不熟'},
        c.onlyWeak,
        (value) => unawaited(c.configure(weak: value)),
      ),
      _optionRow<int>(
        '每轮数量',
        const {10: '10词', 20: '20词', 0: '全部'},
        c.limit,
        (value) => unawaited(c.configure(count: value)),
      ),
      _optionRow<bool>(
        '单词顺序',
        const {false: '顺序', true: '随机'},
        c.randomOrder,
        (value) => unawaited(c.configure(random: value)),
      ),
      if (c.hasDraft) const SizedBox(height: 12),
      if (c.hasDraft)
        StudyCard(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '上次：${c.session!.direction.label} · 已完成 ${c.session!.index}/${c.session!.words.length}',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: StudyButton.text(
                        onPressed: c.busy || !c.permitted ? null : c.resume,
                        child: const Text('继续上次'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StudyButton.text(
                        onPressed: c.busy
                            ? null
                            : () async {
                                if (await _confirm('放弃未完成队列？已经提交的标记会保留。') &&
                                    mounted) {
                                  await c.discard();
                                }
                              },
                        child: const Text('放弃草稿'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      if (c.error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(c.error!)),
                const SizedBox(width: 12),
                StudyIconButton(
                  tooltip: '关闭提示',
                  onPressed: c.dismissError,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _review() {
    final session = c.session!;
    final word = session.words[c.reviewIndex];
    final jp = session.direction == FlashDirection.japanese;
    final colors = Theme.of(context).colorScheme;
    final text = c.flipped
        ? (jp ? word.chinese : word.japanese)
        : (jp ? word.japanese : word.chinese);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < 450 ||
            MediaQuery.textScalerOf(context).scale(14) > 21;
        final content = ListView(
          key: ValueKey('card:${session.id}:${c.reviewIndex}'),
          primary: false,
          shrinkWrap: compact,
          physics: compact ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.all(20),
          children: [
            Text(word.source, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Semantics(
              button: true,
              label: '点击播放单词读音',
              child: lg.GlassCard(
                useOwnLayer: true,
                quality: studyGlassControlQuality,
                padding: EdgeInsets.zero,
                margin: const EdgeInsets.all(4),
                clipBehavior: Clip.antiAlias,
                child: StudyInkWell(
                  onTap:
                      c.busy || c.advancing || !c.permitted || c.resourceBlocked
                      ? null
                      : () => unawaited(c.playPronunciation()),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: double.infinity,
                      minHeight: 250,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FlashcardSpeaker(controller: c),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            c.flipped
                                ? '本词条答案'
                                : jp
                                ? '想一想中文意思'
                                : '想一想日语怎么说',
                          ),
                          const SizedBox(height: 22),
                          Text(
                            text,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(
                                  fontFamily: (c.flipped ? !jp : jp) ? 'Hiragino Mincho ProN' : 'Songti SC',
                                  locale: (c.flipped ? !jp : jp) ? const Locale('ja', 'JP') : const Locale('zh', 'CN'),
                                  height: 1.5,
                                ),
                          ),
                          if ((jp || c.flipped) &&
                              word.kana.isNotEmpty &&
                              word.kana != text) ...[
                            const SizedBox(height: 12),
                            Text(word.kana, style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP')), textAlign: TextAlign.center),
                          ],
                          if (c.flipped) ...[
                            const SizedBox(height: 12),
                            Text(
                              jp ? word.japanese : word.chinese,
                              style: TextStyle(fontFamily: jp ? 'Hiragino Sans' : 'PingFang SC', locale: jp ? const Locale('ja', 'JP') : const Locale('zh', 'CN')),
                              textAlign: TextAlign.center,
                            ),
                            if (word.pos.isNotEmpty)
                              Text(
                                word.pos,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!c.awaitingNext) ...[
              const SizedBox(height: 16),
              StudyButton.outlined(
                onPressed: c.busy || c.advancing || !c.permitted || c.resourceBlocked
                    ? null
                    : c.flip,
                child: Text(c.flipped ? '回到正面' : '查看答案'),
              ),
              const SizedBox(height: 16),
            ],
          ],
        );
        final children = <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Row(
              children: [
                Expanded(child: Text(session.direction.label)),
                Text('${c.reviewIndex + 1} / ${session.words.length}'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: LinearProgressIndicator(
              value: session.index / session.words.length,
            ),
          ),
          compact ? content : Expanded(child: content),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c.awaitingNext) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: const Text(
                          '已标记不熟，记住答案后继续。',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    StudyButton.filled(
                      onPressed: c.busy || !c.permitted || c.resourceBlocked
                          ? null
                          : c.next,
                      child: Text(session.complete ? '查看本轮结果' : '下一张'),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: StudyButton.outlined(
                            onPressed: !c.canRate ? null : () => c.mark(false),
                            child: const Text('不熟'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StudyButton.filled(
                            onPressed: !c.canRate ? null : () => c.mark(true),
                            child: const Text('认识'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  StudyButton.text(
                    onPressed: c.busy ? null : c.setup,
                    child: const Text('暂存退出'),
                  ),
                ],
              ),
            ),
          ),
        ];
        return compact
            ? ListView(
                key: ValueKey('round:${session.id}:${c.reviewIndex}'),
                children: children,
              )
            : Column(children: children);
      },
    );
  }

  Widget _result() {
    final session = c.session!;
    final children = <Widget>[
      Text(
        '这一轮完成了',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      _message('${session.direction.label} · 复习 ${session.words.length} 词'),
      _heading(
        '认识 ${session.words.length - session.weak.length}　／　不熟 ${session.weak.length}',
      ),
      for (final word in session.weak)
        StudyListTile(
          title: Text(word.japanese),
          subtitle: Text('${word.kana}\n${word.chinese}'),
        ),
      if (session.weak.isEmpty) _message('本轮没有不熟词，可以换个方向继续练习。'),
      if (session.weak.isNotEmpty) ...[
        StudyButton.filled(
          onPressed: c.busy || !c.permitted || c.resourceBlocked
              ? null
              : c.retryWeak,
          child: Text('再练本轮不熟 · ${session.weak.length}词'),
        ),
        const SizedBox(height: 8),
      ],
      StudyButton.text(
        onPressed: c.busy ? null : c.setup,
        child: const Text('返回复习设置'),
      ),
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => PopScope(
      canPop: !c.busy && c.stage != FlashStage.review,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !c.busy && c.stage == FlashStage.review)
          unawaited(c.setup());
      },
      child: Scaffold(
        appBar: StudyAppBar(
          title: const Text('闪卡复习'),
          actions: [
            if (c.stage == FlashStage.setup)
              StudyIconButton(
                tooltip: '选择内容',
                onPressed: c.busy || _choosingBook || _confirming
                    ? null
                    : _chooseBook,
                icon: const Icon(Icons.library_books_outlined),
              ),
            if (c.stage == FlashStage.setup)
              StudyIconButton(
                tooltip: '开始复习',
                onPressed:
                    c.busy || _choosingBook || !c.permitted || c.resourceBlocked
                    ? null
                    : _start,
                icon: const Icon(Icons.play_circle_outline_rounded),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                children: [
                  if (c.busy) const LinearProgressIndicator(),
                  if (!c.permitted)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('自习室暂未解锁，复习进度已保留。'),
                    ),
                  if (c.resourceBlocked)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('内容正在更新或需要修复，请处理完成后重新进入闪卡复习。'),
                    ),
                  if (c.error != null && c.stage != FlashStage.setup)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          c.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: switch (c.stage) {
                      FlashStage.setup => _setup(),
                      FlashStage.review => _review(),
                      FlashStage.result => _result(),
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

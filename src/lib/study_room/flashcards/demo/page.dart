import 'dart:async';

import 'package:flutter/material.dart';

import '../../../glass_ui.dart';
import 'guide.dart';
import 'controller.dart';
import 'lesson_selector.dart';
import 'models.dart';

class FlashcardsDemoPage extends StatefulWidget {
  const FlashcardsDemoPage({super.key});
  @override
  State<FlashcardsDemoPage> createState() => _FlashcardsDemoPageState();
}

class _FlashcardsDemoPageState extends State<FlashcardsDemoPage> {
  late final FlashDemoController c;
  final _demoTargets = FlashDemoTargets();
  bool _confirming = false;
  @override
  void initState() {
    super.initState();
    c = FlashDemoController();
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

  String get _bookTitle {
    for (final book in c.books) {
      if (book['id'].toString() == c.bookId) {
        return '${book['textbook']} ${book['volume'] ?? ''}'.trim();
      }
    }
    return '正在载入演示样例';
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
                                        ? '演示样例暂不可用，请重新播放。'
                                        : '演示课程暂不可用，请重新播放。',
                                  ),
                                )
                              : Padding(
                                  key: _demoTargets.lesson,
                                  padding: EdgeInsets.zero,
                                  child: FlashDemoLessonSelector(
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
      _message(
        '第1课 · 中国人、日本人\n使用内置样例体验闪卡，演示记录不会影响正式学习。',
      ),
      _optionRow<FlashDemoDirection>(
        '回忆方向',
        {
          for (final direction in FlashDemoDirection.values)
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
                        onPressed: c.busy ? null : c.resume,
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
    final jp = session.direction == FlashDemoDirection.japanese;
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
              child: StudyCard(
                key: _demoTargets.card,
                color: colors.surfaceContainerLow,
                clipBehavior: Clip.antiAlias,
                child: StudyInkWell(
                  onTap:
                      c.busy || c.advancing
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
                      key: _demoTargets.next,
                      onPressed: c.busy ? null : c.next,
                      child: Text(session.complete ? '查看本轮结果' : '下一张'),
                    ),
                  ] else ...[
                    StudyButton.outlined(
                      key: _demoTargets.flip,
                      onPressed: c.busy || c.advancing ? null : c.flip,
                      child: Text(c.flipped ? '回到正面' : '查看答案'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: StudyButton.outlined(
                            key: _demoTargets.weak,
                            onPressed: !c.canRate ? null : () => c.mark(false),
                            child: const Text('不熟'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StudyButton.filled(
                            key: _demoTargets.known,
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
        // Tour targets must be mounted before the guide scrolls to them.
        if (compact) {
          return SingleChildScrollView(
            key: ValueKey('round:${session.id}:${c.reviewIndex}'),
            child: Column(children: children),
          );
        }
        return Column(children: children);
      },
    );
  }

  Widget _result() {
    final session = c.session!;
    final children = <Widget>[
      Text(
        '这一轮完成了',
        key: _demoTargets.result,
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
          key: _demoTargets.retry,
          onPressed: c.busy
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _buildPage();
    return FlashDemoGuide(
      controller: c,
      targets: _demoTargets,
      child: page,
    );
  }

  Widget _buildPage() => AnimatedBuilder(
    animation: c,
    builder: (context, _) => PopScope(
      canPop: true,
      child: Scaffold(
        appBar: StudyAppBar(
          title: const Text('闪卡复习 · 演示'),
          actions: [
            if (c.stage == FlashDemoStage.setup)
              StudyIconButton(
                key: _demoTargets.start,
                tooltip: '开始复习',
                onPressed: c.busy ? null : _start,
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
                  if (c.error != null && c.stage != FlashDemoStage.setup)
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
                      FlashDemoStage.setup => _setup(),
                      FlashDemoStage.review => _review(),
                      FlashDemoStage.result => _result(),
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

import '../../l10n/l10n.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../glass_ui.dart';
import '../host_contracts.dart';
import '../access/access.dart';
import 'demo/entry.dart';
import 'feature/entry.dart';

class FlashcardsEntry extends StatefulWidget {
  const FlashcardsEntry(this.host, this.access, {super.key});
  final StudyRoomHost host;
  final StudyRoomAccess access;
  @override
  State<FlashcardsEntry> createState() => _FlashcardsEntryState();
}

class _FlashcardsEntryState extends State<FlashcardsEntry> {
  bool _opening = false;
  String get title => context.tr('闪卡', '單字卡', 'Flashcards', 'フラッシュカード');
  String get caption => context.tr(
    '翻一张，记牢一点。',
    '翻一張，記牢一點。',
    'One card, one stronger memory.',
    '1枚めくって、少しずつ定着。',
  );
  String get description => context.tr(
    '原文与释义双向回忆，集中复习不熟的单词。',
    '原文與釋義雙向回憶，集中複習不熟的單字。',
    'Recall words and meanings both ways, focusing on unfamiliar words.',
    '原文と意味の両方向で思い出し、苦手な単語を集中復習。',
  );
  static const icon = Icons.style_rounded;
  static const colors = [Color(0xFF577263), Color(0xFF304D40)];
  Future<void> _open({required bool demo}) async {
    if (_opening) return;
    _opening = true;
    try {
      if (!demo && !await widget.access.ensure(context)) return;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => demo
              ? buildFlashcardsDemo()
              : buildFlashcardsFeature(widget.host),
        ),
      );
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    const cream = Color(0xFFFFEDC7);
    void openDemo() => unawaited(_open(demo: true));
    void openCard() => unawaited(_open(demo: !widget.host.isUnlocked()));
    void openCornerAction() {
      if (widget.host.isUnlocked()) {
        unawaited(_open(demo: false));
      } else {
        unawaited(widget.access.ensure(context));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        button: true,
        label:
            '$title，${widget.host.isUnlocked() ? context.tr('进入功能', '進入功能', 'Open feature', '機能を開く') : context.tr('查看演示', '查看示範', 'View demo', 'デモを見る')}',
        onTap: openCard,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .12),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: StudyPanel(
            color: colors.last,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFCBB58B), width: 1.5),
              ),
              child: GestureDetector(
                onTap: openCard,
                excludeFromSemantics: true,
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  children: [
                    Positioned(
                      right: -24,
                      top: 22,
                      child: IgnorePointer(
                        child: Container(
                          width: 174,
                          height: 174,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: cream.withValues(alpha: .10),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 24,
                      top: 55,
                      child: IgnorePointer(
                        child: Transform.rotate(
                          angle: -.12,
                          child: Icon(
                            icon,
                            size: 94,
                            color: cream.withValues(alpha: .20),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 164),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ExcludeSemantics(
                                    child: Text(
                                      title,
                                      style: const TextStyle(
                                        fontFamily: 'Songti SC',
                                        locale: Locale('zh', 'CN'),

                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                        color: cream,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Semantics(
                                  button: true,
                                  label: widget.host.isUnlocked()
                                      ? '${context.tr('进入', '進入', 'Open', '開く')} $title'
                                      : '${context.tr('购买解锁', '購買解鎖', 'Unlock', '購入して解放')} $title',
                                  onTap: openCornerAction,
                                  child: ExcludeSemantics(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: openCornerAction,
                                      child: SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: Center(
                                          child: Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: cream.withValues(
                                                alpha: .12,
                                              ),
                                              border: Border.all(
                                                color: cream.withValues(
                                                  alpha: .45,
                                                ),
                                              ),
                                            ),
                                            child: Icon(
                                              widget.host.isUnlocked()
                                                  ? Icons.arrow_forward_rounded
                                                  : Icons.lock_outline_rounded,
                                              size: 20,
                                              color: cream,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.only(left: 23),
                              child: ExcludeSemantics(
                                child: Text(
                                  caption,
                                  style: TextStyle(
                                    fontSize: 12,
                                    letterSpacing: 1,
                                    color: cream.withValues(alpha: .75),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Semantics(
                              button: true,
                              label:
                                  '$title · ${context.tr('查看演示', '查看示範', 'View demo', 'デモを見る')}',
                              onTap: openDemo,
                              child: ExcludeSemantics(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: openDemo,
                                  child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: Center(
                                      child: Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: cream.withValues(alpha: .12),
                                          border: Border.all(
                                            color: cream.withValues(alpha: .45),
                                          ),
                                        ),
                                        child: const Center(
                                          child: Text(
                                            '!',
                                            style: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w600,
                                              color: cream,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              description,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.6,
                                color: cream,
                              ),
                            ),
                          ],
                        ),
                      ),
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
}

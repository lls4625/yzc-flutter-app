import '../../l10n/l10n.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../glass_ui.dart';
import '../host_contracts.dart';
import '../access/access.dart';
import 'feature/entry.dart';
import 'demo/entry.dart';

class ListeningEntry extends StatefulWidget {
  const ListeningEntry(this.host, this.access, {super.key});
  final StudyRoomHost host;
  final StudyRoomAccess access;
  @override
  State<ListeningEntry> createState() => _ListeningEntryState();
}

class _ListeningEntryState extends State<ListeningEntry> {
  bool _opening = false;
  String get title => context.tr('磨耳朵', '磨耳朵', 'Listening', 'リスニング');
  String get caption => context.tr(
    '听见语言的节奏',
    '聽見語言的節奏',
    'Hear the rhythm of language',
    '言葉のリズムを聴く',
  );
  String get description => context.tr(
    '让语言融入日常，反复聆听，慢慢培养语感。',
    '讓語言融入日常，反覆聆聽，慢慢培養語感。',
    'Bring language into everyday life. Listen again and build your intuition.',
    '毎日の生活に言葉を。繰り返し聴いて、少しずつ語感を育てましょう。',
  );
  static const icon = Icons.headphones_rounded;
  static const colors = [Color(0xFF466D67), Color(0xFF213F3D)];
  Future<void> _open({required bool demo}) async {
    if (_opening) return;
    _opening = true;
    try {
      if (!demo && !await widget.access.ensure(context)) return;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => demo
              ? buildListeningDemo()
              : buildListeningFeature(widget.host, widget.access),
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

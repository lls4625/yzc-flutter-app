import 'demo/entry.dart';
import 'feature/entry.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../glass_ui.dart';
import '../host_contracts.dart';
import '../access/access.dart';
import '../resources/page.dart';

class JlptPracticeEntry extends StatefulWidget {
  const JlptPracticeEntry(this.host, this.access, {super.key});
  final StudyRoomHost host;
  final StudyRoomAccess access;
  @override
  State<JlptPracticeEntry> createState() => _JlptPracticeEntryState();
}

class _JlptPracticeEntryState extends State<JlptPracticeEntry> {
  bool _opening = false;
  static const title = 'J练习';
  static const caption = '所有题目均为测试题目，非考试真题，请慎重考虑！';
  static const description = '一步一步 稳稳积累 围绕词汇、语法与阅读逐项练习，积累每一点进步。';
  static const icon = Icons.menu_book_rounded;
  static const colors = [Color(0xFF8B7051), Color(0xFF57432F)];
  Future<void> _open({required bool demo}) async {
    if (_opening) return;
    _opening = true;
    try {
      if (!demo && !await widget.access.ensure(context)) return;
      if (!mounted) return;
      if (demo) {
        showJlptPracticeDemo(context);
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => buildJlptPracticeFeature(widget.host),
      ));
    } finally {
      _opening = false;
    }
  }

  Future<void> _updateResources() async {
    if (_opening || !await widget.access.ensure(context) || !mounted) return;
    _opening = true;
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => StudyResourcePage(widget.host)));
    } finally { _opening = false; }
  }

  @override
  Widget build(BuildContext context) {
    const cream = Color(0xFFFFEDC7);
    void openDemo() => unawaited(_open(demo: true));
    void openCard() => unawaited(_open(demo: false));
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
        label: '$title，${widget.host.isUnlocked() ? '进入功能' : '购买解锁'}',
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
                            if (widget.host.resources.hasUpdate)
                              Align(alignment: Alignment.centerRight, child: TextButton.icon(
                                onPressed: _updateResources,
                                icon: const Icon(Icons.system_update_alt, color: cream, size: 18),
                                label: const Text('有更新', style: TextStyle(color: cream)),
                              )),
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
                                        fontFamilyFallback: ['STSong', 'serif'],
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
                                      ? '进入$title'
                                      : '购买解锁$title',
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
                              label: '查看$title演示',
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

import 'dart:async';

import 'package:flutter/material.dart';

import '../../glass_ui.dart';
import '../access/access.dart';
import '../host_contracts.dart';
import 'feature/page.dart';

class GrammarLookupEntry extends StatefulWidget {
  const GrammarLookupEntry(this.host, this.access, {super.key});
  final StudyRoomHost host;
  final StudyRoomAccess access;

  @override
  State<GrammarLookupEntry> createState() => _GrammarLookupEntryState();
}

class _GrammarLookupEntryState extends State<GrammarLookupEntry> {
  bool _opening = false;
  static const title = '查文法';
  static const caption = '日语文法、中文解释';
  static const description = '在已安装的内容文法表中快速查找。';
  static const icon = Icons.menu_book_outlined;
  static const colors = [Color(0xFF665D78), Color(0xFF40384F)];

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    try {
      if (!await widget.access.ensure(context) || !mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => GrammarLookupPage(widget.host),
      ));
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    const cream = Color(0xFFFFEDC7);
    void openCard() => unawaited(_open());
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
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .12),
              blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: StudyPanel(
            color: colors.last,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topLeft,
                  end: Alignment.bottomRight, colors: colors),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFCBB58B), width: 1.5),
              ),
              child: GestureDetector(
                onTap: openCard,
                excludeFromSemantics: true,
                behavior: HitTestBehavior.opaque,
                child: Stack(children: [
                  Positioned(
                    right: -24,
                    top: 22,
                    child: IgnorePointer(
                      child: Container(
                        width: 174,
                        height: 174,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: cream.withValues(alpha: .10)),
                        ),
                      ),
                    ),
                  ),
                  Positioned(right: 24, top: 55, child: IgnorePointer(child: Transform.rotate(
                    angle: -.12, child: Icon(icon, size: 94,
                      color: cream.withValues(alpha: .20))))),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 164),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Expanded(child: ExcludeSemantics(child: Text(title,
                            style: TextStyle(fontFamily: 'Songti SC', locale: Locale('zh', 'CN'),
                              fontFamilyFallback: ['STSong', 'serif'], fontSize: 22,
                              fontWeight: FontWeight.w600, color: cream, letterSpacing: 1)))),
                          const SizedBox(width: 12),
                          Semantics(button: true,
                            label: widget.host.isUnlocked() ? '进入$title' : '购买解锁$title',
                            onTap: openCard,
                            child: ExcludeSemantics(child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: openCard,
                              child: SizedBox(width: 44, height: 44, child: Center(child: Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(shape: BoxShape.circle,
                                  color: cream.withValues(alpha: .12),
                                  border: Border.all(color: cream.withValues(alpha: .45))),
                                child: Icon(widget.host.isUnlocked()
                                  ? Icons.arrow_forward_rounded : Icons.lock_outline_rounded,
                                  size: 20, color: cream),
                              ))),
                            )),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        Padding(padding: const EdgeInsets.only(left: 23),
                          child: ExcludeSemantics(child: Text(caption,
                            style: TextStyle(fontSize: 12, letterSpacing: 1,
                              color: cream.withValues(alpha: .75))))),
                        const SizedBox(height: 24),
                        const Padding(padding: EdgeInsets.only(left: 23, right: 86),
                          child: Text(description, style: TextStyle(
                            fontSize: 13, height: 1.6, color: cream))),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

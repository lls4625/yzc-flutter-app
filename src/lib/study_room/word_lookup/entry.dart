import '../../l10n/l10n.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../glass_ui.dart';
import '../access/access.dart';
import '../host_contracts.dart';
import 'feature/page.dart';

class WordLookupEntry extends StatefulWidget {
  const WordLookupEntry(this.host, this.access, {super.key});
  final StudyRoomHost host;
  final StudyRoomAccess access;

  @override
  State<WordLookupEntry> createState() => _WordLookupEntryState();
}

class _WordLookupEntryState extends State<WordLookupEntry> {
  bool _opening = false;
  String get title => context.tr('查单词', '查單字', 'Word search', '単語検索');
  String get caption =>
      context.tr('原文、释义', '原文、釋義', 'Original text and meaning', '原文・意味');
  String get description => context.tr(
    '在已安装的内容单词表中快速查找。',
    '在已安裝的內容單字表中快速搜尋。',
    'Quickly search words in installed content.',
    'インストール済みのコンテンツから単語をすばやく検索。',
  );
  static const icon = Icons.manage_search_rounded;
  static const colors = [Color(0xFF7B6045), Color(0xFF4C3928)];

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    try {
      if (!await widget.access.ensure(context) || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => WordLookupPage(widget.host)),
      );
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
        label:
            '$title，${widget.host.isUnlocked() ? context.tr('进入功能', '進入功能', 'Open feature', '機能を開く') : context.tr('购买解锁', '購買解鎖', 'Unlock', '購入して解放')}',
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
                gradient: const LinearGradient(
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
                                      style: TextStyle(
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
                                  onTap: openCard,
                                  child: ExcludeSemantics(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: openCard,
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
                            const SizedBox(height: 24),
                            Padding(
                              padding: EdgeInsets.only(left: 23, right: 86),
                              child: Text(
                                description,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.6,
                                  color: cream,
                                ),
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

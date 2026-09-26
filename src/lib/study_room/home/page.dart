import 'package:flutter/material.dart';

import '../../glass_ui.dart';
import '../host_contracts.dart';
import '../access/access.dart';
import '../flashcards/entry.dart';
import '../listening/entry.dart';
import '../dictation/entry.dart';
import '../jlpt_practice/entry.dart';
import '../jlpt_test/entry.dart';
import '../word_lookup/entry.dart';
import '../grammar_lookup/entry.dart';

class StudyRoomPage extends StatelessWidget {
  const StudyRoomPage(this.host, this.access, {super.key});
  final StudyRoomHost host;
  final StudyRoomAccess access;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: host.changes,
    builder: (context, _) => _buildPage(context),
  );

  Widget _buildPage(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFE6CCA0) : const Color(0xFF785738);
    final paper = dark ? const Color(0xFF25231F) : const Color(0xFFF3E9D6);
    return ColoredBox(
      color: paper,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              child: Column(
                children: [
                  Semantics(
                    header: true,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '為せば成る',
                        style: TextStyle(
                          fontFamily: 'Hiragino Mincho ProN',
                          locale: const Locale('ja', 'JP'),
                          fontFamilyFallback: const ['Hiragino Mincho Pro', 'serif'],
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 3,
                          color: ink,
                          shadows: [
                            Shadow(
                              color: dark ? Colors.black26 : Colors.white70,
                              offset: const Offset(1, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 24,
                        child: StudyDivider(color: ink.withValues(alpha: .35)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '今日も、一歩',
                          style: TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'),
                            fontSize: 11,
                            letterSpacing: 2,
                            color: ink.withValues(alpha: .8),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 24,
                        child: StudyDivider(color: ink.withValues(alpha: .35)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: ListView(
                    key: const PageStorageKey('study-room-features'),
                    primary: false,
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                    children: [
                      WordLookupEntry(host, access),
                      GrammarLookupEntry(host, access),
                      ListeningEntry(host, access),
                      DictationEntry(host, access),
                      FlashcardsEntry(host, access),
                      JlptPracticeEntry(host, access),
                      JlptTestEntry(host, access),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

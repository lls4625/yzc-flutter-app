import 'package:flutter/material.dart';

import '../../../glass_ui.dart';

/// Flashcard-owned course cards; presentation does not depend on listening.
class FlashLessonSelector extends StatelessWidget {
  const FlashLessonSelector({
    super.key,
    required this.lessons,
    required this.selected,
    required this.onToggle,
  });

  final List<({String id, String title})> lessons;
  final Set<String> selected;
  final ValueChanged<String>? onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        primary: false,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: constraints.maxWidth >= 320 ? 6 : 4,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
          mainAxisExtent: 60,
        ),
        itemCount: lessons.length,
        itemBuilder: (context, index) {
          final lesson = lessons[index];
          final checked = selected.contains(lesson.id);
          final status = checked ? '选中' : '未选中';
          final action = onToggle == null ? null : () => onToggle!(lesson.id);
          return Semantics(
            key: ValueKey(lesson.id),
            button: true,
            selected: checked,
            enabled: action != null,
            label: '${lesson.title}单词，$status',
            onTap: action,
            child: ExcludeSemantics(
              child: StudyPanel(
                color: checked
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: checked ? scheme.primary : scheme.outlineVariant,
                    width: checked ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: StudyInkWell(
                  onTap: action,
                  child: SizedBox.expand(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              lesson.title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.headphones_rounded,
                                  size: 13,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 2),
                                const Text(
                                  '单词',
                                  style: TextStyle(fontSize: 10),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  checked
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked,
                                  size: 12,
                                  color: checked
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                              ],
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
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/l10n.dart';
import '../lib/course/feature/video_controller.dart';
import '../lib/course/feature/media_widgets.dart';

void main() {
  testWidgets(
    'cached course video error follows locale without changing controller',
    (tester) async {
      final controller = CourseVideoController();
      addTearDown(controller.dispose);
      controller.error = '视频暂时无法播放，请重试';
      final owner = controller.owner;
      final rendered = <String>{};
      for (final locale in supportedUiLocales) {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: supportedUiLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: CourseVideoBar(controller: controller, onLocate: () {}),
            ),
          ),
        );
        await tester.pump();
        final context = tester.element(find.byType(CourseVideoBar));
        final translated = context.ui(controller.error!);
        expect(find.text(translated), findsOneWidget);
        rendered.add(translated);
        expect(controller.owner, owner);
        expect(controller.error, '视频暂时无法播放，请重试');
        expect(tester.takeException(), isNull);
      }
      expect(
        rendered.length,
        4,
        reason: 'all four locale renderings must be independently translated',
      );
    },
  );
}

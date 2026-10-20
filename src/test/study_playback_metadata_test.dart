import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/l10n.dart';
import '../lib/study_room/demo_localization/ui.dart';
import '../lib/study_room/jlpt_test/feature/models.dart';
import '../lib/study_room/jlpt_test/feature/review_audio.dart';

void main() {
  testWidgets(
    'new review playback uses current UI locale without changing media',
    (tester) async {
      final starts = <Map<dynamic, dynamic>>[];
      const channel = MethodChannel('yuzhichu/lesson_playback');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'start') starts.add(call.arguments as Map);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final question = Question({
        'id': 'metadata',
        'level': 'N5',
        'type_code': 'L_TASK',
        'phonetic': 'original.mp3',
      });
      final key = GlobalKey();
      State? originalState;
      for (final locale in supportedUiLocales) {
        late String expectedTitle, expectedAlbum;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: supportedUiLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  expectedTitle =
                      '${studyUi(context, question.typeName)} · ${studyUi(context, '回顾')}';
                  expectedAlbum = studyUi(context, 'J测试回顾');
                  return ReviewAudio(
                    key: key,
                    question: question,
                    resolveMedia: (_, __) async =>
                        '/original/package/original.mp3',
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        originalState ??= key.currentState;
        expect(key.currentState, same(originalState));
        final before = starts.length;
        await tester.tap(find.byIcon(Icons.volume_up_outlined));
        await tester.pumpAndSettle();
        expect(starts.length, before + 1);
        expect(starts.last['title'], expectedTitle);
        expect(starts.last['albumTitle'], expectedAlbum);
        expect(
          (starts.last['clips'] as List).single['path'],
          '/original/package/original.mp3',
        );
        if (locale.languageCode == 'en') expect(expectedAlbum, 'J Test review');
        if (locale.languageCode == 'ja') expect(expectedAlbum, 'Jテストの復習');
        expect(tester.takeException(), isNull);
      }
      expect(starts.length, 4);
    },
  );
}

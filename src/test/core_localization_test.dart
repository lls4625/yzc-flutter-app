import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/app.dart';
import '../lib/data.dart';
import '../lib/glass_ui.dart';
import '../lib/l10n/l10n.dart';
import '../lib/lesson_presentation.dart';
import '../lib/resource_operation_coordinator.dart';
import '../lib/resource_operation_ui.dart';
import '../lib/resources.dart';
import '../lib/user_error.dart';

class _PreferenceStore extends AppStore {
  final writes = <String, Object>{};
  @override
  Future<void> setSetting(String key, Object value) async {
    writes[key] = value;
  }

  @override
  Future<RowData> setting() =>
      throw StateError('A UI preference must not reload content or purchases');
}

class _DeletedPackageStore extends AppStore {
  _DeletedPackageStore(Database db, Directory root)
    : super.forTesting(db, root);
  @override
  Future<List<RowData>> practiceItems(String id) async => [
    {
      'id': 'item',
      'question_id': 'snapshot',
      'textbook_id': 'deleted-new-english-package',
      'content': 'Preserved question!',
      'definition': 'Preserved explanation',
      'relation': 'word',
      'correct_answer': 'A',
      'answer_time': null,
    },
  ];
  @override
  Future<List<RowData>> options(String id) async => [
    {'code': 'A', 'content': 'Preserved choice'},
  ];
}

class _Session extends StatefulWidget {
  const _Session();
  @override
  State<_Session> createState() => _SessionState();
}

class _SessionState extends State<_Session> {
  final answer = TextEditingController(text: 'retained answer');
  int step = 3;
  @override
  void dispose() {
    answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text(context.l10n.settings),
        TextField(controller: answer),
        Text('step:$step'),
        Text(context.ui(userError(PlatformException(code: 'speech_voice')))),
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('system locale resolution prioritizes explicit scripts then Chinese regions', () {
    expect(resolveUiLocale([const Locale('zh', 'CN')]), supportedUiLocales[0]);
    for (final region in ['TW', 'HK', 'MO']) {
      expect(resolveUiLocale([Locale('zh', region)]), supportedUiLocales[1]);
    }
    expect(
      resolveUiLocale([
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
          countryCode: 'TW',
        ),
      ]),
      supportedUiLocales[0],
    );
    expect(
      resolveUiLocale([
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
          countryCode: 'CN',
        ),
      ]),
      supportedUiLocales[1],
    );
    expect(resolveUiLocale([const Locale('fr')]), const Locale('en'));
    expect(resolveUiLocale(null), const Locale('en'));
    expect(uiLocaleFromSetting('system'), isNull);
    expect(uiLocaleFromSetting('invalid'), isNull);
  });
  test('lesson wrappers localize without changing R/P codes or sorting', () {
    final row = <String, Object?>{'lesson': 'r12', 'num': 12};
    expect(lessonLabel(row), '复习12');
    expect(lessonLabel(row, locale: const Locale('en')), 'Review 12');
    expect(
      lessonLabel({'lesson': 'p1', 'num': 1}, locale: const Locale('ja')),
      '準備1',
    );
    expect(
      lessonLabel({'lesson': '1', 'num': 1}, locale: supportedUiLocales[1]),
      '第1課',
    );
    expect(row, {'lesson': 'r12', 'num': 12});
  });
  test(
    'all official ARB messages and placeholders are complete in four languages',
    () {
      final baseline = jsonDecode(
        File('lib/l10n/app_en.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      final keys = baseline.keys.where((key) => !key.startsWith('@')).toSet();
      for (final locale in ['zh_Hans', 'zh_Hant', 'en', 'ja']) {
        final arb = jsonDecode(
          File('lib/l10n/app_$locale.arb').readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(
          arb.keys.where((key) => !key.startsWith('@')).toSet(),
          keys,
          reason: locale,
        );
        for (final key in keys) {
          expect(
            (arb[key] as String).trim(),
            isNotEmpty,
            reason: '$locale/$key',
          );
          expect(
            arb['@$key']?['placeholders'],
            baseline['@$key']?['placeholders'],
            reason: '$locale/$key',
          );
        }
      }
    },
  );
  testWidgets(
    'every fixed user-error boundary message has four-language rendering',
    (tester) async {
      final source = File('lib/user_error.dart').readAsStringSync();
      final messages = RegExp(r"return '([^']+)'[;]")
          .allMatches(source)
          .map((m) => m[1]!)
          .toSet();
      expect(messages.length, greaterThan(20));
      late BuildContext uiContext;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: supportedUiLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) {
              uiContext = context;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final message in messages) {
        expect(uiContext.ui(message), isNot(message), reason: message);
        expect(
          RegExp(r'[\u4e00-\u9fff]').hasMatch(uiContext.ui(message)),
          isFalse,
          reason: message,
        );
      }
    },
  );
  testWidgets(
    'actual StudyApp hot switch retains route, answer, step, and independent settings',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('yuzhichu/lesson_playback'),
            (_) async => <String, Object?>{},
          );
      final store = _PreferenceStore();
      final operations = ResourceOperationCoordinator();
      final resources = Resources(store, operations: operations);
      final app = AppController(store, resources, operations);
      app.settings = {
        'ui_locale': 'zh-Hans',
        'learning_target': 'ja',
        'font_scale': 0,
      };
      app.position = {'textbook_id': 'unchanged-book'};
      await tester.pumpWidget(studyGlassRoot(StudyApp(app)));
      await tester.pump();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(MaterialPageRoute<void>(builder: (_) => const _Session()));
      await tester.pumpAndSettle();
      final session = tester.state<_SessionState>(find.byType(_Session));
      final purchase = app.studyRoomPurchase;
      final tip = app.developerTip;
      for (final entry in [
        ('en', 'Settings'),
        ('ja', '設定'),
        ('zh-Hant', '設定'),
        ('zh-Hans', '设置'),
      ]) {
        await app.setting('ui_locale', entry.$1);
        await tester.pumpAndSettle();
        expect(find.text(entry.$2), findsOneWidget);
        expect(
          tester.state<_SessionState>(find.byType(_Session)),
          same(session),
        );
        expect(session.answer.text, 'retained answer');
        expect(session.step, 3);
        expect(app.learningTarget, 'ja');
        expect(app.position['textbook_id'], 'unchanged-book');
        expect(app.studyRoomPurchase, same(purchase));
        expect(app.developerTip, same(tip));
      }
      await app.setting('learning_target', 'en');
      await tester.pumpAndSettle();
      expect(app.learningTarget, 'en');
      expect(app.settings['ui_locale'], 'zh-Hans');
      expect(tester.state<_SessionState>(find.byType(_Session)), same(session));
      expect(store.writes, {'ui_locale': 'zh-Hans', 'learning_target': 'en'});
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
      resources.dispose();
      operations.dispose();
    },
  );
  test(
    'course fixed error boundaries all have canonical localization entries',
    () {
      final arb = jsonDecode(
        File('lib/l10n/app_zh_Hans.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      final values = arb.values.whereType<String>().toSet();
      final pattern = RegExp(
        r"(?:fallback:\s*|error\s*=\s*|StateError\()'([^']*)'",
      );
      for (final file
          in Directory('lib/course')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        for (final match in pattern.allMatches(file.readAsStringSync())) {
          final message = match[1]!;
          if (RegExp(r'[\u4e00-\u9fff]').hasMatch(message)) {
            expect(values, contains(message), reason: file.path);
          }
        }
      }
    },
  );
  testWidgets(
    'deleted new package retains neutral practice and due-review snapshots',
    (tester) async {
      sqfliteFfiInit();
      final database = await tester.runAsync(
        () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
      );
      await tester.runAsync(() async {
        await database!.execute('CREATE TABLE yzc_textbook (id TEXT)');
        await database.execute(
          'CREATE TABLE yzc_user_practice (id TEXT, user_id TEXT, type TEXT)',
        );
        await database.insert('yzc_user_practice', {
          'id': 'review',
          'user_id': 'test-user',
          'type': 'review',
        });
      });
      final store = _DeletedPackageStore(database!, Directory.systemTemp);
      final operations = ResourceOperationCoordinator();
      final resources = Resources(store, operations: operations);
      final app = AppController(store, resources, operations);
      final locale = ValueNotifier<Locale>(const Locale('en'));
      await tester.pumpWidget(
        ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (_, value, __) => studyGlassRoot(
            MaterialApp(
              locale: value,
              supportedLocales: supportedUiLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: PracticePage(app, 'review'),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('practice-neutral-body-0')),
        findsOneWidget,
      );
      expect(find.text('Preserved question!'), findsOneWidget);
      expect(find.textContaining('Preserved choice'), findsOneWidget);
      final state = tester.state(find.byType(PracticePage));
      locale.value = const Locale('ja');
      app.settings = {'learning_target': 'ja'};
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(PracticePage)), same(state));
      expect(find.text('Preserved question!'), findsOneWidget);
      expect(find.textContaining('元の教材の言語情報'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(database.close);
      locale.dispose();
      app.dispose();
      resources.dispose();
      operations.dispose();
    },
  );
  testWidgets(
    'canonical catalog error translates title and cause on every locale change',
    (tester) async {
      const cached = '内容目录更新失败：网络连接失败';
      for (final locale in supportedUiLocales) {
        late BuildContext ui;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: supportedUiLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Builder(
              builder: (context) {
                ui = context;
                return Text(context.ui(cached));
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('${ui.ui('内容目录更新失败')}：${ui.ui('网络连接失败')}'),
          findsOneWidget,
        );
        if (locale.languageCode == 'en')
          expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(ui.ui(cached)), isFalse);
      }
      expect(cached, '内容目录更新失败：网络连接失败');
      final source = File('lib/app.dart').readAsStringSync();
      expect(source.contains("_showOperationError(context.ui("), isFalse);
      expect(source.contains("? context.ui('学习资源包更新失败')"), isFalse);
    },
  );
  testWidgets(
    'cached errors and operation stages change language without changing state',
    (tester) async {
      final locale = ValueNotifier<Locale>(const Locale('en'));
      const cached = '网络连接失败。学习记录已保留。';
      await tester.pumpWidget(
        ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (_, value, __) => MaterialApp(
            locale: value,
            supportedLocales: supportedUiLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Builder(
              builder: (context) => Column(
                children: [
                  Text(context.ui(cached)),
                  Text(
                    resourceOperationText(
                      ResourceOperationStage.commit,
                      null,
                      subject: '学习资源',
                      context: context,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Network connection failed Learning records were kept.'),
        findsOneWidget,
      );
      expect(find.text('Finishing safely'), findsOneWidget);
      locale.value = const Locale('ja');
      await tester.pumpAndSettle();
      expect(find.text('安全に仕上げ処理中'), findsOneWidget);
      expect(cached, '网络连接失败。学习记录已保留。');
      await tester.pumpWidget(const SizedBox.shrink());
      locale.dispose();
    },
  );
}

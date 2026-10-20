import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../lib/resource_transfer.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/content_language.dart';
import '../lib/data.dart';
import '../lib/resources.dart';
import '../lib/ai_question.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('yuzhichu/lesson_playback'),
          (call) async => <String, Object?>{},
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('yuzhichu/lesson_playback'),
          null,
        );
  });

  test('language identity is explicit, string-safe and independent', () {
    expect(normalizedUiLocale('bogus'), 'system');
    expect(normalizedLearningTarget('zh-Hant'), 'ja');
    expect(
      ContentLanguage.fromTextbook({'id': '1971170190440288258'}).cacheKey,
      'ja:zh-Hans',
    );
    for (final row in [
      {'id': 'new'},
      {'id': '1971170190440288258', 'source_language': 'de'},
      {'id': 'new', 'source_language': 'en', 'explanation_language': 'invalid'},
    ]) {
      expect(() => ContentLanguage.fromTextbook(row), throwsFormatException);
    }
    final english = ContentLanguage.fromTextbook({
      'id': '9007199254740993',
      'source_language': 'en',
      'explanation_language': 'zh-Hant',
    });
    expect(english.ttsLocale, 'en-US');
    expect(
      () => english.requireSame(const ContentLanguage('ja', 'zh-Hant')),
      throwsFormatException,
    );
  });

  test(
    'English tokenization is lossless with contractions and punctuation',
    () {
      for (final source in [
        "Don't stop, it's state-of-the-art!",
        'Hello world.',
        'A single-word',
        '“We’re ready.”',
        'A\nlong\tline',
      ]) {
        final tokens = englishContentTokens(source);
        expect(tokens.join(), source);
      }
      expect(englishContentTokens("Don't re-enter."), [
        "Don't",
        ' ',
        're-enter',
        '.',
      ]);
    },
  );

  test('translated recognized question headings preserve every paragraph', () {
    final body = questionBody(
      '【Short reading】\nRead the passage.\n\nFirst paragraph.\n\nSecond paragraph.\n\nQuestion: What happened?',
    );
    expect(body.parts.single.text, 'First paragraph.\n\nSecond paragraph.');
    expect(body.footer, 'Question: What happened?');
    const unknown = '【Future format】\nInstruction\n\nBody';
    expect(questionBody(unknown).heading, unknown);
  });

  test(
    'additive migration repeats and settings do not change book or records',
    () async {
      final dir = await Directory.systemTemp.createTemp('language-migration-');
      final db = await databaseFactoryFfi.openDatabase(
        '${dir.path}/user.sqlite',
      );
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      await db.execute(
        'CREATE TABLE yzc_user_setting(id TEXT, user_id TEXT, update_time INTEGER)',
      );
      await db.execute(
        'CREATE TABLE yzc_textbook(id TEXT PRIMARY KEY, textbook TEXT)',
      );
      await db.execute(
        'CREATE TABLE yzc_user_position(user_id TEXT, textbook_id TEXT, update_time INTEGER)',
      );
      await db.execute('CREATE TABLE preserved_record(id TEXT, answer TEXT)');
      await db.insert('yzc_user_setting', {
        'id': 'settings',
        'user_id': 'test-user',
      });
      await db.insert('yzc_textbook', {
        'id': '1971170190440288258',
        'textbook': 'old',
      });
      await db.insert('yzc_user_position', {
        'user_id': 'test-user',
        'textbook_id': '1971170190440288258',
      });
      await db.insert('preserved_record', {
        'id': '9007199254740993',
        'answer': 'A',
      });
      final store = AppStore.forTesting(db, dir);
      await store.prepareLanguageSchema();
      expect((await store.setting())['ui_locale'], 'system');
      expect((await store.setting())['learning_target'], 'ja');
      await store.setSetting('learning_target', 'en');
      await store.setSetting('ui_locale', 'zh-Hant');
      await store.prepareLanguageSchema();
      await store.selectBook('other');
      expect((await store.setting())['learning_target'], 'en');
      expect((await store.setting())['ui_locale'], 'zh-Hant');
      expect(
        (await db.query('preserved_record')).single['id'],
        '9007199254740993',
      );
      expect((await db.query('yzc_textbook')).single['source_language'], 'ja');
      for (final ui in uiLocaleValues) {
        for (final target in learningTargetValues) {
          await store.setSetting('ui_locale', ui);
          await store.setSetting('learning_target', target);
          final saved = await store.setting();
          expect(saved['ui_locale'], ui);
          expect(saved['learning_target'], target);
          expect(
            (await db.query('yzc_textbook')).single['source_language'],
            'ja',
          );
        }
      }
      await store.setSetting('learning_target', 'en');
      await expectLater(
        store.setSetting('learning_target', 'de'),
        throwsArgumentError,
      );
      await store.setSetting('ui_locale', 'ja');
      expect((await store.setting())['learning_target'], 'en');
      await db.update('yzc_user_setting', {
        'ui_locale': 'bad',
        'learning_target': 'bad',
      });
      await store.prepareLanguageSchema();
      expect((await store.setting())['ui_locale'], 'system');
      expect((await store.setting())['learning_target'], 'ja');
      expect((await db.query('preserved_record')).single['answer'], 'A');
    },
  );

  test(
    'failed migration rolls back additive columns without losing records',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'language-migration-fail-',
      );
      final db = await databaseFactoryFfi.openDatabase(
        '${dir.path}/user.sqlite',
      );
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      await db.execute(
        'CREATE TABLE yzc_user_setting(id TEXT, user_id TEXT, update_time INTEGER)',
      );
      await db.insert('yzc_user_setting', {
        'id': 'preserve',
        'user_id': 'test-user',
      });
      final store = AppStore.forTesting(db, dir);
      await expectLater(
        store.prepareLanguageSchema(),
        throwsA(isA<DatabaseException>()),
      );
      expect((await db.query('yzc_user_setting')).single['id'], 'preserve');
      expect(
        (await db.rawQuery('PRAGMA table_info(yzc_user_setting)'))
            .map((r) => r['name']),
        isNot(contains('ui_locale')),
      );
      await db.execute('CREATE TABLE yzc_textbook(id TEXT PRIMARY KEY)');
      await store.prepareLanguageSchema();
      expect((await store.setting())['learning_target'], 'ja');
    },
  );

  test(
    'production validator accepts missing legacy columns and rejects conflicts',
    () async {
      final dir = await Directory.systemTemp.createTemp('language-validator-');
      final local = await databaseFactoryFfi.openDatabase(
        '${dir.path}/local.sqlite',
      );
      final source = await databaseFactoryFfi.openDatabase(
        '${dir.path}/source.sqlite',
      );
      addTearDown(() async {
        await source.close();
        await local.close();
        await dir.delete(recursive: true);
      });
      final script = await File('assets/database/init.sql').readAsString();
      for (final sql
          in script
              .replaceAll(RegExp(r'^--.*$', multiLine: true), '')
              .split(';')) {
        if (sql.trim().isNotEmpty) await local.execute(sql);
      }
      for (final table in ['yzc_textbook', ...textbookContentTables]) {
        var sql =
            (await local.rawQuery(
                  "SELECT sql FROM sqlite_master WHERE name=?",
                  [table],
                )).single['sql']
                as String;
        if (table == 'yzc_textbook') {
          sql = sql
              .replaceAll(RegExp(r'\s*`source_language` TEXT,'), '')
              .replaceAll(RegExp(r'\s*`explanation_language` TEXT,'), '');
        }
        await source.execute(sql);
      }
      const id = '1971170190440288258';
      await source.insert('yzc_textbook', {'id': id});
      final package = Directory('${dir.path}/package');
      await Directory('${package.path}/mp3').create(recursive: true);
      final resources = Resources(AppStore.forTesting(local, dir));
      await resources.validateForTesting(source, id, package.path);
      await expectLater(
        resources.validateForTesting(
          source,
          id,
          package.path,
          catalog: {
            'id': id,
            'source_language': 'en',
            'explanation_language': 'zh-Hans',
          },
        ),
        throwsFormatException,
      );
      await source.update('yzc_textbook', {'id': 'new'});
      await expectLater(
        resources.validateForTesting(source, 'new', package.path),
        throwsFormatException,
      );
    },
  );
  test('legacy ZIP install, catalog refresh and failed replacement preserve installed data', () async {
    final dir = await Directory.systemTemp.createTemp('language-install-');
    final local = await databaseFactoryFfi.openDatabase(
      '${dir.path}/local.sqlite',
    );
    final sourcePath = '${dir.path}/source.sqlite';
    final source = await databaseFactoryFfi.openDatabase(sourcePath);
    addTearDown(() async {
      await local.close();
      await dir.delete(recursive: true);
    });
    final script = await File('assets/database/init.sql').readAsString();
    for (final sql
        in script
            .replaceAll(RegExp(r'^--.*$', multiLine: true), '')
            .split(';')) {
      if (sql.trim().isNotEmpty) await local.execute(sql);
    }
    for (final table in ['yzc_textbook', ...textbookContentTables]) {
      var sql =
          (await local.rawQuery("SELECT sql FROM sqlite_master WHERE name=?", [
                table,
              ])).single['sql']
              as String;
      if (table == 'yzc_textbook') {
        sql = sql
            .replaceAll(RegExp(r'\s*`source_language` TEXT,'), '')
            .replaceAll(RegExp(r'\s*`explanation_language` TEXT,'), '');
      }
      await source.execute(sql);
    }
    const id = '1971170190440288258';
    await source.insert('yzc_textbook', {'id': id, 'ver': '1'});
    await source.insert('yzc_unit', {'id': 'unit', 'textbook_id': id});
    await source.insert('yzc_lessons', {
      'id': 'lesson',
      'textbook_id': id,
      'unit_id': 'unit',
      'lesson': 'L1',
    });
    await source.insert('yzc_ai_question', {
      'id': 'question',
      'textbook_id': id,
      'unit_id': 'unit',
      'lessons_id': 'lesson',
      'lesson': 'L1',
      'question': '日本語',
      'relation': 'word',
    });
    await source.close();
    final databaseBytes = await File(sourcePath).readAsBytes();
    final archive = Archive()
      ..addFile(
        ArchiveFile('legacy/data.sqlite', databaseBytes.length, databaseBytes),
      )
      ..addFile(ArchiveFile('legacy/mp3/sample.mp3', 3, [1, 2, 3]));
    final zip = ZipEncoder().encode(archive);
    final transfer = _FixtureTransfer(zip, {
      'id': id,
      'ver': '1',
      'sfky': '1',
      'resource_file': 'legacy.zip',
    });
    final store = AppStore.forTesting(local, dir);
    await local.insert('yzc_user_setting', {
      'id': 'settings',
      'user_id': 'test-user',
      'learning_target': 'en',
      'ui_locale': 'ja',
    });
    await local.insert('yzc_user_learn', {
      'id': 'progress',
      'user_id': 'test-user',
      'textbook_id': id,
      'lessons_id': 'lesson',
    });
    final resources = Resources(
      store,
      transfer: transfer,
      password: () async => '',
      base: Uri.parse('https://fixture.invalid/'),
    );
    await resources.download(id);
    final installed = (await local.query('yzc_textbook')).single;
    expect(installed['source_language'], 'ja');
    expect(installed['explanation_language'], 'zh-Hans');
    expect((await resources.installation(id))?['status'], 'ready');
    transfer.catalog = {
      ...transfer.catalog,
      'ver': '2',
      'source_language': 'en',
      'explanation_language': 'zh-Hant',
    };
    await resources.refreshTextbooks();
    expect((await local.query('yzc_textbook')).single, installed);
    await expectLater(resources.download(id), throwsFormatException);
    expect((await local.query('yzc_textbook')).single, installed);
    expect((await store.setting())['learning_target'], 'en');
    expect((await local.query('yzc_user_learn')).single['id'], 'progress');
    transfer.catalog = {
      ...transfer.catalog,
      'source_language': 'ja',
      'explanation_language': 'zh-Hans',
    };
    final failing = Resources(
      store,
      transfer: transfer,
      password: () async => '',
      base: Uri.parse('https://fixture.invalid/'),
      onCheckpoint: (point) async {
        if (point == 'before-db-commit')
          throw StateError('injected transaction failure');
      },
    );
    await expectLater(failing.download(id), throwsStateError);
    expect((await local.query('yzc_textbook')).single, installed);
    expect((await resources.installation(id))?['status'], 'ready');
    expect((await local.query('yzc_user_learn')).single['id'], 'progress');
    expect(
      await File('${dir.path}/resources/legacy/mp3/sample.mp3').exists(),
      isTrue,
    );
  });
}

/// Replace only the network; extraction, validation, install and rollback use
/// the production implementation and an actual ZIP with missing language columns.
class _FixtureTransfer extends ResourceTransfer {
  _FixtureTransfer(this.zip, this.catalog)
    : super(freeSpace: () async => 1024 * 1024 * 1024);
  final List<int> zip;
  Map<String, Object?> catalog;
  @override
  Future<Object?> json(
    Uri uri, {
    ResourceTask? task,
    ResourceProgress? report,
    int limit = 8 * 1024 * 1024,
  }) async => [catalog];
  @override
  Future<String> download(
    Uri uri,
    File file,
    ResourceTask task,
    ResourceProgress report, {
    String? expectedHash,
  }) async {
    task.check();
    await file.writeAsBytes(zip, flush: true);
    return sha256.convert(zip).toString();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/data.dart';
import '../lib/resources.dart';

Future<void> _executeScript(Database database, String script) async {
  final statement = StringBuffer();
  for (final line in const LineSplitter().convert(script)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('--')) continue;
    statement.writeln(line);
    if (trimmed.endsWith(';')) {
      await database.execute(statement.toString());
      statement.clear();
    }
  }
}

Future<Database> _sourceFrom(
  Database local,
  String path, {
  bool legacyMediaColumns = false,
  bool extraColumns = false,
}) async {
  final source = await databaseFactoryFfi.openDatabase(path);
  for (final table in ['yzc_textbook', ...textbookContentTables]) {
    if (!legacyMediaColumns || table == 'yzc_textbook') {
      final row = (await local.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        [table],
      )).single;
      await source.execute(row['sql']! as String);
      if (extraColumns)
        await source.execute(
          'ALTER TABLE "$table" ADD COLUMN "future_optional" TEXT',
        );
    } else {
      final definitions = <String>[];
      for (final column in await local.rawQuery('PRAGMA table_info($table)')) {
        final name = column['name']! as String;
        if (optionalTextbookContentColumns.contains(name)) continue;
        definitions.add(
          '"$name" ${column['type']}${column['notnull'] == 1 ? ' NOT NULL' : ''}${column['pk'] == 1 ? ' PRIMARY KEY' : ''}',
        );
      }
      if (extraColumns) definitions.add('"future_optional" TEXT');
      await source.execute('CREATE TABLE "$table" (${definitions.join(',')})');
    }
  }
  return source;
}

Map<String, Object?> _question(
  String id, {
  String? unit = 'unit',
  String? lessonId = 'lesson',
  String? lesson = 'L1',
  Object? options = '["A:甲","B:乙"]',
  Object? answer = 'A',
  String relation = 'word',
  String? mediaType,
  String? mediaSrc,
  String? mediaConfig,
}) => {
  'id': id,
  'textbook_id': 'book',
  'unit_id': unit,
  'lessons_id': lessonId,
  'lesson': lesson,
  'question': '题干 $id',
  'options': options,
  'answer': answer,
  'relation': relation,
  'media_type': mediaType ?? 'text',
  'media_src': mediaSrc,
  'media_config': mediaConfig,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'production validation degrades local faults and filters unsafe rows',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'yzc-import-test-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final local = await databaseFactoryFfi.openDatabase(
        '${temporary.path}/local.sqlite',
      );
      addTearDown(local.close);
      await _executeScript(
        local,
        await File('assets/database/init.sql').readAsString(),
      );
      final source = await _sourceFrom(
        local,
        '${temporary.path}/source.sqlite',
      );
      addTearDown(source.close);

      await source.insert('yzc_textbook', {'id': 'book', 'textbook': '测试教材'});
      await source.insert('yzc_unit', {'id': 'unit', 'textbook_id': 'book'});
      await source.insert('yzc_lessons', {
        'id': 'lesson',
        'textbook_id': 'book',
        'unit_id': 'unit',
        'lesson': 'L1',
      });
      await source.insert('yzc_ai_question', _question('valid'));
      await source.insert(
        'yzc_ai_question',
        _question('open', options: ' ', answer: null),
      );
      await source.insert(
        'yzc_ai_question',
        _question('bad-json', options: '{bad json'),
      );
      await source.insert(
        'yzc_ai_question',
        _question('orphan', lessonId: 'missing'),
      );
      await source.insert(
        'yzc_ai_question',
        _question('conflict', unit: 'other'),
      );
      await source.insert(
        'yzc_ai_question',
        _question('nullable-redundancy', unit: null, lesson: null),
      );
      await source.insert(
        'yzc_ai_question',
        _question('blank-redundancy', unit: '  ', lesson: '\t'),
      );
      await source.insert('yzc_lessons', {
        'id': 'bad-lesson',
        'textbook_id': 'book',
        'unit_id': 'missing-unit',
        'lesson': 'L2',
      });
      await source.insert('yzc_words', {
        'id': 'cascaded-word',
        'textbook_id': 'book',
        'unit_id': 'missing-unit',
        'lessons_id': 'bad-lesson',
        'lesson': 'L2',
        'word': '应隔离',
      });
      await source.insert(
        'yzc_ai_question',
        _question(
          'missing-media',
          mediaType: 'audio',
          mediaSrc: 'mp3/missing.mp3',
        ),
      );
      final mediaConfig = jsonEncode({
        'version': 1,
        'interactive': true,
        'hotspots': [
          {
            'id': 'valid-hotspot',
            'label': '读音',
            'audio_src': 'missing-hotspot.mp3',
            'bounds': {'x': 0, 'y': 0, 'width': .5, 'height': .5},
          },
          {
            'id': 'bad-hotspot',
            'label': '坏',
            'audio_src': '../bad.mp3',
            'bounds': {'x': 0, 'y': 0, 'width': .5, 'height': .5},
          },
        ],
      });
      await source.insert(
        'yzc_ai_question',
        _question(
          'partial-hotspots',
          options: '',
          answer: '',
          mediaType: 'interactive_image',
          mediaSrc: 'mp3/image.png',
          mediaConfig: mediaConfig,
        ),
      );
      final package = Directory('${temporary.path}/package');
      await Directory('${package.path}/mp3').create(recursive: true);
      await File('${package.path}/mp3/image.png').writeAsBytes([0]);

      final validation = await Resources(AppStore.forTesting(local, temporary))
          .validateForTesting(source, 'book', package.path);

      expect(
        validation.skippedRows['yzc_ai_question'],
        containsAll(['orphan', 'conflict']),
      );
      expect(validation.skippedRows['yzc_lessons'], contains('bad-lesson'));
      expect(validation.skippedRows['yzc_words'], contains('cascaded-word'));
      expect(
        shouldImportResourceRow(validation, 'yzc_ai_question', {
          'id': 'orphan',
        }),
        isFalse,
      );
      expect(
        shouldImportResourceRow(validation, 'yzc_ai_question', {
          'id': 'bad-json',
        }),
        isTrue,
      );
      expect(
        shouldImportResourceRow(validation, 'yzc_ai_question', {
          'id': 'nullable-redundancy',
        }),
        isTrue,
      );
      expect(
        shouldImportResourceRow(validation, 'yzc_ai_question', {
          'id': 'blank-redundancy',
        }),
        isTrue,
      );
      expect(
        validation.issues.any(
          (issue) =>
              issue.location.contains('bad-json') &&
              issue.message.contains('排除自动评分'),
        ),
        isTrue,
      );
      expect(
        validation.issues.any(
          (issue) => issue.location.contains('missing-media'),
        ),
        isTrue,
      );
      expect(
        validation.issues.any(
          (issue) =>
              issue.location.contains('bad-hotspot') ||
              issue.message.contains('热点 2'),
        ),
        isTrue,
      );
      expect(
        validation.issues.any(
          (issue) =>
              issue.location.contains('valid-hotspot') &&
              issue.message.contains('缺少音频'),
        ),
        isTrue,
      );
    },
  );

  test('package identity conflict remains fatal', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'yzc-identity-test-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final local = await databaseFactoryFfi.openDatabase(
      '${temporary.path}/local.sqlite',
    );
    addTearDown(local.close);
    await _executeScript(
      local,
      await File('assets/database/init.sql').readAsString(),
    );
    final source = await _sourceFrom(local, '${temporary.path}/source.sqlite');
    addTearDown(source.close);
    await source.insert('yzc_textbook', {'id': 'other'});
    final package = Directory('${temporary.path}/package');
    await Directory('${package.path}/mp3').create(recursive: true);
    await expectLater(
      Resources(AppStore.forTesting(local, temporary))
          .validateForTesting(source, 'book', package.path),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'all isolated learning rows fail before replacing old content',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'yzc-all-isolated-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final local = await databaseFactoryFfi.openDatabase(
        '${temporary.path}/local.sqlite',
      );
      addTearDown(local.close);
      await _executeScript(
        local,
        await File('assets/database/init.sql').readAsString(),
      );
      await local.insert('yzc_words', {
        'id': 'old-safe',
        'textbook_id': 'book',
      });
      final source = await _sourceFrom(
        local,
        '${temporary.path}/source.sqlite',
      );
      addTearDown(source.close);
      await source.insert('yzc_textbook', {'id': 'book'});
      await source.insert('yzc_unit', {'id': 'unit', 'textbook_id': 'book'});
      await source.insert('yzc_lessons', {
        'id': 'bad-lesson',
        'textbook_id': 'book',
        'unit_id': 'missing',
        'lesson': 'L1',
      });
      await source.insert('yzc_words', {
        'id': 'only-new-row',
        'textbook_id': 'book',
        'unit_id': 'missing',
        'lessons_id': 'bad-lesson',
        'lesson': 'L1',
      });
      final package = Directory('${temporary.path}/package');
      await Directory('${package.path}/mp3').create(recursive: true);
      await expectLater(
        Resources(AppStore.forTesting(local, temporary))
            .validateForTesting(source, 'book', package.path),
        throwsA(isA<FormatException>()),
      );
      expect(
        await local.query('yzc_words', where: 'id=?', whereArgs: ['old-safe']),
        hasLength(1),
      );
    },
  );

  test(
    'legacy missing media columns and future optional columns are accepted',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'yzc-schema-compat-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final local = await databaseFactoryFfi.openDatabase(
        '${temporary.path}/local.sqlite',
      );
      addTearDown(local.close);
      await _executeScript(
        local,
        await File('assets/database/init.sql').readAsString(),
      );
      final source = await _sourceFrom(
        local,
        '${temporary.path}/source.sqlite',
        legacyMediaColumns: true,
        extraColumns: true,
      );
      addTearDown(source.close);
      await source.insert('yzc_textbook', {'id': 'book'});
      final package = Directory('${temporary.path}/package');
      await Directory('${package.path}/mp3').create(recursive: true);
      final validation = await Resources(AppStore.forTesting(local, temporary))
          .validateForTesting(source, 'book', package.path);
      expect(validation.issues, isEmpty);
    },
  );

  test('empty update cannot erase existing learning content', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'yzc-empty-update-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final local = await databaseFactoryFfi.openDatabase(
      '${temporary.path}/local.sqlite',
    );
    addTearDown(local.close);
    await _executeScript(
      local,
      await File('assets/database/init.sql').readAsString(),
    );
    await local.insert('yzc_words', {'id': 'old-safe', 'textbook_id': 'book'});
    final source = await _sourceFrom(local, '${temporary.path}/source.sqlite');
    addTearDown(source.close);
    await source.insert('yzc_textbook', {'id': 'book'});
    final package = Directory('${temporary.path}/package');
    await Directory('${package.path}/mp3').create(recursive: true);
    await expectLater(
      Resources(AppStore.forTesting(local, temporary))
          .validateForTesting(source, 'book', package.path),
      throwsA(isA<FormatException>()),
    );
    expect(
      await local.query('yzc_words', where: 'id=?', whereArgs: ['old-safe']),
      hasLength(1),
    );
  });

  test('import projection defaults null and blank media types', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'yzc-media-default-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final local = await databaseFactoryFfi.openDatabase(
      '${temporary.path}/local.sqlite',
    );
    addTearDown(local.close);
    await _executeScript(
      local,
      await File('assets/database/init.sql').readAsString(),
    );
    const localColumns = {
      'id',
      'textbook_id',
      'media_type',
      'media_src',
      'media_config',
    };
    final nullSource = <String, Object?>{
      'id': 'null-media',
      'textbook_id': 'book',
      'media_type': null,
    };
    final blankSource = <String, Object?>{
      'id': 'blank-media',
      'textbook_id': 'book',
      'media_type': ' \t ',
    };
    final normalizedNull = normalizeResourceRowForImport(
      nullSource,
      localColumns,
    );
    final normalizedBlank = normalizeResourceRowForImport(
      blankSource,
      localColumns,
    );
    expect(nullSource['media_type'], isNull);
    expect(blankSource['media_type'], ' \t ');
    expect(normalizedNull, containsPair('media_type', 'text'));
    expect(normalizedBlank, containsPair('media_type', 'text'));
    expect(normalizedNull, containsPair('media_src', null));
    expect(normalizedNull, containsPair('media_config', null));
    await local.insert('yzc_ai_question', normalizedNull);
    await local.insert('yzc_ai_question', normalizedBlank);
    final inserted = await local.query(
      'yzc_ai_question',
      columns: ['id', 'media_type'],
      orderBy: 'id',
    );
    expect(inserted, [
      {'id': 'blank-media', 'media_type': 'text'},
      {'id': 'null-media', 'media_type': 'text'},
    ]);
  });
}

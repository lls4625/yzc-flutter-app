import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/study_room/host_contracts.dart';
import '../lib/study_room/word_lookup/feature/repository.dart';
import '../lib/study_room/grammar_lookup/feature/repository.dart';

class LookupHost implements StudyRoomHost {
  LookupHost(this.database);
  @override
  final Database database;
  String target = 'ja';
  int targetReads = 0;
  @override
  String get learningTarget {
    targetReads++;
    return target;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late LookupHost host;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE yzc_textbook(id TEXT PRIMARY KEY, textbook TEXT, volume TEXT, sort INTEGER, source_language TEXT, explanation_language TEXT)',
    );
    await db.execute(
      'CREATE TABLE yzc_lessons(id TEXT PRIMARY KEY, textbook_id TEXT, lesson TEXT, num INTEGER, title TEXT)',
    );
    await db.execute(
      'CREATE TABLE yzc_words(id TEXT PRIMARY KEY, textbook_id TEXT, lessons_id TEXT, word TEXT, kana TEXT, kanji TEXT, definition TEXT, sort INTEGER)',
    );
    await db.execute(
      'CREATE TABLE yzc_grammar(id TEXT PRIMARY KEY, textbook_id TEXT, lessons_id TEXT, pid TEXT, type TEXT, sort INTEGER, content TEXT, definition TEXT, connection TEXT, example TEXT, example_definition TEXT, tip TEXT)',
    );
    for (final language in ['ja', 'en']) {
      await db.insert('yzc_textbook', {
        'id': language,
        'textbook': 'Original $language',
        'source_language': language,
        'explanation_language': 'zh-Hant',
      });
      await db.insert('yzc_lessons', {
        'id': 'lesson-$language',
        'textbook_id': language,
        'lesson': '1',
        'num': 1,
      });
      await db.insert('yzc_words', {
        'id': 'word-$language',
        'textbook_id': language,
        'lessons_id': 'lesson-$language',
        'word': language == 'ja' ? '共有' : 'shared!',
        'definition': 'shared meaning 100%',
      });
      await db.insert('yzc_grammar', {
        'id': 'grammar-$language',
        'textbook_id': language,
        'lessons_id': 'lesson-$language',
        'type': '1',
        'content': language == 'ja' ? 'なければならない' : 'must',
        'definition': 'shared necessity explanation',
        'example_definition': 'example translation',
      });
    }
    host = LookupHost(db);
  });
  tearDown(() => db.close());
  test('word searches retain both packages under either target and preserve exact metadata', () async {
    final repo = WordLookupRepository(host);
    for (final target in ['ja', 'en']) {
      host.target = target;
      final rows = await repo.search('shared');
      expect(rows.map((r) => r['textbook_id']).toSet(), {'ja', 'en'});
      expect(
        rows.singleWhere((r) => r['textbook_id'] == 'en')['word'],
        'shared!',
      );
      expect(rows.map((r) => r['source_language']).toSet(), {'ja', 'en'});
      expect((await repo.search('%')).length, 2);
      expect(await repo.search("' OR 1=1 --"), isEmpty);
    }
    expect(host.targetReads, 0);
  });
  test('grammar titles and package explanations search across targets without old-index identity spoofing', () async {
    final repo = GrammarLookupRepository(host);
    for (final target in ['en', 'ja']) {
      host.target = target;
      final meanings = await repo.search('necessity');
      expect(meanings.rows.map((r) => r['textbook_id']).toSet(), {'ja', 'en'});
      expect((await repo.search('must')).rows.single['textbook_id'], 'en');
      final examples = (await repo.search('example translation')).rows;
      expect(examples.length, 2);
      expect(
        examples.every((row) => row['lookup_field'] == 'example_definition'),
        isTrue,
      );
      expect(
        meanings.rows.every((row) => row['lookup_field'] == 'definition'),
        isTrue,
      );
      for (final row in meanings.rows) {
        expect(row['lookup_evidence_id'], isEmpty);
        expect(
          (await repo.tree(row)).single['explanation_language'],
          'zh-Hant',
        );
      }
    }
    expect(host.targetReads, 0);
  });
}

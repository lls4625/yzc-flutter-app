import '../../host_contracts.dart';
import '../../jlpt/feature/storage.dart';
import 'models.dart';

class JlptRepository {
  JlptRepository(StudyRoomHost host) : _store = JlptStorage(host, 'practice');
  final JlptStorage _store;
  Future<String?> mediaPath(String level, String reference) =>
      _store.host.resources.mediaPath(level, reference);
  Future<String> loadLevel() => _store.loadLevel();
  Future<void> saveLevel(String level) => _store.saveLevel(level);
  Future<Bank> load(String level) async {
    final bank = Bank(await _store.load(level));
    if (bank.papers.isEmpty) throw StateError('当前等级暂无题目');
    return bank;
  }
  Future<void> create(Attempt attempt) => _store.create(attempt.snapshot, attempt.progress);
  Future<void> save(String id, String progress, bool submitted) => _store.save(id, progress, submitted);
  Future<List<Json>> history() => _store.history();
  Future<List<Json>> mistakes() => _store.mistakes();
  Future<Attempt> restore(String id) async {
    final saved = await _store.restore(id);
    final attempt = Attempt(saved.snapshot, saved.progress);
    if (attempt.questions.isEmpty || attempt.position < 0 || attempt.position >= attempt.questions.length) {
      throw const FormatException('进度记录损坏');
    }
    return attempt;
  }
  Future<void> close() async {}
}

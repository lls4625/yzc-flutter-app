import 'dart:convert';
import 'models.dart';
import 'samples.dart';

// This repository never receives a host, database, user ID or filesystem path.
class JlptRepository {
  final Map<String, Attempt> _attempts = {};
  final Map<String, Json> _mistakes = {};
  String _level = 'N5';
  Json _copy(Json value) => jsonDecode(jsonEncode(value)) as Json;
  Future<String> loadLevel() async => _level;
  Future<void> saveLevel(String level) async { _level = level; }
  Future<Bank> load(String level) async => demoBank();
  Future<void> create(Attempt a) async {
    _attempts[a.id] = Attempt(_copy(a.snapshot), _copy(a.progress));
  }
  Future<void> save(String id, String payload, bool submitted) async {
    final old = _attempts[id]!;
    if (old.submitted) return;
    final a = Attempt(old.snapshot, jsonDecode(payload) as Json);
    _attempts[id] = a;
    if (!submitted) return;
    for (final q in a.questions) {
      if (!a.answers.containsKey(q.id)) continue;
      if (!a.correct(q)) {
        _mistakes[q.id] = {'question': _copy(q.data),
          'wrong_count': ((_mistakes[q.id]?['wrong_count'] as int?) ?? 0) + 1};
      } else if (!a.revealed.contains(q.id)) {
        _mistakes.remove(q.id);
      }
    }
  }
  Future<List<Json>> history() async => [for (final a in _attempts.values.toList().reversed)
    {'id': a.id, 'title': a.title, 'submitted': a.submitted ? 1 : 0}];
  Future<List<Json>> mistakes() async => _mistakes.values.map(_copy).toList();
  Future<Attempt> restore(String id) async {
    final a = _attempts[id]!;
    return Attempt(_copy(a.snapshot), _copy(a.progress));
  }
  void reset() { _attempts.clear(); _mistakes.clear(); _level = 'N5'; }
  Future<void> close() async {}
}

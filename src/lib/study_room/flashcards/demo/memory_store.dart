import 'models.dart';

class FlashDemoMemoryStore {
  Map<String, dynamic> _settings = {};
  final _mastery = <FlashDemoDirection, Map<String, ({bool known, int time})>>{};
  FlashDemoSession? _session;
  Future<void> open() async {}
  Future<Map<String, dynamic>> settings() async => Map.of(_settings);
  Future<void> saveSettings(Map<String, dynamic> value) async {
    _settings = Map.of(value);
  }

  Future<Map<String, ({bool known, int time})>> mastery(
    FlashDemoDirection direction,
  ) async => Map.of(_mastery[direction] ?? {});
  Future<FlashDemoSession?> draft() async => _session;
  Future<void> begin(FlashDemoSession session) async {
    _session = session;
  }

  Future<void> discard() async {
    _session = null;
  }

  Future<void> mark(FlashDemoSession before, FlashDemoSession after, bool known) async {
    if (_session?.id != before.id || _session?.index != before.index) {
      throw StateError('复习进度已变化，请返回设置重新载入');
    }
    (_mastery[before.direction] ??= {})[before.words[before.index].key] = (
      known: known,
      time: DateTime.now().millisecondsSinceEpoch,
    );
    _session = after;
  }

  Future<void> close() async {
    _settings.clear();
    _mastery.clear();
    _session = null;
  }
}

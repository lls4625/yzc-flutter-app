part of 'page.dart';

typedef RowData = DictationDemoRow;
String textOf(RowData row, String key) => row[key]?.toString() ?? '';
String featureError(Object? error, {String fallback = '操作失败，请重试'}) =>
    error is StateError ? error.message.toString() : fallback;
Future<void> perform(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        GlassSnackBar(content: Text(featureError(e))),
      );
    }
  }
}

/// All settings, targets and routes belong to this single demo session.
class DictationDemoController {
  final catalog = DictationDemoCatalog();
  final navigator = GlobalKey<NavigatorState>();
  final selectionKey = GlobalKey<_DictationDemoSelectionPageState>();
  final practiceKey = GlobalKey<_DictationPageState>();
  final selectionTarget = GlobalKey();
  final orderTarget = GlobalKey();
  final rulesTarget = GlobalKey();
  final startTarget = GlobalKey();
  final audioTarget = GlobalKey();
  final slotsTarget = GlobalKey();
  final choicesTarget = GlobalKey();
  final nextTarget = GlobalKey();
  final resetTarget = GlobalKey();
  final Map<String, Object> _settings = {};
  bool guided = true;

  String get selectedBook => _settings['book'] as String? ?? '';
  bool get pauseEach => _settings['pause_each'] == true;
  bool get randomOrder => _settings['random_order'] == true;
  int get repeats => _settings['repeats'] as int? ?? 1;
  int get interval => _settings['interval'] as int? ?? 1;

  Future<void> load() async {
    await catalog.load();
    _settings.putIfAbsent('book', () => '');
    if (selectedBook.isEmpty) {
      _settings['book'] = textOf((await catalog.textbooks()).single, 'id');
    }
  }

  Future<void> setting(String key, Object value) async {
    final valid = switch (key) {
      'book' => value is String &&
          (await catalog.textbooks()).any((book) => textOf(book, 'id') == value),
      'pause_each' || 'random_order' => value is bool,
      'repeats' => value is int && value >= 1 && value <= 5,
      'interval' => value is int && value >= 1 && value <= 10,
      _ => false,
    };
    if (!valid) throw ArgumentError('未知演示设置');
    _settings[key] = value;
  }

  Future<void> reset() async {
    _settings.clear();
    await load();
  }
}

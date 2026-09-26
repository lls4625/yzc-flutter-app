import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../foundation/native_audio_transport.dart';
import 'demo.dart';
import 'memory_store.dart';
import 'models.dart';

typedef FlashDemoRow = Map<String, Object?>;

enum FlashDemoStage { setup, review, result }

class FlashDemoController extends ChangeNotifier {
  FlashDemoController();
  final store = FlashDemoMemoryStore();
  FlashDemoData? _demoData;
  bool busy = false, flipped = false, _opened = false, _disposed = false;
  Future<void>? _pending;
  String? error;
  FlashDemoStage stage = FlashDemoStage.setup;
  FlashDemoDirection direction = FlashDemoDirection.japanese;
  bool onlyWeak = false;
  bool randomOrder = false;
  int limit = 10, skipped = 0;
  String bookId = '', version = '';
  Set<String> lessonIds = {};
  List<FlashDemoRow> books = [], lessons = [];
  List<FlashDemoWord> words = [];
  Map<String, ({bool known, int time})> mastery = {};
  FlashDemoSession? session;
  int? _answerIndex;
  Timer? _advanceTimer;
  bool advancing = false;
  bool get awaitingNext => _answerIndex != null;
  int get reviewIndex => _answerIndex ?? session!.index;
  bool get canRate =>
      stage == FlashDemoStage.review &&
      hasDraft &&
      !awaitingNext &&
      !busy &&
      !advancing;
  bool get hasDraft => session != null && !session!.complete;
  List<FlashDemoWord> _buildQueue() {
    final items = words
        .where((w) => !onlyWeak || mastery[w.key]?.known == false)
        .toList();
    if (randomOrder) items.shuffle();
    return limit == 0 ? items : items.take(limit).toList();
  }

  final _audio = NativeAudioTransport.instance;
  final _audioIdentity = 'flashcards-demo:${DateTime.now().microsecondsSinceEpoch}';
  int _audioRequest = 0;
  bool _audioStarting = false;

  // The guide waits for the owned sample recording, never another module's audio.
  bool get demoPronunciationActive =>
      (_audioStarting || (_audio.lesson == _audioIdentity && _audio.active));
  String? get demoPronunciationError =>
      _audio.lesson == _audioIdentity ? _audio.error : null;

  Future<void> stopDemoPronunciation() async {
    _audioRequest++;
    if (_audio.lesson == _audioIdentity) await _audio.stop();
  }

  Future<void> resetDemo() => _run(() async {
    _clearAnswer();
    await store.close();
    await store.open();
    session = null;
    mastery = {};
    direction = FlashDemoDirection.japanese;
    onlyWeak = false;
    randomOrder = false;
    limit = 0;
    stage = FlashDemoStage.setup;
    await _loadLessons(newBook: true);
  });

  Future<void> playPronunciation() async {
    if (_disposed ||
        _audioStarting ||
        _audio.stopping ||
        busy ||
        advancing ||
        stage != FlashDemoStage.review)
      return;
    _audioStarting = true;
    final stopRevision = _audio.stopRevision;
    final request = ++_audioRequest;
    final word = session!.words[reviewIndex];
    try {
      await _validateSession();
      final path = await _demoData!.pronunciation(word);
      if (_disposed ||
          request != _audioRequest ||
          stopRevision != _audio.stopRevision ||
          stage != FlashDemoStage.review)
        return;
      await _audio.start({
        'lesson': _audioIdentity,
        'title': '${word.japanese} · 闪卡复习',
        'albumTitle': '闪卡复习',
        'words': true,
        'batch': false,
        'speed': 1.0,
        'repeat': 1,
        'intervalSteps': 0,
        'clips': [
          {'id': word.key, 'path': path},
        ],
        'startIndex': 0,
      });
      if (_disposed || request != _audioRequest) {
        if (_audio.lesson == _audioIdentity) await _audio.stop();
      } else if (error != null) {
        error = null;
        notifyListeners();
      }
    } catch (e) {
      if (!_disposed && request == _audioRequest) {
        error = e is StateError ? e.message.toString() : '单词读音播放失败，请重试';
        notifyListeners();
      }
    } finally {
      _audioStarting = false;
    }
  }

  void _stopPronunciation() {
    _audioRequest++;
    if (_audio.lesson == _audioIdentity) {
      unawaited(
        _audio.stop().catchError((Object e) {
          debugPrint('Flashcard audio stop failed: $e');
        }),
      );
    }
  }

  Future<void> _run(Future<void> Function() action) {
    if (busy || _disposed) return Future.value();
    busy = true;
    error = null;
    notifyListeners();
    return _pending = () async {
      try {
        await action();
      } catch (e) {
        error = e is StateError
            ? e.message.toString()
            : '演示数据处理失败，请重新播放。';
      } finally {
        busy = false;
        if (!_disposed) notifyListeners();
      }
    }();
  }

  Future<void> load() => _run(() async {
    if (!_opened) {
      await store.open();
      _opened = true;
    }
    final settings = await store.settings();
    direction = FlashDemoDirection.values.firstWhere(
      (d) => d.name == settings['direction'],
      orElse: () => FlashDemoDirection.japanese,
    );
    onlyWeak = settings['onlyWeak'] == true;
    randomOrder = settings['randomOrder'] == true;
    limit = [0, 10, 20].contains(settings['limit'])
        ? settings['limit'] as int
        : 10;
    bookId = settings['book'] as String? ?? '';
    lessonIds = ((settings['lessons'] as List?) ?? [])
        .whereType<String>()
        .toSet();
    session = await store.draft();
    await _loadLessons();
    _clearAnswer();
    stage = FlashDemoStage.setup;
  });

  Future<void> _loadLessons({bool newBook = false}) async {
    final initial = _demoData == null;
    final data = _demoData ??= await FlashDemoData.load();
    books = [data.book];
    lessons = [data.lesson];
    bookId = data.book['id'].toString();
    final valid = {data.lesson['id'].toString()};
    lessonIds = initial || newBook ? valid : lessonIds.intersection(valid);
  }

  Future<void> _loadSelectedWords() async {
    words = _demoData!.words(lessonIds);
    version = 'demo-v1';
    skipped = 0;
    mastery = await store.mastery(direction);
  }

  Map<String, dynamic> get _settings => {
    'direction': direction.name,
    'onlyWeak': onlyWeak,
    'randomOrder': randomOrder,
    'limit': limit,
    'book': bookId,
    'lessons': lessonIds.toList(),
  };
  Future<void> configure({
    FlashDemoDirection? nextDirection,
    bool? weak,
    bool? random,
    int? count,
    Set<String>? selectedLessons,
  }) async {
    if (busy || _disposed || stage != FlashDemoStage.setup) return;
    if (nextDirection != null) direction = nextDirection;
    if (weak != null) onlyWeak = weak;
    if (random != null) randomOrder = random;
    if (count != null) limit = count;
    if (selectedLessons != null) lessonIds = Set.of(selectedLessons);
    error = null;
    notifyListeners();
  }

  bool validateSelection() {
    final message = bookId.isEmpty
        ? '请先选择教材。'
        : lessonIds.isEmpty
        ? '请先选择需要复习的课程。'
        : null;
    if (message == null) return true;
    error = message;
    notifyListeners();
    return false;
  }

  void dismissError() {
    if (_disposed || error == null) return;
    error = null;
    notifyListeners();
  }

  Future<void> start() => _run(() async {
    await _loadSelectedWords();
    final queue = _buildQueue();
    if (words.isEmpty) {
      throw StateError('当前所选课程没有可用单词，请选择其他课程。');
    }
    if (queue.isEmpty) {
      throw StateError(
        onlyWeak
            ? '当前所选课程在${direction.label}方向没有标记为“不熟”的单词，可切换为“全部单词”或选择其他课程。'
            : '当前所选课程没有可复习单词，请选择其他课程。',
      );
    }
    await store.saveSettings(_settings);
    final next = FlashDemoSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      direction: direction,
      words: queue,
      version: version,
    );
    await store.begin(next);
    session = next;
    _clearAnswer();
    stage = FlashDemoStage.review;
  });

  Future<void> _validateSession() async {
    final data = _demoData;
    if (data == null || session == null || session!.words.any((word) =>
        word.bookId != data.book['id'].toString() ||
        word.lessonId != data.lesson['id'].toString())) {
      throw StateError('演示样例已不可用，请重新播放。');
    }
  }

  Future<void> resume() => _run(() async {
    session = await store.draft();
    if (!hasDraft) throw StateError('没有未完成的复习');
    await _validateSession();
    _clearAnswer();
    stage = FlashDemoStage.review;
  });
  Future<void> mark(bool known) => _run(() async {
    if (stage != FlashDemoStage.review || awaitingNext || advancing || !hasDraft)
      return;
    _stopPronunciation();
    final stayOnAnswer = !known && !flipped;
    final ratedIndex = session!.index;
    await _validateSession();
    final next = session!.marked(known);
    await store.mark(session!, next, known);
    session = next;
    if (stayOnAnswer) {
      // The mark is already committed; display the rated word until Next.
      _answerIndex = ratedIndex;
      flipped = true;
    } else {
      _advance();
    }
  });
  void _clearAnswer() {
    _stopPronunciation();
    _answerIndex = null;
    flipped = false;
    _advanceTimer?.cancel();
    advancing = false;
  }

  void _advance() {
    _clearAnswer();
    stage = session!.complete ? FlashDemoStage.result : FlashDemoStage.review;
    if (stage == FlashDemoStage.review && !_disposed) {
      // Once direct front-side rating is enabled, a double tap must not rate
      // the next unseen word after the first transaction has already finished.
      advancing = true;
      _advanceTimer = Timer(const Duration(milliseconds: 300), () {
        advancing = false;
        if (!_disposed) notifyListeners();
      });
    }
  }

  void next() {
    if (!awaitingNext || busy) return;
    _advance();
    notifyListeners();
  }

  Future<void> retryWeak() => _run(() async {
    if (stage != FlashDemoStage.result || session!.weak.isEmpty) return;
    await _validateSession();
    final next = FlashDemoSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      direction: session!.direction,
      words: session!.weak,
      version: session!.version,
    );
    await store.begin(next);
    session = next;
    _clearAnswer();
    stage = FlashDemoStage.review;
  });
  Future<void> discard() => _run(() async {
    if (!_opened) return;
    await store.discard();
    session = null;
    _clearAnswer();
    stage = FlashDemoStage.setup;
    await _loadLessons();
  });
  void flip() {
    if (busy ||
        advancing ||
        awaitingNext ||
        stage != FlashDemoStage.review)
      return;
    flipped = !flipped;
    notifyListeners();
  }

  Future<void> setup() => _run(() async {
    stage = FlashDemoStage.setup;
    _clearAnswer();
    await _loadLessons();
  });
  @override
  void dispose() {
    _disposed = true;
    _stopPronunciation();
    _advanceTimer?.cancel();
    unawaited(_close());
    super.dispose();
  }

  Future<void> _close() async {
    await _pending;
    try {
      await store.close();
    } catch (e) {
      debugPrint('Flashcard storage close failed: $e');
    }
  }
}

import '../../../user_error.dart';
import '../../../system_errors.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../host_contracts.dart';
import '../../../foundation/native_audio_transport.dart';
import 'models.dart';
import 'repository.dart';

enum FlashStage { setup, review, result }

class FlashController extends ChangeNotifier {
  FlashController(this.host)
    : store = FlashDatabaseStore(host),
      catalog = FlashCatalog(host) {
    host.changes.addListener(_hostChanged);
  }
  final StudyRoomHost host;
  final FlashStore store;
  final FlashCatalog catalog;
  bool busy = false, flipped = false, _opened = false, _disposed = false;
  Future<void>? _pending;
  String? error;
  FlashStage stage = FlashStage.setup;
  FlashDirection direction = FlashDirection.japanese;
  bool onlyWeak = false;
  bool randomOrder = false;
  int limit = 10, skipped = 0;
  String bookId = '', version = '';
  Set<String> lessonIds = {};
  List<FlashRow> books = [], lessons = [];
  List<FlashWord> words = [];
  Map<String, ({bool known, int time})> mastery = {};
  FlashSession? session;
  int? _answerIndex;
  Timer? _advanceTimer;
  bool advancing = false;
  bool get awaitingNext => _answerIndex != null;
  int get reviewIndex => _answerIndex ?? session!.index;
  bool get canRate =>
      stage == FlashStage.review &&
      hasDraft &&
      !awaitingNext &&
      !busy &&
      !advancing &&
      permitted &&
      !resourceBlocked;
  bool get permitted => host.isUnlocked() && !host.isPurchaseSaving();
  bool get hasDraft => session != null && !session!.complete;
  bool get resourceBlocked =>
      (stage == FlashStage.setup
          ? bookId.isNotEmpty && host.isBookUnavailable(bookId)
          : session != null &&
                host.isBookUnavailable(session!.words.first.bookId));
  List<FlashWord> _buildQueue() {
    final items = words
        .where((w) => !onlyWeak || mastery[w.key]?.known == false)
        .toList();
    if (randomOrder) items.shuffle();
    return limit == 0 ? items : items.take(limit).toList();
  }

  final _audio = NativeAudioTransport.instance;
  final _audioIdentity = 'flashcards:${DateTime.now().microsecondsSinceEpoch}';
  int _audioRequest = 0;
  bool _audioStarting = false;
  bool get pronunciationPlaying =>
      stage == FlashStage.review && session != null &&
      _audio.lesson == _audioIdentity &&
      _audio.playingId == session!.words[reviewIndex].key &&
      _audio.isPlaying;

  Future<void> playPronunciation() async {
    if (_disposed ||
        _audioStarting ||
        _audio.stopping ||
        busy ||
        advancing ||
        stage != FlashStage.review ||
        !permitted ||
        resourceBlocked)
      return;
    _audioStarting = true;
    final stopRevision = _audio.stopRevision;
    final request = ++_audioRequest;
    final word = session!.words[reviewIndex];
    try {
      await _validateSession();
      final path = await catalog.pronunciation(word);
      if (_disposed ||
          request != _audioRequest ||
          stopRevision != _audio.stopRevision ||
          stage != FlashStage.review ||
          !permitted ||
          resourceBlocked)
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
    } catch (e, caughtStack) {
      SystemErrors.record(e, caughtStack, module: 'flashcards', operation: '闪卡操作', context: {'source': 'study_room/flashcards/feature/controller.dart'});
      if (!_disposed && request == _audioRequest) {
        error = userError(e, fallback: '单词读音播放失败，请重试');
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
        _audio.stop().catchError((Object e, StackTrace stack) {
          SystemErrors.record(e, stack, module: 'flashcards', operation: '停止读音');
          debugPrint('Flashcard audio stop failed: $e');
        }),
      );
    }
  }

  void _hostChanged() {
    if (!permitted || resourceBlocked) _stopPronunciation();
    if (!_disposed) notifyListeners();
  }

  void _requirePermission() {
    if (!permitted) throw StateError('自习室暂未解锁，已保留复习进度');
  }

  Future<void> _run(Future<void> Function() action) {
    if (busy || _disposed) return Future.value();
    busy = true;
    error = null;
    notifyListeners();
    return _pending = () async {
      try {
        await action();
      } catch (e, caughtStack) {
      SystemErrors.record(e, caughtStack, module: 'flashcards', operation: '闪卡操作', context: {'source': 'study_room/flashcards/feature/controller.dart'});
        error = userError(e, fallback: '闪卡数据处理失败，请重试；已有记录不会自动删除');
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
    direction = FlashDirection.values.firstWhere(
      (d) => d.name == settings['direction'],
      orElse: () => FlashDirection.japanese,
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
    stage = FlashStage.setup;
  });

  Future<void> _loadLessons({bool newBook = false}) async {
    _requirePermission();
    books = await catalog.books();
    if (!books.any((b) => b['id'].toString() == bookId)) {
      bookId = '';
      lessonIds = {};
      lessons = [];
      return;
    }
    lessons = await catalog.lessons(bookId);
    final valid = lessons.map((l) => l['id'].toString()).toSet();
    lessonIds = newBook ? valid : lessonIds.intersection(valid);
  }

  Future<void> _loadSelectedWords() async {
    if (bookId.isEmpty) throw StateError('请先选择内容。');
    if (lessonIds.isEmpty) throw StateError('请先选择需要复习的课程。');
    final result = await catalog.words(bookId, lessonIds);
    words = result.words;
    version = result.version;
    skipped = result.skipped;
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
    FlashDirection? nextDirection,
    bool? weak,
    bool? random,
    int? count,
    String? book,
    Set<String>? selectedLessons,
  }) async {
    if (busy || _disposed || stage != FlashStage.setup) return;
    if (book != null) {
      await _run(() async {
        bookId = book;
        await _loadLessons(newBook: true);
      });
      return;
    }
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
        ? '请先选择内容。'
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
    _requirePermission();
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
    _requirePermission();
    final next = FlashSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      direction: direction,
      words: queue,
      version: version,
    );
    await store.begin(next);
    session = next;
    _clearAnswer();
    stage = FlashStage.review;
  });

  Future<void> _validateSession() async {
    _requirePermission();
    if (await catalog.version(session!.words.first.bookId) !=
            session!.version) {
      throw StateError('内容版本已变化，请返回设置放弃草稿，重新选择课程');
    }
  }

  Future<void> resume() => _run(() async {
    session = await store.draft();
    if (!hasDraft) throw StateError('没有未完成的复习');
    await _validateSession();
    _clearAnswer();
    stage = FlashStage.review;
  });
  Future<void> mark(bool known) => _run(() async {
    if (stage != FlashStage.review || awaitingNext || advancing || !hasDraft)
      return;
    _stopPronunciation();
    final stayOnAnswer = !known && !flipped;
    final ratedIndex = session!.index;
    await _validateSession();
    _requirePermission();
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
    stage = session!.complete ? FlashStage.result : FlashStage.review;
    if (stage == FlashStage.review && !_disposed) {
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
    if (!awaitingNext || busy || !permitted || resourceBlocked) return;
    _advance();
    notifyListeners();
  }

  Future<void> retryWeak() => _run(() async {
    if (stage != FlashStage.result || session!.weak.isEmpty) return;
    await _validateSession();
    final next = FlashSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      direction: session!.direction,
      words: session!.weak,
      version: session!.version,
    );
    await store.begin(next);
    session = next;
    _clearAnswer();
    stage = FlashStage.review;
  });
  Future<void> discard() => _run(() async {
    if (!_opened) return;
    await store.discard();
    session = null;
    _clearAnswer();
    stage = FlashStage.setup;
    await _loadLessons();
  });
  void flip() {
    if (busy ||
        advancing ||
        awaitingNext ||
        !permitted ||
        resourceBlocked ||
        stage != FlashStage.review)
      return;
    flipped = !flipped;
    notifyListeners();
  }

  Future<void> setup() => _run(() async {
    stage = FlashStage.setup;
    _clearAnswer();
    await _loadLessons();
  });
  @override
  void dispose() {
    _disposed = true;
    _stopPronunciation();
    _advanceTimer?.cancel();
    host.changes.removeListener(_hostChanged);
    unawaited(_close());
    super.dispose();
  }

  Future<void> _close() async {
    await _pending;
    try {
      await store.close();
    } catch (e, caughtStack) {
      SystemErrors.record(e, caughtStack, module: 'flashcards', operation: '闪卡操作', context: {'source': 'study_room/flashcards/feature/controller.dart'});
      debugPrint('Flashcard storage close failed: $e');
    }
  }
}

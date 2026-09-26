import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Shared platform transport; feature queues and presentation stay with their owners.
class NativeAudioTransport extends ChangeNotifier {
  NativeAudioTransport._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'state') _update(call.arguments);
    });
  }

  static final instance = NativeAudioTransport._();
  static const _channel = MethodChannel('yuzhichu/lesson_playback');
  Map<String, dynamic> _state = {};
  int _revision = -1;
  bool _stopping = false;
  Future<void>? _stopOperation;
  int _stopRevision = 0;

  bool get stopping => _stopping;
  int get stopRevision => _stopRevision;
  String get title {
    final value = (_state['title'] as String?)?.trim();
    return value == null || value.isEmpty ? '音频播放' : value;
  }

  bool get waiting => _state['waiting'] == true;
  bool get isPlaying => _state['isPlaying'] == true;

  String? get lesson => _state['lesson'] as String?;
  String? get playingId => _state['playingId'] as String?;
  /// The next clip selected by the native queue, including during an interval.
  String? get queuedId => _state['queuedId'] as String?;
  String? get completedId => _state['completedId'] as String?;
  bool get active => _state['active'] == true;
  bool get batch => _state['batch'] == true;
  bool get words => _state['words'] != false;
  bool get paused => _state['paused'] == true;
  int get repeat => (_state['repeat'] as num?)?.toInt() ?? 1;
  int get intervalSteps => (_state['intervalSteps'] as num?)?.toInt() ?? 0;
  String? get error => _state['error'] as String?;

  void _update(dynamic value) {
    if (value is! Map) return;
    final revision = (value['revision'] as num?)?.toInt() ?? 0;
    if (revision <= _revision) return;
    _revision = revision;
    _state = Map<String, dynamic>.from(value);
    notifyListeners();
  }

  Future<void> refresh() async =>
      _update(await _channel.invokeMethod<Object?>('state'));

  Future<void> start(Map<String, dynamic> request) async =>
      _update(await _channel.invokeMethod<Object?>('start', request));

  Future<void> stop() => _stopOperation ??= _stopNative();

  Future<void> _stopNative() async {
    _stopRevision++;
    _stopping = true;
    notifyListeners();
    try {
      _update(await _channel.invokeMethod<Object?>('stop'));
    } finally {
      _stopOperation = null;
      _stopping = false;
      notifyListeners();
    }
  }

  Future<void> resume() async =>
      _update(await _channel.invokeMethod<Object?>('resume'));

  Future<void> blockBook(String book) async => _update(
    await _channel.invokeMethod<Object?>('blockBook', {'book': book}),
  );

  Future<void> unblockBook(String book) async => _update(
    await _channel.invokeMethod<Object?>('unblockBook', {'book': book}),
  );

  Future<void> configure({
    double? speed,
    int? repeat,
    int? intervalSteps,
  }) async => _update(
    await _channel.invokeMethod<Object?>('configure', {
      if (speed != null) 'speed': speed,
      if (repeat != null) 'repeat': repeat,
      if (intervalSteps != null) 'intervalSteps': intervalSteps,
    }),
  );
}

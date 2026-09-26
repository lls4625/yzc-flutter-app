import 'dart:async';

import 'package:flutter/material.dart';

import '../../../foundation/native_audio_transport.dart';
import '../../../glass_ui.dart';
import 'demo.dart';
import 'models.dart';

String listeningDemoError(Object? error, {String fallback = '操作失败，请重试'}) =>
    error is StateError ? error.message.toString() : fallback;

Future<void> demoPerform(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      GlassSnackBar(content: Text(listeningDemoError(e))),
    );
  }
}

/// In-memory settings and tour commands belonging exclusively to this demo.
class ListeningDemoController extends ChangeNotifier {
  ListeningDemoController() { _audio.addListener(_changed); }
  final navigator = GlobalKey<NavigatorState>();
  final catalog = ListeningDemoCatalog();
  final _audio = NativeAudioTransport.instance;
  final identity = 'listening-demo:${DateTime.now().microsecondsSinceEpoch}';
  final _settings = <String, Object>{};
  bool _disposed = false, ready = false, foreground = true;
  int playbackGeneration = 0;
  bool get busy => playerReady != null && !playerReady!.isCompleted;
  String? error;
  ListeningDemoStage stage = ListeningDemoStage.selection;
  Completer<void>? playerReady;
  VoidCallback? selectAllAction, orderAction;
  VoidCallback? closeAction;
  Future<void> Function()? resetSelectionAction;
  Future<void> Function()? openPlayerAction, resumeAction;
  Future<void> Function(double)? speedAction;
  Future<void> Function(int)? repeatAction, intervalAction;
  bool get owns => _audio.lesson == identity;
  bool get playing => owns && _audio.active && !_audio.paused;
  String? get playbackError => owns ? _audio.error : null;
  String get selectedBook => listeningDemoText(catalog.data!.book, 'id');
  double get speed => (_settings['playback_speed'] as int? ?? 10) / 10;
  bool get ruby => _settings['show_ruby'] != 0;
  bool get source => _settings['show_source'] != 0;
  bool get translation => _settings['show_definition'] != 0;

  void _changed() { if (!_disposed) notifyListeners(); }
  Future<void> load() => catalog.load();
  void selectionReady() { ready = true; _changed(); }
  void reportError(String message) { error = message; _changed(); }
  Future<void> setting(String key, Object value) async {
    _settings[key] = value;
    _changed();
  }
  Future<void> resetDemo() async {
    await stop();
    if (_disposed) return;
    navigator.currentState?.popUntil((route) => route.isFirst);
    await WidgetsBinding.instance.endOfFrame;
    if (_disposed) return;
    _settings.clear();
    error = null;
    stage = ListeningDemoStage.selection;
    playerReady = null;
    await resetSelectionAction?.call();
    _changed();
  }
  void selectAll() => selectAllAction?.call();
  void demonstrateOrder() => orderAction?.call();
  Future<void> start({int? index}) async {
    if (_disposed || !foreground) return;
    if (stage == ListeningDemoStage.selection) {
      await openPlayerAction?.call();
    } else {
      await resumeAction?.call();
    }
    if (playbackError != null) throw StateError(playbackError!);
  }
  Future<void> setSpeed(double value) async { await speedAction?.call(value); }
  Future<void> setRepeat(int value) async { await repeatAction?.call(value); }
  Future<void> setInterval(int value) async { await intervalAction?.call(value); }
  Future<void> stop() async {
    ++playbackGeneration;
    if (owns) await _audio.stop();
  }
  @override
  void dispose() {
    _disposed = true;
    foreground = false;
    _audio.removeListener(_changed);
    unawaited(stop().catchError((Object e) { debugPrint('Demo audio stop failed: $e'); }));
    super.dispose();
  }
}

/// Bundled sample catalog. No database, host or installed-resource access.
class ListeningDemoCatalog {
  ListeningDemoData? data;
  Future<void> load() async { data ??= await ListeningDemoData.load(); }
  Future<List<ListeningDemoRow>> textbooks() async => [data!.book];
  Future<List<ListeningDemoRow>> lessons(String book) async => [data!.lesson];
  Future<String> version(String book) async => 'bundled-listening-demo-v1';
  Future<List<ListeningDemoRow>> content(String table, String book, String lesson) async =>
      switch (table) {
        'yzc_words' => data!.words,
        'yzc_content' => data!.content,
        _ => throw ArgumentError('未知样例内容类型'),
      };
  Future<String> audioPath(String book, String filename) async => data!.audioPath(filename);
}

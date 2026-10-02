import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../system_errors.dart';

/// A course owns playback; inline and fullscreen surfaces only observe it.
class CourseVideoController extends ChangeNotifier {
  CourseVideoController() {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'state' && call.arguments is Map) {
          final state = Map<String, dynamic>.from(call.arguments as Map);
          _owners[state['owner']]?._update(state);
        }
      });
    }
    _owners[owner] = this;
  }

  static const _channel = MethodChannel('yuzhichu/course_video');
  static final _owners = <String, CourseVideoController>{};
  static bool _listening = false;
  static int _serial = 0;
  final String owner = 'course-video-${DateTime.now().microsecondsSinceEpoch}-${_serial++}';
  Map<String, dynamic> _state = {};
  int _revision = -1, _request = 0;
  bool _disposed = false;
  bool busy = false;
  bool fullscreen = false;
  String orientationMode = 'auto';
  String? error;
  int speedSteps = 20;
  String? get rowId => _state['id'] as String?;
  String get status => _state['status'] as String? ?? 'idle';
  bool get playing => _state['playing'] == true;
  bool get loading => status == 'loading';
  bool get active => rowId != null && !{'idle', 'ended', 'error'}.contains(status);
  bool get hasMedia => rowId != null && status != 'idle';
  double get position => (_state['position'] as num?)?.toDouble() ?? 0;
  double get duration => (_state['duration'] as num?)?.toDouble() ?? 0;
  double get aspectRatio {
    final value = (_state['aspectRatio'] as num?)?.toDouble() ?? 16 / 9;
    return value.isFinite && value > 0 ? value : 16 / 9;
  }
  double get speed => speedSteps / 20;
  String get speedLabel => speed.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

  void _update(Map<String, dynamic> state) {
    if (_disposed || state['owner'] != owner) return;
    final revision = (state['revision'] as num?)?.toInt() ?? 0;
    if (revision <= _revision) return;
    _revision = revision;
    _state = state;
    final nextError = state['error'] as String?;
    if (nextError != null && nextError != error) {
      SystemErrors.record(StateError(nextError), StackTrace.current,
        module: 'course_video', operation: '原生视频状态', context: {'content_id': rowId});
    }
    error = nextError;
    notifyListeners();
  }

  Future<void> _invoke(String method, [Map<String, Object?> args = const {}]) async {
    final result = await _channel.invokeMethod<Object?>(method, {'owner': owner, ...args});
    if (result is Map) _update(Map<String, dynamic>.from(result));
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_disposed || busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'course_video', operation: '视频播放操作');
      if (!_disposed) error = e is PlatformException && e.message?.isNotEmpty == true
        ? e.message : '视频暂时无法播放，请重试';
    } finally {
      if (!_disposed) { busy = false; notifyListeners(); }
    }
  }

  Future<void> play({required String id, required String book,
    required Future<String> Function() resolvePath, required Future<void> Function() beforePlay}) => _action(() async {
    final request = ++_request;
    final path = await resolvePath();
    if (_disposed || request != _request) return;
    await beforePlay();
    if (_disposed || request != _request) return;
    await _invoke('load', {'id': id, 'book': book, 'path': path, 'speedSteps': speedSteps});
  });

  Future<(String, double)?> poster(Future<String> Function() resolvePath) async {
    try {
      final path = await resolvePath();
      if (_disposed) return null;
      final result = await _channel.invokeMapMethod<String, Object?>('poster', {
        'owner': owner,
        'path': path,
      });
      final posterPath = result?['path'] as String?;
      final ratio = (result?['aspectRatio'] as num?)?.toDouble();
      final nativeError = result?['error'] as String?;
      if (nativeError != null && nativeError.isNotEmpty) throw StateError(nativeError);
      if (posterPath == null || posterPath.isEmpty || ratio == null || !ratio.isFinite || ratio <= 0) return null;
      return (posterPath, ratio);
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'course_video', operation: '生成视频预览图');
      return null;
    }
  }

  Future<void> toggle() => _action(() => _invoke(playing ? 'pause' : 'resume'));
  Future<void> seek(double seconds) => _action(() => _invoke('seek', {'seconds': seconds}));
  Future<void> changeSpeed(int delta) => _action(() async {
    final next = (speedSteps + delta).clamp(10, 60).toInt();
    await _invoke('speed', {'speedSteps': next});
    if (!_disposed) speedSteps = next;
  });

  Future<void> changeOrientation(String mode) async {
    const supported = {'auto', 'portrait', 'landscapeLeft', 'landscapeRight'};
    if (_disposed || !supported.contains(mode) || orientationMode == mode) return;
    final orientations = switch (mode) {
      'portrait' => const [DeviceOrientation.portraitUp],
      'landscapeLeft' => const [DeviceOrientation.landscapeLeft],
      'landscapeRight' => const [DeviceOrientation.landscapeRight],
      _ => const <DeviceOrientation>[],
    };
    try {
      await SystemChrome.setPreferredOrientations(orientations);
      if (!_disposed) {
        orientationMode = mode;
        notifyListeners();
      }
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'course_video', operation: '切换屏幕方向');
    }
  }

  Future<void> resetOrientation() => changeOrientation('auto');

  Future<void> stop() async {
    ++_request; // Also cancels an in-flight path lookup or audio handoff.
    if (_disposed) return;
    try {
      await _invoke('stop');
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'course_video', operation: '停止视频');
      if (!_disposed) { error = '停止视频失败，请重试'; notifyListeners(); }
      rethrow;
    }
  }

  void setFullscreen(bool value) {
    if (_disposed || fullscreen == value) return;
    fullscreen = value;
    notifyListeners();
  }

  @override
  void dispose() {
    ++_request;
    _disposed = true;
    _owners.remove(owner);
    unawaited(SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]).catchError(
      (Object e, StackTrace stack) {
        SystemErrors.record(e, stack, module: 'course_video', operation: '恢复自动旋转');
      }));
    unawaited(_invoke('stop').catchError((Object e, StackTrace stack) {
      SystemErrors.record(e, stack, module: 'course_video', operation: '离开课程停止视频');
    }));
    super.dispose();
  }
}

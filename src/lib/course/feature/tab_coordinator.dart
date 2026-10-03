import 'package:flutter/material.dart';

typedef CourseTabBottomBuilder = Widget Function(BuildContext context);
typedef CourseTabAction = Future<void> Function();
typedef CourseTabCondition = bool Function();

/// Bridges tab-owned controls and media actions to the lesson-page state machine.
///
/// Content and media stay inside each independent tab. The lesson page uses this
/// narrow contract to keep navigation, bottom chrome, and route lifecycle
/// behavior consistent across all four tabs.
class CourseTabCoordinator extends ChangeNotifier {
  Object? _owner;
  CourseTabBottomBuilder? _bottomBuilder;
  CourseTabAction? _stopForTabChange;
  CourseTabAction? _stopVideo;
  CourseTabCondition? _videoFullscreen;
  bool _busy = false;

  bool get busy => _busy;
  bool get hasBottom => _bottomBuilder != null;
  bool get videoFullscreen => _videoFullscreen?.call() ?? false;

  Widget? buildBottom(BuildContext context) => _bottomBuilder?.call(context);

  void attach(Object owner, {
    CourseTabBottomBuilder? bottomBuilder,
    CourseTabAction? stopForTabChange,
    CourseTabAction? stopVideo,
    CourseTabCondition? videoFullscreen,
    bool busy = false,
  }) {
    _owner = owner;
    _bottomBuilder = bottomBuilder;
    _stopForTabChange = stopForTabChange;
    _stopVideo = stopVideo;
    _videoFullscreen = videoFullscreen;
    _busy = busy;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_owner == owner) notifyListeners();
    });
  }

  void update(Object owner, {bool? busy}) {
    if (_owner != owner) return;
    if (busy != null) _busy = busy;
    notifyListeners();
  }

  Future<void> stopForTabChange() async {
    await _stopForTabChange?.call();
  }

  Future<void> stopVideo() async {
    await _stopVideo?.call();
  }

  void detach(Object owner) {
    if (_owner != owner) return;
    _owner = null;
    _bottomBuilder = null;
    _stopForTabChange = null;
    _stopVideo = null;
    _videoFullscreen = null;
    _busy = false;
  }
}

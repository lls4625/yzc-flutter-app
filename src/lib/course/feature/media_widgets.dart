import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'video_controller.dart';

class CourseImageCard extends StatefulWidget {
  const CourseImageCard({super.key, required this.source, required this.resolvePath, required this.label});
  final String source, label;
  final Future<String> Function() resolvePath;
  @override
  State<CourseImageCard> createState() => _CourseImageCardState();
}

class _CourseImageCardState extends State<CourseImageCard> {
  late Future<(String, double)> _image = _load();
  Future<(String, double)> _load() async {
    final path = await widget.resolvePath();
    final codec = await ui.instantiateImageCodec(await File(path).readAsBytes(), targetWidth: 64);
    try {
      final frame = await codec.getNextFrame();
      final ratio = frame.image.width / frame.image.height;
      frame.image.dispose();
      return (path, ratio);
    } finally { codec.dispose(); }
  }
  @override
  void didUpdateWidget(CourseImageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.source != oldWidget.source) _image = _load();
  }
  @override
  Widget build(BuildContext context) => _MediaCard(child: FutureBuilder<(String, double)>(
    future: _image,
    builder: (context, snapshot) {
      Widget failure() => Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        const Text('插图暂时无法显示'),
        TextButton(onPressed: () => setState(() => _image = _load()), child: const Text('重试')),
      ]));
      if (snapshot.hasError) return failure();
      final data = snapshot.data;
      return AspectRatio(aspectRatio: data?.$2 ?? 2 / 3, child: data == null
          ? const Center(child: CircularProgressIndicator())
          : Image.file(File(data.$1), fit: BoxFit.contain, semanticLabel: widget.label,
              errorBuilder: (_, error, stack) => failure()));
    },
  ));
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 12),
    child: Material(color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14), clipBehavior: Clip.antiAlias, child: child));
}

class CourseVideoCard extends StatelessWidget {
  const CourseVideoCard({super.key, required this.controller, required this.id,
    required this.onPlay, required this.enabled});
  final CourseVideoController controller;
  final String id;
  final Future<void> Function() onPlay;
  final bool enabled;
  @override
  Widget build(BuildContext context) => _MediaCard(child: AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final selected = controller.rowId == id && controller.hasMedia;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(borderRadius: BorderRadius.circular(14), child: selected
          ? AspectRatio(aspectRatio: controller.aspectRatio.clamp(.6, 2.0).toDouble(),
            child: CourseVideoSurface(controller: controller, onRetry: onPlay,
              onFullscreen: () => openCourseVideoFullscreen(context, controller)))
          : AspectRatio(aspectRatio: 16 / 9, child: ColoredBox(color: Colors.black87,
            child: Center(child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: enabled && !controller.busy ? onPlay : null,
              icon: const Icon(Icons.play_circle_fill, size: 44),
              label: Text(controller.busy ? '准备中' : '点击播放'),
            ))))),
        if (!selected && controller.error != null)
          Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: Text(controller.error!)),
      ]);
    },
  ));
}

/// Flutter draws controls; the native view is only a video surface. Vertical
/// gestures remain with the course scroll view, horizontal video gestures do not
/// change the course tab.
class CourseVideoSurface extends StatefulWidget {
  const CourseVideoSurface({super.key, required this.controller, required this.onFullscreen,
    this.fullscreen = false, this.onRetry});
  final CourseVideoController controller;
  final VoidCallback onFullscreen;
  final bool fullscreen;
  final Future<void> Function()? onRetry;
  @override
  State<CourseVideoSurface> createState() => _CourseVideoSurfaceState();
}

class _CourseVideoSurfaceState extends State<CourseVideoSurface> {
  double? _dragPosition;
  String _time(double value) {
    final seconds = value.isFinite ? value.floor().clamp(0, 864000) : 0;
    final minutes = seconds ~/ 60;
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: widget.controller, builder: (context, _) {
    final c = widget.controller;
    final enabled = !c.busy && !c.loading && c.status != 'error';
    Widget button(String label, IconData icon, VoidCallback? action) => IconButton(
      tooltip: label, onPressed: action, color: Colors.white, disabledColor: Colors.white38,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44), icon: Icon(icon));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (_) {},
      child: ColoredBox(color: Colors.black, child: Stack(fit: StackFit.expand, children: [
        if (widget.fullscreen || !c.fullscreen)
          IgnorePointer(child: UiKitView(
            key: ValueKey('${c.owner}:${widget.fullscreen}'),
            viewType: 'yuzhichu/course_video_surface',
            creationParams: {'owner': c.owner, 'fullscreen': widget.fullscreen},
            creationParamsCodec: const StandardMessageCodec(),
          )),
        if (c.loading) const Center(child: CircularProgressIndicator(color: Colors.white)),
        if (c.error != null)
          Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(c.error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
              if (widget.onRetry != null)
                TextButton(onPressed: c.busy ? null : widget.onRetry, child: const Text('重试')),
            ]))),
        Positioned(top: 0, left: 0, right: 0, child: ColoredBox(color: Colors.black54,
          child: Row(children: [
            button('速度减少 0.05', Icons.remove, enabled && c.speedSteps > 10 ? () => c.changeSpeed(-1) : null),
            SizedBox(width: 48, child: Text(c.speedLabel, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              semanticsLabel: '视频速度 ${c.speedLabel} 倍')),
            button('速度增加 0.05', Icons.add, enabled && c.speedSteps < 60 ? () => c.changeSpeed(1) : null),
            const Spacer(),
            button(widget.fullscreen ? '退出全屏' : '全屏',
              widget.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              widget.fullscreen || c.active ? widget.onFullscreen : null),
          ]))),
        Positioned(bottom: 0, left: 0, right: 0, child: ColoredBox(color: Colors.black54,
          child: Row(children: [
            button(c.status == 'ended' ? '重新播放' : c.playing ? '暂停' : '继续',
              c.status == 'ended' ? Icons.replay : c.playing ? Icons.pause : Icons.play_arrow,
              enabled ? () => c.toggle() : null),
            Text(_time(_dragPosition ?? c.position), style: const TextStyle(color: Colors.white, fontSize: 12)),
            Expanded(child: Slider(
              value: (_dragPosition ?? c.position).clamp(0, math.max(c.duration, .001)).toDouble(),
              min: 0, max: math.max(c.duration, .001),
              onChanged: enabled && c.duration > 0 ? (value) => setState(() => _dragPosition = value) : null,
              onChangeEnd: (value) async {
                await c.seek(value);
                if (mounted) setState(() => _dragPosition = null);
              },
            )),
            Padding(padding: const EdgeInsets.only(right: 12),
              child: Text(_time(c.duration), style: const TextStyle(color: Colors.white, fontSize: 12))),
          ]))),
      ])),
    );
  });
}

Future<void> openCourseVideoFullscreen(BuildContext context, CourseVideoController controller) async {
  if (controller.fullscreen || !controller.active) return;
  controller.setFullscreen(true);
  try {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => _FullscreenVideo(controller)));
  } finally { controller.setFullscreen(false); }
}

class _FullscreenVideo extends StatefulWidget {
  const _FullscreenVideo(this.controller);
  final CourseVideoController controller;
  @override
  State<_FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<_FullscreenVideo> {
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _changed();
  }
  void _close() {
    if (_closing || !mounted || ModalRoute.of(context)?.isCurrent != true) return;
    _closing = true;
    Navigator.of(context).pop();
  }
  void _changed() {
    if (!{'ended', 'idle'}.contains(widget.controller.status)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _close(); });
  }
  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black,
    body: SafeArea(child: CourseVideoSurface(controller: widget.controller,
      fullscreen: true, onFullscreen: _close)),
  );
}

class CourseVideoBar extends StatelessWidget {
  const CourseVideoBar({super.key, required this.controller, required this.onLocate});
  final CourseVideoController controller;
  final VoidCallback onLocate;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: controller, builder: (context, _) =>
    Material(color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          Expanded(child: Text(controller.error ?? (controller.loading ? '视频准备中' :
            controller.playing ? '视频播放中' : '视频已暂停'), maxLines: 2)),
          IconButton(tooltip: controller.playing ? '暂停视频' : '继续视频',
            onPressed: controller.busy || controller.loading ? null : controller.toggle,
            icon: Icon(controller.playing ? Icons.pause : Icons.play_arrow)),
          IconButton(tooltip: '定位视频', onPressed: onLocate, icon: const Icon(Icons.my_location)),
          TextButton(onPressed: () async {
            try { await controller.stop(); } catch (_) { /* Controller exposes the error. */ }
          }, child: const Text('结束')),
        ])),
    ));
}

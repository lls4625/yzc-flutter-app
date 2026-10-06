import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'image_interaction_config.dart';
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

class CourseInteractiveImageCard extends StatefulWidget {
  const CourseInteractiveImageCard({super.key, required this.source, required this.resolvePath, required this.label,
    required this.mediaConfig, required this.onActivate, required this.interactionEnabled, this.hotspotAvailable});
  final String source, label, mediaConfig;
  final Future<String> Function() resolvePath;
  final Future<void> Function(CourseImageHotspot hotspot) onActivate;
  final Future<bool> Function(CourseImageHotspot hotspot)? hotspotAvailable;
  final bool interactionEnabled;
  @override
  State<CourseInteractiveImageCard> createState() => _CourseInteractiveImageCardState();
}

class _CourseInteractiveImageCardState extends State<CourseInteractiveImageCard> {
  late Future<(String, double)> _image = _load();
  late CourseImageInteractionConfig? _config = _parseConfig();
  String? _selected;
  int _activation = 0;
  final Map<String, Future<bool>> _availability = {};

  CourseImageInteractionConfig? _parseConfig() {
    return CourseImageInteractionConfig.parseTolerant(widget.mediaConfig).config;
  }

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
  void didUpdateWidget(CourseInteractiveImageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.source != oldWidget.source) _image = _load();
    if (widget.mediaConfig != oldWidget.mediaConfig) {
      _config = _parseConfig();
      _selected = null;
      _availability.clear();
    }
  }

  Color _color(String value) => Color(int.parse(value.substring(1), radix: 16) | 0xFF000000);

  void _activate(CourseImageHotspot hotspot) {
    setState(() { _selected = hotspot.id; _activation++; });
    if (widget.interactionEnabled) unawaited(widget.onActivate(hotspot));
  }

  Widget _interactiveImage(String path, double ratio) => AspectRatio(
    aspectRatio: ratio,
    child: LayoutBuilder(builder: (context, constraints) => Stack(fit: StackFit.expand, children: [
      Image.file(File(path), fit: BoxFit.contain, semanticLabel: widget.label),
      for (final hotspot in _config!.hotspots) FutureBuilder<bool>(
        future: _availability.putIfAbsent(hotspot.id, () => widget.hotspotAvailable?.call(hotspot) ?? Future<bool>.value(true)),
        builder: (context, snapshot) => _hotspot(hotspot, constraints, snapshot.data ?? false)),
    ])),
  );

  Widget _hotspot(CourseImageHotspot hotspot, BoxConstraints constraints, bool available) {
    final selected = _selected == hotspot.id;
    final bounds = hotspot.bounds;
    final color = _color(hotspot.color);
    return Positioned(
      left: constraints.maxWidth * bounds.x,
      top: constraints.maxHeight * bounds.y,
      width: constraints.maxWidth * bounds.width,
      height: constraints.maxHeight * bounds.height,
      child: Semantics(
        button: true,
        enabled: widget.interactionEnabled && available,
        selected: selected,
        label: '${hotspot.semanticLabel}，点击播放读音',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.interactionEnabled && available ? () => _activate(hotspot) : null,
          child: TweenAnimationBuilder<double>(
            key: ValueKey('${hotspot.id}:$selected:$_activation'),
            tween: Tween(begin: 0, end: selected ? 1 : 0),
            duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero : const Duration(milliseconds: 520),
            curve: Curves.easeOut,
            builder: (context, progress, child) => Transform.scale(
              scale: selected ? 1 + math.sin(progress * math.pi) * .025 : 1,
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero : const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: selected ? .10 : .04),
                  border: Border.all(color: color.withValues(alpha: selected ? 1 : .72),
                    width: selected ? 3 : 2),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: selected
                    ? [BoxShadow(color: color.withValues(alpha: .35), blurRadius: 12, spreadRadius: 2)]
                    : const [],
                ),
                child: selected ? Align(alignment: Alignment.topLeft, child: Container(
                  margin: const EdgeInsets.all(4),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: color.withValues(alpha: .92), borderRadius: BorderRadius.circular(6)),
                  child: Text(hotspot.label, style: const TextStyle(color: Colors.white, fontSize: 12,
                    fontWeight: FontWeight.w700, height: 1.2)),
                )) : Align(alignment: Alignment.topRight, child: Container(
                  width: 12, height: 12, margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: color.withValues(alpha: .45), blurRadius: 5)]),
                )),
              ),
            ),
          ),
        ),
      ),
    );
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
          : _config == null
            ? Image.file(File(data.$1), fit: BoxFit.contain, semanticLabel: widget.label, errorBuilder: (_, error, stack) => failure())
            : _interactiveImage(data.$1, data.$2));
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

class CourseVideoCard extends StatefulWidget {
  const CourseVideoCard({super.key, required this.controller, required this.id,
    required this.source, required this.resolvePath, required this.onPlay, required this.enabled});
  final CourseVideoController controller;
  final String id, source;
  final Future<String> Function() resolvePath;
  final Future<void> Function() onPlay;
  final bool enabled;
  @override
  State<CourseVideoCard> createState() => _CourseVideoCardState();
}

class _CourseVideoCardState extends State<CourseVideoCard> {
  late Future<(String, double)?> _poster = widget.controller.poster(widget.resolvePath);
  @override
  void didUpdateWidget(CourseVideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.source != oldWidget.source || (!oldWidget.enabled && widget.enabled)) {
      _poster = widget.controller.poster(widget.resolvePath);
    }
  }
  @override
  Widget build(BuildContext context) => _MediaCard(child: AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final selected = controller.rowId == widget.id && controller.hasMedia;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(borderRadius: BorderRadius.circular(14), child: selected
          ? AspectRatio(aspectRatio: controller.aspectRatio.clamp(.6, 2.0).toDouble(),
            child: CourseVideoSurface(controller: controller, onRetry: widget.onPlay,
              onFullscreen: () => openCourseVideoFullscreen(context, controller),
              onOrientation: (value) {
                controller.setVideoOrientation(value);
                if (value != 'portrait' && !controller.fullscreen) {
                  unawaited(openCourseVideoFullscreen(context, controller));
                }
              }))
          : FutureBuilder<(String, double)?>(future: _poster, builder: (context, snapshot) {
              final poster = snapshot.data;
              return AspectRatio(aspectRatio: (poster?.$2 ?? 16 / 9).clamp(.6, 2.0).toDouble(),
                child: ColoredBox(color: Colors.black87, child: Stack(fit: StackFit.expand, children: [
                  if (poster != null)
                    Image.file(File(poster.$1), fit: BoxFit.contain,
                      errorBuilder: (_, error, stack) => const SizedBox.shrink()),
                  Center(child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: widget.enabled && !controller.busy ? widget.onPlay : null,
                    icon: const Icon(Icons.play_circle_fill, size: 44),
                    label: Text(controller.busy ? '准备中' : '点击播放'),
                  )),
                ])));
            })),
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
    required this.onOrientation, this.fullscreen = false, this.onRetry});
  final CourseVideoController controller;
  final VoidCallback onFullscreen;
  final ValueChanged<String> onOrientation;
  final bool fullscreen;
  final Future<void> Function()? onRetry;
  @override
  State<CourseVideoSurface> createState() => _CourseVideoSurfaceState();
}

class _CourseVideoSurfaceState extends State<CourseVideoSurface> {
  double? _dragPosition;
  bool _showOrientationMenu = false;
  String _time(double value) {
    final seconds = value.isFinite ? value.floor().clamp(0, 864000) : 0;
    final minutes = seconds ~/ 60;
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: widget.controller, builder: (context, _) {
    final c = widget.controller;
    final enabled = !c.busy && !c.loading && c.status != 'error';
    const orientationNames = {
      'landscapeLeft': '横屏向左',
      'landscapeRight': '横屏向右',
    };
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
        Positioned(top: 48, right: 0, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          ColoredBox(color: Colors.black54, child: button('视频方向', Icons.screen_rotation,
            c.active ? () => setState(() => _showOrientationMenu = !_showOrientationMenu) : null)),
          if (_showOrientationMenu)
            Material(color: Colors.black87, child: SizedBox(width: 164, child: Column(
              mainAxisSize: MainAxisSize.min,
              children: orientationNames.entries.map((entry) => InkWell(
                onTap: () {
                  setState(() => _showOrientationMenu = false);
                  widget.onOrientation(entry.key);
                },
                child: SizedBox(height: 44, child: Row(children: [
                  const SizedBox(width: 12),
                  Icon(c.videoOrientation == entry.key ? Icons.check : Icons.screen_rotation,
                    color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(entry.value, style: const TextStyle(color: Colors.white)),
                ])),
              )).toList(),
            ))),
        ])),
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
  } finally {
    controller.setVideoOrientation('portrait');
    controller.setFullscreen(false);
  }
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
    body: SafeArea(child: AnimatedBuilder(animation: widget.controller, builder: (context, _) {
      final quarterTurns = switch (widget.controller.videoOrientation) {
        'landscapeLeft' => 3,
        'landscapeRight' => 1,
        _ => 0,
      };
      return RotatedBox(quarterTurns: quarterTurns, child: CourseVideoSurface(
        controller: widget.controller,
        fullscreen: true,
        onFullscreen: _close,
        onOrientation: widget.controller.setVideoOrientation,
      ));
    })),
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

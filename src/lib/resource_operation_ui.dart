import 'package:flutter/material.dart';
import 'glass_ui.dart';

void showResourceWait(BuildContext context, String operation) {
  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(GlassSnackBar(
      duration: const Duration(seconds: 3),
      content: Text('请等待$operation完成'),
    ));
}

class ResourceActivityIcon extends StatefulWidget {
  const ResourceActivityIcon({required this.checking});
  final bool checking;

  @override
  State<ResourceActivityIcon> createState() => _ResourceActivityIconState();
}

class _ResourceActivityIconState extends State<ResourceActivityIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _rotation;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    if (widget.checking) _rotation.repeat();
  }

  @override
  void didUpdateWidget(covariant ResourceActivityIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checking == widget.checking) return;
    if (widget.checking) {
      _rotation.repeat();
    } else {
      _rotation.reset();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _rotation,
    child: const Icon(Icons.refresh),
  );
}


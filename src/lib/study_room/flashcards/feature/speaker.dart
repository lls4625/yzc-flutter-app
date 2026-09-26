import 'package:flutter/material.dart';

import '../../../foundation/native_audio_transport.dart';
import 'controller.dart';

/// Playback feedback owned by the formal flashcard feature.
class FlashcardSpeaker extends StatefulWidget {
  const FlashcardSpeaker({required this.controller, super.key});
  final FlashController controller;

  @override
  State<FlashcardSpeaker> createState() => _FlashcardSpeakerState();
}

class _FlashcardSpeakerState extends State<FlashcardSpeaker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    NativeAudioTransport.instance.addListener(_sync);
    widget.controller.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(covariant FlashcardSpeaker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
    }
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    if (widget.controller.pronunciationPlaying && !_reduceMotion) {
      if (!_animation.isAnimating) _animation.repeat();
    } else {
      _animation.stop();
      _animation.value = 0;
    }
    setState(() {});
  }

  @override
  void dispose() {
    NativeAudioTransport.instance.removeListener(_sync);
    widget.controller.removeListener(_sync);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.controller.pronunciationPlaying ? '正在朗读单词' : '点击卡片播放读音',
    child: AnimatedBuilder(
      animation: _animation,
      builder: (context, _) => Icon(
        !widget.controller.pronunciationPlaying || _reduceMotion
            ? Icons.volume_up_rounded
            : _animation.value < 1 / 3
            ? Icons.volume_mute_rounded
            : _animation.value < 2 / 3
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded,
        size: 30,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

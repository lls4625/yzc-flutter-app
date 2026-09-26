import 'package:flutter/material.dart';

import '../../../glass_ui.dart';
import '../../../foundation/native_audio_transport.dart';

/// Reserves space above each page's navigation or actions, without an overlay.
class DictationDemoScaffold extends StatelessWidget {
  const DictationDemoScaffold({
    super.key,
    this.appBar,
    this.body,
    this.backgroundColor,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.controlledLesson,
  });

  final PreferredSizeWidget? appBar;
  final Widget? body, bottomNavigationBar, floatingActionButton;
  final Color? backgroundColor;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final String? controlledLesson;

  @override
  Widget build(BuildContext context) {
    final playback = NativeAudioTransport.instance;
    return AnimatedBuilder(
      animation: playback,
      builder: (context, _) {
        final show =
            playback.active &&
            playback.lesson != controlledLesson;
        final keyboard = show ? MediaQuery.viewInsetsOf(context).bottom : 0.0;
        return Scaffold(
          appBar: appBar,
          body: body,
          backgroundColor: backgroundColor,
          floatingActionButton: keyboard > 0 ? null : floatingActionButton,
          floatingActionButtonLocation: floatingActionButtonLocation,
          bottomNavigationBar: !show
              ? bottomNavigationBar
              : Padding(
                  padding: EdgeInsets.only(bottom: keyboard),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PlaybackBar(
                        key: ValueKey(playback.lesson),
                        bottomSafeArea: bottomNavigationBar == null,
                      ),
                      if (bottomNavigationBar != null) bottomNavigationBar!,
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _PlaybackBar extends StatefulWidget {
  const _PlaybackBar({super.key, required this.bottomSafeArea});
  final bool bottomSafeArea;

  @override
  State<_PlaybackBar> createState() => _PlaybackBarState();
}

class _PlaybackBarState extends State<_PlaybackBar> {
  String? _error;

  Future<void> _stop() async {
    setState(() => _error = null);
    try {
      await NativeAudioTransport.instance.stop();
    } catch (_) {
      if (mounted) setState(() => _error = '停止失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final playback = NativeAudioTransport.instance;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = playback.stopping
        ? '正在停止…'
        : playback.paused
        ? '已暂停'
        : playback.waiting
        ? '播放间隔中'
        : '播放中';
    return Material(
      color: colors.surfaceContainerLow,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          bottom: widget.bottomSafeArea,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.headphones_rounded, color: colors.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playback.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _error ?? status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _error == null
                              ? colors.onSurfaceVariant
                              : colors.error,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StudyButton.text(
                  onPressed: playback.stopping ? null : _stop,
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(88, 48)),
                  ),
                  child: Text(playback.stopping ? '正在停止' : '停止播放'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

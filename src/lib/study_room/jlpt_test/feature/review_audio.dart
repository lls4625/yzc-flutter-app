import 'dart:async';
import 'package:flutter/material.dart';
import '../../../foundation/native_audio_transport.dart';
import '../../../glass_ui.dart';
import '../../../system_errors.dart';
import 'models.dart';

/// Review playback is independent of the exam's one-completion allowance.
class ReviewAudio extends StatefulWidget {
  const ReviewAudio({super.key, required this.question, required this.resolveMedia});
  final Question question;
  final Future<String?> Function(String, String) resolveMedia;

  @override
  State<ReviewAudio> createState() => _ReviewAudioState();
}

class _ReviewAudioState extends State<ReviewAudio> with WidgetsBindingObserver {
  final _audio = NativeAudioTransport.instance;
  late final String _owner = 'jlpt-review-${DateTime.now().microsecondsSinceEpoch}';
  String? _path, _request;
  bool _loading = true, _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audio.addListener(_changed);
    unawaited(_load());
  }

  Future<void> _load() async {
    String? path;
    try {
      path = await widget.resolveMedia(widget.question.data['level'] as String,
        widget.question.data['phonetic'] as String? ?? '');
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'jlpt_test', operation: '读取回顾音频');
    }
    if (mounted) setState(() { _path = path; _loading = false; });
  }

  void _changed() {
    if (!mounted || _request == null || _busy) return;
    if (_audio.lesson != _owner || _audio.completedId == _request || !_audio.active) {
      setState(() => _request = null);
    } else if (_audio.paused || _audio.error != null) {
      unawaited(_stop());
    }
  }

  Future<void> _stopOwned() async {
    if (_audio.lesson != _owner) return;
    try { await _audio.stop(); }
    catch (error, stack) {
      SystemErrors.record(error, stack, module: 'jlpt_test', operation: '停止回顾音频');
    }
  }

  Future<void> _stop() async {
    _request = null;
    if (mounted) setState(() {});
    await _stopOwned();
  }

  Future<void> _toggle() async {
    if (_busy || _path == null) return;
    if (_request != null) { await _stop(); return; }
    final id = '$_owner-${DateTime.now().microsecondsSinceEpoch}';
    setState(() { _busy = true; _request = id; });
    try {
      if (_audio.stopping) await _audio.stop();
      if (!mounted || _request != id) return;
      await _audio.start({
        'lesson': _owner, 'title': '${widget.question.typeName} · 回顾',
        'albumTitle': 'J测试回顾', 'words': false, 'batch': false,
        'speed': 1.0, 'repeat': 1, 'intervalSteps': 0,
        'clips': [{'id': id, 'path': _path}], 'startIndex': 0,
      });
      if (!mounted || _request != id) await _stopOwned();
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'jlpt_test', operation: '播放回顾音频');
      _request = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('音频播放失败，请重试。')));
        unawaited(_load());
      }
    } finally {
      _busy = false;
      if (mounted) { setState(() {}); _changed(); }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_stop());
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(_loading ? '正在读取音频' : _path == null ? '音频未提供' : '听力音频'),
      StudyButton.textIcon(
        onPressed: _loading || _path == null || _busy ? null : _toggle,
        icon: Icon(_request == null ? Icons.volume_up_outlined : Icons.stop),
        label: Text(_request == null ? '播放' : '停止')),
    ]),
  );

  @override
  void dispose() {
    _audio.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    _request = null;
    unawaited(_stopOwned());
    super.dispose();
  }
}

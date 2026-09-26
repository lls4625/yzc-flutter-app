import 'dart:async';
import 'package:flutter/material.dart';
import '../../../glass_ui.dart';
import '../../../foundation/native_audio_transport.dart';
import '../../../system_errors.dart';
import 'models.dart';
import 'question_view.dart';

class ListeningQuestion extends StatefulWidget {
  const ListeningQuestion({super.key, required this.question, required this.answer,
    required this.onAnswer, required this.onHelp, required this.resolveMedia,
    this.review = false, this.mistakeReview = false, this.audioCompleted = false});
  final Question question;
  final String? answer;
  final ValueChanged<String>? onAnswer;
  final ValueChanged<String> onHelp;
  final Future<String?> Function(String, String) resolveMedia;
  final bool review, mistakeReview;
  final bool audioCompleted;
  @override
  State<ListeningQuestion> createState() => _ListeningQuestionState();
}

class _ListeningQuestionState extends State<ListeningQuestion> with WidgetsBindingObserver {
  final _audio = NativeAudioTransport.instance;
  late final String _owner = 'jlpt_test-${DateTime.now().microsecondsSinceEpoch}';
  String? _path, _instructionPath, _request;
  bool _loading = true, _starting = false, _heard = false, _text = false;
  bool _instruction = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _text = widget.review;
    WidgetsBinding.instance.addObserver(this);
    _audio.addListener(_audioChanged);
    unawaited(_load());
  }

  Future<String?> _resolve(String reference) =>
      widget.resolveMedia(widget.question.data['level'] as String, reference);

  Future<void> _load() async {
    final generation = ++_generation;
    String? path, instruction;
    try {
      path = await _resolve(widget.question.data['phonetic'] as String? ?? '');
      final descriptor = widget.question.presentation['instruction_audio'];
      if (descriptor is Map && descriptor['path_base'] == 'mp3' && descriptor['path'] is String) {
        instruction = await _resolve(descriptor['path'] as String);
      }
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'jlpt_test', operation: '读取听力媒体');
    }
    if (mounted && generation == _generation) {
      setState(() {
        _path = path; _instructionPath = instruction; _loading = false;
        if (path == null) _text = true;
      });
      if (path == null) widget.onHelp('text_help');
    }
  }

  @override
  void didUpdateWidget(covariant ListeningQuestion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id) {
      _stop();
      _heard = false; _text = widget.review; _loading = true;
      _path = null; _instructionPath = null;
      unawaited(_load());
    } else if (!oldWidget.review && widget.review) { _text = true; }
  }

  void _audioChanged() {
    if (!mounted || _request == null || _starting) return;
    if (_audio.lesson != _owner) {
      setState(() => _request = null);
      return;
    }
    if (_audio.error != null) {
      setState(() => _request = null);
      _message('音频播放失败，请重试。');
    } else if (_audio.completedId == _request) {
      final completedQuestion = !_instruction;
      setState(() { if (completedQuestion) _heard = true; _request = null; });
      if (completedQuestion) widget.onHelp('completed_audio');
    } else if (!_audio.active || _audio.paused) {
      _stop();
      setState(() {});
    }
  }

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _stopOwned() async {
    if (_audio.lesson != _owner) return;
    try { await _audio.stop(); }
    catch (error, stack) {
      SystemErrors.record(error, stack, module: 'jlpt_test', operation: '停止听力音频');
    }
  }

  void _stop() { _request = null; unawaited(_stopOwned()); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) { _stop(); if (mounted) setState(() {}); }
  }

  Future<void> _play({bool instruction = false}) async {
    if (_starting || _request != null) return;
    if (!instruction && (_heard || widget.audioCompleted)) return;
    final path = instruction ? _instructionPath : _path;
    if (path == null) return;
    final id = '$_owner-${DateTime.now().microsecondsSinceEpoch}';
    setState(() { _request = id; _instruction = instruction; _starting = true; });
    try {
      // Serialize a pending stop before starting a new native request.
      if (_audio.stopping) await _audio.stop();
      if (!mounted || _request != id) return;
      await _audio.start({
        'lesson': _owner, 'title': '${widget.question.typeName} · ${instruction ? '题型说明' : '听力'}',
        'albumTitle': 'J 听力', 'words': false, 'batch': false,
        'speed': 1.0, 'repeat': 1, 'intervalSteps': 0,
        'clips': [{'id': id, 'path': path}], 'startIndex': 0,
      });
      if (!mounted || _request != id) { await _stopOwned(); return; }
      if (!instruction && _audio.error == null) widget.onHelp('file_audio');
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'jlpt_test', operation: '播放听力音频');
      if (mounted && _request == id) {
        _request = null;
        _message('音频播放失败，请重试。');
        unawaited(_load());
      }
    } finally {
      _starting = false;
      if (mounted) { setState(() {}); _audioChanged(); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final allowText = widget.review || widget.mistakeReview || (!_loading && _path == null);
    final showTranscript = allowText && (_text || widget.review);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(_loading ? '正在读取音频' : _path == null ? '音频未提供' : '听力音频'),
        StudyButton.textIcon(onPressed: _loading || _path == null || _starting ||
            _request != null || _heard || widget.audioCompleted ? null : () => _play(),
          icon: Icon(_heard || widget.audioCompleted ? Icons.check_circle_outline : Icons.volume_up_outlined),
          label: Text(_request != null && !_instruction ? '正在播放' :
            _heard || widget.audioCompleted ? '已播放一次' : '播放')),
      ]),
      if (allowText) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
        if (allowText && _instructionPath != null) StudyButton.text(
          onPressed: _starting || _request != null ? null : () => _play(instruction: true),
          child: Text(_request != null && _instruction ? '正在播放说明' : '题型说明')),
        if (allowText) StudyButton.text(onPressed: () {
          setState(() => _text = !_text);
          if (_text) widget.onHelp('text_help');
        }, child: Text(_text ? '收起' : '文字稿')),
        ]),
      ],
      const SizedBox(height: 12),
      QuestionView(question: q, answer: widget.answer, onAnswer: widget.onAnswer,
        resolveMedia: widget.resolveMedia,
        review: widget.review, showTranscript: showTranscript,
        showListeningText: allowText, showPrompt: allowText,
        showOptions: true),
    ]);
  }

  @override
  void dispose() {
    _generation++;
    _audio.removeListener(_audioChanged);
    _stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

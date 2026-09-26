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
    this.review = false, this.explanationKey});
  final Question question;
  final String? answer;
  final ValueChanged<String>? onAnswer;
  final ValueChanged<String> onHelp;
  final Future<String?> Function(String, String) resolveMedia;
  final bool review;
  final Key? explanationKey;
  @override
  State<ListeningQuestion> createState() => _ListeningQuestionState();
}

class _ListeningQuestionState extends State<ListeningQuestion> with WidgetsBindingObserver {
  final _audio = NativeAudioTransport.instance;
  late final String _owner = 'jlpt_practice-${DateTime.now().microsecondsSinceEpoch}';
  String? _path, _instructionPath, _request;
  bool _loading = true, _starting = false, _heard = false, _text = false;
  bool _instruction = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _text = false;
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
      SystemErrors.record(error, stack, module: 'jlpt_practice', operation: '读取听力媒体');
    }
    if (mounted && generation == _generation) {
      setState(() { _path = path; _instructionPath = instruction; _loading = false; });
    }
  }

  @override
  void didUpdateWidget(covariant ListeningQuestion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id) {
      _stop();
      _heard = false; _text = false; _loading = true;
      _path = null; _instructionPath = null;
      unawaited(_load());
    }
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
      setState(() { if (!_instruction) _heard = true; _request = null; });
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
      SystemErrors.record(error, stack, module: 'jlpt_practice', operation: '停止听力音频');
    }
  }

  void _stop() { _request = null; unawaited(_stopOwned()); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) { _stop(); if (mounted) setState(() {}); }
  }

  Future<void> _play({bool instruction = false}) async {
    if (_starting) return;
    if (_request != null) { _stop(); setState(() {}); return; }
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
      SystemErrors.record(error, stack, module: 'jlpt_practice', operation: '播放听力音频');
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
    final accessible = _text;
    final heard = _heard || widget.answer != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(_loading ? '正在读取音频' : _path == null ? '音频未提供' : '听力音频'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        StudyButton.textIcon(onPressed: _loading || _path == null || _starting ? null : () => _play(),
          icon: Icon(_request == null ? Icons.volume_up_outlined : Icons.stop),
          label: Text(_request != null ? '停止' : '播放')),
        if (_instructionPath != null) StudyButton.text(
          onPressed: _starting ? null : () => _play(instruction: true),
          child: Text(_request != null && _instruction ? '停止' : '题型说明')),
        StudyButton.text(onPressed: () {
          setState(() => _text = !_text);
          if (_text) widget.onHelp('text_help');
        }, child: Text(_text ? '收起' : '文字稿')),
      ]),
      const SizedBox(height: 12),
      if (!heard && !accessible && q.presentation['prompt_timing'] == 'after_dialogue')
        const Padding(padding: EdgeInsets.only(bottom: 12),
          child: Text('设问在音频播放结束后显示；也可打开文字稿。')),
      QuestionView(question: q, answer: widget.answer, onAnswer: widget.onAnswer,
        resolveMedia: widget.resolveMedia,
        review: widget.review, showTranscript: _text,
        explanationKey: widget.explanationKey,
        showPrompt: accessible || heard || q.presentation['prompt_timing'] != 'after_dialogue',
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

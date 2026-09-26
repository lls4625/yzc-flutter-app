import '../../../system_errors.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../glass_ui.dart';
import 'package:flutter/services.dart';
import 'models.dart';
import 'question_view.dart';

/// Only the generic native speech transport is used. JLPT presentation and
/// progress stay in this feature; no old practice widgets or models are reused.
class ListeningQuestion extends StatefulWidget {
  const ListeningQuestion({super.key, required this.question, required this.answer,
    required this.onAnswer, required this.onHelp, this.review = false, this.showDemoTranscript = false});
  final Question question;
  final String? answer;
  final ValueChanged<String>? onAnswer;
  final ValueChanged<String> onHelp;
  final bool review, showDemoTranscript;
  @override
  State<ListeningQuestion> createState() => _ListeningQuestionState();
}

class _ListeningQuestionState extends State<ListeningQuestion> with WidgetsBindingObserver {
  static const _channel = MethodChannel('yuzhichu/practice_speech');
  String? _request;
  bool _heard = false, _text = false;
  @override
  void initState() {
    super.initState();
    _text = widget.review || widget.showDemoTranscript;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant ListeningQuestion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.showDemoTranscript && widget.showDemoTranscript) _text = true;
    if (!oldWidget.review && widget.review) _text = true;
  }

  Future<void> _stopNative(String id) async {
    try { await _channel.invokeMethod<void>('stop', {'id': id}); }
    on PlatformException catch (caughtError, caughtStack) {
      SystemErrors.record(caughtError, caughtStack, module: 'jlpt_test_demo', operation: '题目音频'); /* Already stopped or unavailable. */ }
    on MissingPluginException catch (caughtError, caughtStack) {
      SystemErrors.record(caughtError, caughtStack, module: 'jlpt_test_demo', operation: '题目音频'); /* Text adaptation remains available. */ }
  }

  void _stop() {
    final id = _request; _request = null;
    if (id != null) unawaited(_stopNative(id));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _stop(); if (mounted) setState(() {});
    }
  }

  Future<void> _play() async {
    if (_request != null) { _stop(); setState(() {}); return; }
    final q = widget.question;
    final id = 'jlpt-test-demo-${DateTime.now().microsecondsSinceEpoch}-${q.id}';
    setState(() => _request = id);
    final after = q.presentation['prompt_timing'] == 'after_dialogue';
    final segments = <String>[
      if (!after) q.stem,
      ...q.transcript.split('\n').where((line) => line.trim().isNotEmpty),
      if (after) q.stem,
      if (q.presentation['options_channel'] == 'spoken_text')
        for (final option in q.options) '${option['id']}。${option['text']}',
    ];
    widget.onHelp('synthetic_audio');
    try {
      await _channel.invokeMethod<void>('speak', {'id': id, 'segments': segments});
      if (mounted && _request == id) setState(() => _heard = true);
    } catch (caughtError, caughtStack) {
      SystemErrors.record(caughtError, caughtStack, module: 'jlpt_test_demo', operation: '题目音频', context: {'source': 'study_room/jlpt_test/demo/listening_question.dart'});
      if (mounted && _request == id) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('合成朗读暂不可用，可打开文字稿继续练习。')));
      }
    } finally {
      if (mounted && _request == id) setState(() => _request = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final accessible = _text || widget.review;
    final heard = _heard || widget.answer != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('听力适配 · 系统日语合成朗读，非正式录音'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        StudyButton.textIcon(onPressed: _play,
          icon: Icon(_request == null ? Icons.volume_up_outlined : Icons.stop),
          label: Text(_request != null ? '停止' : _heard ? '再次朗读' : '朗读题目')),
        StudyButton.text(onPressed: () {
          setState(() => _text = !_text);
          if (_text) widget.onHelp('text_help');
        }, child: Text(_text ? '收起文字稿' : '查看文字稿')),
      ]),
      const SizedBox(height: 12),
      if (!heard && !accessible && (q.presentation['prompt_timing'] == 'after_dialogue' ||
          q.presentation['options_channel'] == 'spoken_text'))
        const Padding(padding: EdgeInsets.only(bottom: 12),
          child: Text('此题的设问或选项在朗读结束后显示；也可打开文字稿。')),
      QuestionView(question: q, answer: widget.answer, onAnswer: widget.onAnswer,
        review: widget.review, showTranscript: _text,
        showPrompt: accessible || heard || q.presentation['prompt_timing'] != 'after_dialogue',
        showOptions: accessible || heard || q.presentation['options_channel'] != 'spoken_text'),
    ]);
  }

  @override
  void dispose() { _stop(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
}

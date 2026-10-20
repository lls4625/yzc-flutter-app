import '../../../l10n/l10n.dart';
import '../../../content_language.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ai_question.dart';
import '../../../data.dart';
import '../../../ios_lesson_playback.dart';
import '../../../practice_question_body.dart';
import '../../../system_errors.dart';
import '../../../ui.dart';
import '../../../user_error.dart';
import '../host.dart';
import 'open_practice_body.dart';
import '../image_interaction_config.dart';
import '../media_widgets.dart';
import '../video_controller.dart';
import '../tab_coordinator.dart';

typedef OpenPracticeSession = Future<void> Function(
  BuildContext context,
  String id,
);

/// Independent implementation of the course practice tab.
class CoursePracticeTab extends StatefulWidget {
  const CoursePracticeTab({
    required this.host,
    required this.book,
    required this.lesson,
    required this.coordinator,
    required this.openPractice,
    super.key,
  });
  final CourseTabHost host;
  final RowData book, lesson;
  final CourseTabCoordinator coordinator;
  final OpenPracticeSession openPractice;

  @override
  State<CoursePracticeTab> createState() => _CoursePracticeTabState();
}

class _CoursePracticeTabState extends State<CoursePracticeTab> {
  final _playback = IosLessonPlayback.instance;
  final _video = CourseVideoController();
  List<RowData> _questions = [], _pending = [];
  bool _loading = true, _busy = false, _resourceUpdating = false;
  String? _error;

  ContentLanguage get _language => ContentLanguage.fromTextbook(widget.book);
  String _relationLabel(Object? relation) => switch (relation) {
    'word' => context.tr('单词', '單字', 'Words', '単語'),
    'grammar' => context.tr('文法', '文法', 'Grammar', '文法'),
    'content' => context.tr('课文', '課文', 'Reading', '本文'),
    _ => context.tr('综合', '綜合', 'Mixed', '総合'),
  };
  String get _bookId => textOf(widget.book, 'id');
  String get _lessonId => textOf(widget.lesson, 'id');
  String get _identity => '$_bookId:$_lessonId:open-practice';
  bool get _ownsPlayback => _playback.lesson == _identity;
  bool get _blocked =>
      widget.host.resources.unavailable.contains(_bookId) ||
      widget.host.resources.activeBook == _bookId;

  @override
  void initState() {
    super.initState();
    widget.host.resources.addListener(_resourceChanged);
    _video.addListener(_videoChanged);
    widget.coordinator.attach(
      this,
      stopForTabChange: _stopForTabChange,
      stopVideo: _video.stop,
      videoFullscreen: () => _video.fullscreen,
      busy: _busy,
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.coordinator.detach(this);
    widget.host.resources.removeListener(_resourceChanged);
    _video.removeListener(_videoChanged);
    _video.dispose();
    super.dispose();
  }

  void _resourceChanged() {
    if (widget.host.resources.activeBook == _bookId) _resourceUpdating = true;
    if (_resourceUpdating && widget.host.resources.activeBook == null) {
      _resourceUpdating = false;
      unawaited(_load());
    }
    if (mounted) {
      setState(() {});
      _syncCoordinator();
    }
  }

  void _syncCoordinator() => widget.coordinator.update(
    this,
    busy: _busy || _video.busy || _playback.stopping,
  );
  void _videoChanged() {
    if (mounted) {
      setState(() {});
      _syncCoordinator();
    }
  }

  Future<void> _stopForTabChange() async {
    await _video.stop();
    if (_ownsPlayback) await _playback.stop();
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stack) {
      SystemErrors.record(
        error,
        stack,
        module: 'course_practice',
        operation: '练习页操作',
        context: {'textbook_id': _bookId, 'lesson_id': _lessonId},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          GlassSnackBar(
            content: Builder(
              builder: (context) => Text(context.ui(userError(error))),
            ),
          ),
        );
      }
    }
  }

  Future<void> _load() async {
    try {
      final questions = await widget.host.store.content(
        'yzc_ai_question',
        _bookId,
        _lessonId,
      );
      final history = await widget.host.store.history();
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _pending = history
            .where(
              (row) =>
                  row['type'] != 'review' &&
                  row['status'] != 'complete' &&
                  row['textbook_id'] == _bookId &&
                  row['lessons_id'] == _lessonId,
            )
            .toList();
        _loading = false;
        _error = null;
      });
      _syncCoordinator();
    } catch (error, stack) {
      SystemErrors.record(
        error,
        stack,
        module: 'course_practice',
        operation: '读取练习页签',
        context: {'textbook_id': _bookId, 'lesson_id': _lessonId},
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _error = userError(error, fallback: '练习内容读取失败');
        });
        _syncCoordinator();
      }
    }
  }

  Future<void> _open(String id) async {
    await widget.openPractice(context, id);
    if (mounted) await _load();
  }

  Future<void> _start({String? relation}) async {
    if (_busy || _blocked) return;
    setState(() => _busy = true);
    _syncCoordinator();
    await _perform(() async {
      if (_ownsPlayback) await _playback.stop();
      await _video.stop();
      final id = await widget.host.store.startPractice(
        _questions,
        relation: relation,
      );
      if (mounted) await _open(id);
    });
    if (mounted) {
      setState(() => _busy = false);
      _syncCoordinator();
    }
  }

  Future<void> _playAudio(
    RowData question, {
    String? filename,
    String? title,
  }) async {
    if (_busy || _blocked) return;
    setState(() => _busy = true);
    _syncCoordinator();
    await _perform(() async {
      await _video.stop();
      if (_playback.active) await _playback.stop();
      final path = filename == null
          ? await widget.host.resources.mediaPath(
              _bookId,
              textOf(question, 'media_src'),
              'audio',
            )
          : await widget.host.resources.audioPath(_bookId, filename);
      await _playback.start({
        'lesson': _identity,
        'title':
            title ??
            context.tr('开放练习听力', '開放練習聽力', 'Open exercise audio', '自由回答の音声'),
        'words': false,
        'batch': false,
        'speed': widget.host.speed,
        'repeat': 1,
        'intervalSteps': 0,
        'startIndex': 0,
        'clips': [
          {
            'id':
                'open-practice:${question['id']}:${filename ?? question['media_src']}',
            'path': path,
          },
        ],
      });
    });
    if (mounted) {
      setState(() => _busy = false);
      _syncCoordinator();
    }
  }

  Future<void> _playHotspot(RowData question, CourseImageHotspot hotspot) =>
      _playAudio(question, filename: hotspot.audioSource, title: hotspot.label);

  Future<void> _playVideo(RowData question) async {
    if (_busy || _blocked) return;
    await _video.play(
      id: textOf(question, 'id'),
      book: _bookId,
      resolvePath: () => widget.host.resources.mediaPath(
        _bookId,
        textOf(question, 'media_src'),
        'video',
      ),
      beforePlay: () async {
        if (_playback.active) await _playback.stop();
      },
    );
  }

  Widget _questionMedia(RowData question) {
    final type = textOf(question, 'media_type');
    if (type.isEmpty || type == 'text') return SizedBox.shrink();
    if (type == 'audio') {
      return Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: StudyButton.outlined(
          onPressed: _busy || _blocked ? null : () => _playAudio(question),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.volume_up_outlined),
              SizedBox(width: 8),
              Text(
                context.tr(
                  '播放听力材料',
                  '播放聽力材料',
                  'Play listening audio',
                  '聴解音声を再生',
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (type == 'image') {
      return CourseImageCard(
        source: textOf(question, 'media_src'),
        label: '开放练习插图',
        resolvePath: () => widget.host.resources.mediaPath(
          _bookId,
          textOf(question, 'media_src'),
          'image',
        ),
      );
    }
    if (type == 'interactive_image') {
      return CourseInteractiveImageCard(
        source: textOf(question, 'media_src'),
        label: '开放练习互动插图',
        mediaConfig: textOf(question, 'media_config'),
        resolvePath: () => widget.host.resources.mediaPath(
          _bookId,
          textOf(question, 'media_src'),
          'interactive_image',
        ),
        hotspotAvailable: (hotspot) =>
            widget.host.resources.hasAudio(_bookId, hotspot.audioSource),
        onActivate: (hotspot) => _playHotspot(question, hotspot),
        interactionEnabled: !_busy && !_blocked,
      );
    }
    if (type == 'video') {
      return CourseVideoCard(
        controller: _video,
        id: textOf(question, 'id'),
        source: textOf(question, 'media_src'),
        resolvePath: () => widget.host.resources.mediaPath(
          _bookId,
          textOf(question, 'media_src'),
          'video',
        ),
        onPlay: () => _playVideo(question),
        enabled: !_busy && !_blocked,
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Text(
        context.tr(
          '此开放练习媒体类型暂不支持',
          '此開放練習媒體類型暫不支援',
          'This exercise media type is not supported',
          'この練習のメディア形式には対応していません',
        ),
      ),
    );
  }

  Widget _openQuestion(RowData question, int index) => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${context.tr('开放练习', '開放練習', 'Open exercise', '自由回答')} ${index + 1} · ${_relationLabel(question['relation'])}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        SizedBox(height: 14),
        _questionMedia(question),
        OpenPracticeBody(
          textOf(question, 'content'),
          sourceLanguage: _language.sourceLanguage,
          explanationLanguage: _language.explanationLanguage,
          key: ValueKey('open-practice-${question['id']}'),
        ),
      ],
    ),
  );

  Widget _degradedQuestion(RowData question, int index) => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${context.tr('暂不可作答', '暫不可作答', 'Read only', '閲覧のみ')} ${index + 1} · ${_relationLabel(question['relation'])}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        SizedBox(height: 8),
        Text(
          context.tr(
            '这道题的选项或答案不完整，已从自动评分中排除。',
            '這道題的選項或答案不完整，已從自動評分中排除。',
            'This question has incomplete choices or answers and is excluded from automatic scoring.',
            '選択肢または正解が不完全なため、この問題は自動採点の対象外です。',
          ),
          style: TextStyle(color: Colors.orange),
        ),
        SizedBox(height: 14),
        _questionMedia(question),
        PracticeQuestionBody(
          textOf(question, 'content'),
          sourceLanguage: _language.sourceLanguage,
          explanationLanguage: _language.explanationLanguage,
          key: ValueKey('degraded-practice-${question['id']}'),
        ),
      ],
    ),
  );

  Widget _card(Widget child) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: StudyPanel(
        color: dark ? Color(0xFF252525) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Center(child: StudyCircularProgressIndicator());
    if (_error != null)
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.ui(_error!), textAlign: TextAlign.center),
              SizedBox(height: 16),
              StudyButton.filled(
                onPressed: _load,
                child: Text(
                  context.tr(
                    '重新读取练习',
                    '重新讀取練習',
                    'Reload exercises',
                    '練習を再読み込み',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    final openQuestions = _questions.where(isOpenDisplayQuestion).toList();
    final choiceQuestions = _questions.where(isAnswerableQuestion).toList();
    final degradedQuestions = _questions
        .where((row) => questionAnswerMode(row).degraded)
        .toList();
    final counts = {
      for (final relation in questionRelations)
        relation: choiceQuestions
            .where((row) => row['relation'] == relation)
            .length,
    };
    final quota = practiceQuota(choiceQuestions);
    final ready = quota.entries.every(
      (entry) => counts[entry.key]! >= entry.value,
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 20),
      children: [
        _card(
          Text(
            context.tr(
              '题目可能存在错误，请自行校对，内容仅供参考。',
              '題目可能存在錯誤，請自行核對，內容僅供參考。',
              'Questions may contain errors. Please check them; the content is for reference.',
              '問題に誤りがある場合があります。内容は参考として、各自で確認してください。',
            ),
            style: TextStyle(fontSize: 14, color: Colors.red),
          ),
        ),
        if (openQuestions.isNotEmpty) ...[
          _card(
            Text(
              context.tr(
                '本课有 ${openQuestions.length} 道开放练习。请自行口头或纸笔作答，App 不记录作答、不判对错。',
                '本課有 ${openQuestions.length} 道開放練習。請自行口頭或紙筆作答，App 不記錄作答、不判對錯。',
                'This lesson has ${openQuestions.length} open exercises. Answer aloud or on paper. The app does not record or score these answers.',
                'この課には自由回答の練習が ${openQuestions.length} 問あります。口頭または紙に回答してください。アプリは回答を記録・採点しません。',
              ),
            ),
          ),
          for (var i = 0; i < openQuestions.length; i++)
            _openQuestion(openQuestions[i], i),
        ],
        if (degradedQuestions.isNotEmpty) ...[
          _card(
            Text(
              context.tr(
                '本课有 ${degradedQuestions.length} 道题数据不完整，可阅读题干，不记录作答也不自动判分。',
                '本課有 ${degradedQuestions.length} 道題資料不完整，可閱讀題幹，不記錄作答也不自動評分。',
                '${degradedQuestions.length} questions have incomplete data. You can read them, but answers are not recorded or scored.',
                '${degradedQuestions.length} 問のデータが不完全です。問題文は読めますが、回答は記録・採点されません。',
              ),
            ),
          ),
          for (var i = 0; i < degradedQuestions.length; i++)
            _degradedQuestion(degradedQuestions[i], i),
        ],
        if (choiceQuestions.isNotEmpty)
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr(
                    '客观练习：${choiceQuestions.length} 题',
                    '客觀練習：${choiceQuestions.length} 題',
                    'Scored exercises: ${choiceQuestions.length}',
                    '採点対象：${choiceQuestions.length} 問',
                  ),
                ),
                Text(
                  counts.entries
                      .map(
                        (entry) =>
                            '${_relationLabel(entry.key)}: ${entry.value}',
                      )
                      .join(' · '),
                ),
                Text(
                  context.tr(
                    '每次综合练习10题',
                    '每次綜合練習10題',
                    '10 questions per mixed practice',
                    '総合練習は毎回10問',
                  ),
                ),
                Text(
                  quota.entries
                      .map(
                        (entry) =>
                            '${_relationLabel(entry.key)}: ${entry.value}',
                      )
                      .join(' · '),
                ),
                SizedBox(height: 12),
                if (_pending.isNotEmpty)
                  StudyButton.outlined(
                    onPressed: _busy
                        ? null
                        : () => _open(textOf(_pending.first, 'id')),
                    child: Text(
                      '${context.tr('继续未完成练习', '繼續未完成練習', 'Resume practice', '練習を再開')} (${_pending.first['answered']}/${_pending.first['count']})',
                    ),
                  ),
                if (_pending.isNotEmpty && ready) SizedBox(height: 20),
                if (ready)
                  StudyButton.filled(
                    onPressed: _busy || _blocked ? null : _start,
                    child: Text(
                      _busy
                          ? context.tr('准备中', '準備中', 'Preparing', '準備中')
                          : context.tr(
                              '开始随机练习',
                              '開始隨機練習',
                              'Start random practice',
                              'ランダム練習を開始',
                            ),
                    ),
                  )
                else
                  Text(
                    context.tr(
                      '客观题尚未齐备，暂不能开始随机练习。',
                      '客觀題尚未齊備，暫不能開始隨機練習。',
                      'There are not enough scored questions to start random practice.',
                      '採点対象の問題が不足しているため、ランダム練習を開始できません。',
                    ),
                  ),
                for (final relation in questionRelations)
                  if (counts[relation]! > 0) ...[
                    SizedBox(height: 12),
                    StudyButton.outlined(
                      onPressed: _busy || _blocked
                          ? null
                          : () => _start(relation: relation),
                      child: Text(
                        '${_relationLabel(relation)} · ${context.tr('最多', '最多', 'Up to', '最大')} ${relation == 'content' ? 3 : 10}',
                      ),
                    ),
                  ],
              ],
            ),
          ),
        if (_questions.isEmpty)
          _card(
            Text(
              context.tr(
                '本课练习题正在整理中。',
                '本課練習題正在整理中。',
                'Exercises for this lesson are being prepared.',
                'この課の練習問題は準備中です。',
              ),
            ),
          ),
      ],
    );
  }
}

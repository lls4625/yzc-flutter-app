import 'lesson_presentation.dart';
import 'content_typography.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'playback_scaffold.dart';
import 'package:flutter/services.dart';
import 'data.dart';
import 'resources.dart';
import 'resource_operation_ui.dart';
import 'resource_transfer.dart';
import 'ios_lesson_playback.dart';
import 'startup_network.dart';
import 'privacy_policy_page.dart';
import 'ui.dart';
import 'ai_question.dart';
import 'practice_question_body.dart';
import 'user_error.dart';
import 'system_errors.dart';
import 'system_error_page.dart';
import 'notice/feature/notice_service.dart';
import 'notice/feature/notice_ui.dart';
import 'developer_tip/feature/developer_tip.dart';
import 'basic_knowledge/feature/basic_knowledge.dart';
import 'course/feature/image_interaction_config.dart';
import 'course/feature/video_controller.dart';
import 'course/feature/media_widgets.dart';
import 'course/feature/host.dart';
import 'course/feature/page.dart';
import 'route_observer.dart';

import 'study_room/study_room_module.dart';
import 'study_room/resources/manager.dart';
import 'study_room/resources/page.dart';

class AppController extends ChangeNotifier implements CourseTabHost {
  AppController(this.store, this.resources);
  final AppStore store;
  late final notices = NoticeService(store);
  String get appVersionLabel => store.appVersion.isEmpty ? '版本信息不可用' : store.appVersion;
  final Resources resources;
  late final studyResources = StudyResources(store);
  final network = StartupNetwork();
  bool hasLocalTextbooks = false;
  VoidCallback? openStudyRoomPurchase;
  late final studyRoomPurchase = StudyRoomPurchaseController()..addListener(notifyListeners);
  late final developerTip = DeveloperTipController()..addListener(notifyListeners);
  bool get studyRoomUnlocked => studyRoomPurchase.unlocked;
  bool get studyRoomPurchaseSaving => studyRoomPurchase.saving;
  late final studyRoomHost = StudyRoomHost(
    userId: store.userId, rootPath: store.root.path, contentDatabasePath: store.db.path,
    changes: Listenable.merge([this, resources, studyResources]),
    database: store.db, write: store.write, newId: store.newId, resources: studyResources,
    isUnlocked: () => studyRoomUnlocked, isPurchaseSaving: () => studyRoomPurchaseSaving,
    isBookUnavailable: (book) => resources.unavailable.contains(book),
    audioPath: resources.audioPath, playbackSpeed: () => speed,
    openPurchase: () => openStudyRoomPurchase?.call(),
  );
  RowData settings = {}, position = {}, stats = {};
  // Full reloads invalidate the home snapshot; time-only statistics do not.
  int _homeDataRevision = 0;
  int get homeDataRevision => _homeDataRevision;
  Future<void> reload() => store.write(() async {
    settings = await store.setting();
    await studyRoomPurchase.reload();
    await developerTip.reload();
    position = await store.position();
    stats = await store.statistics();
    hasLocalTextbooks = (await resources.installations()).any((row) =>
      row['status'] == 'ready' && !resources.unavailable.contains(textOf(row, 'textbook_id')));
    _homeDataRevision++;
    notifyListeners();
  });
  Future<void> refreshReviewStatistics() => store.write(() async {
    final next = {...stats, ...await store.reviewStatistics()};
    if (mapEquals(stats, next)) return;
    stats = next;
    notifyListeners();
  });
  Future<void> refreshTimeStatistics() => store.write(() async {
    final next = await store.statistics();
    if (mapEquals(stats, next)) return;
    stats = next;
    notifyListeners();
  });
  Future<void> setting(String key, Object value) async {
    await store.setSetting(key, value);
    await reload();
  }
  bool get ruby => intOf(settings, 'show_ruby', 1) == 1;
  bool get source => intOf(settings, 'show_source', 1) == 1;
  bool get translation => intOf(settings, 'show_definition', 1) == 1;
  double get speed => intOf(settings, 'playback_speed', 10) / 10;
  int get fontScale {
    final value = intOf(settings, 'font_scale');
    return validFontScale(value) ? value : 0;
  }

  @override
  void dispose() {
    studyRoomPurchase.removeListener(notifyListeners);
    studyRoomPurchase.dispose();
    developerTip.removeListener(notifyListeners);
    developerTip.dispose();
    super.dispose();
  }
}

Future<void> perform(BuildContext context, Future<void> Function() action) async {
  try { await action(); } catch (e, stack) {
    SystemErrors.record(e, stack, module: 'app', operation: '页面操作');
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(GlassSnackBar(content: Text(userError(e))));
  }
}
void openPage(BuildContext context, Widget page) {
  Navigator.of(context).push(page is CourseLessonPage
    ? _LessonPageRoute(builder: (_) => page)
    : MaterialPageRoute<void>(builder: (_) => page));
}

class _LessonPageRoute extends MaterialPageRoute<void> {
  _LessonPageRoute({required super.builder});

  @override
  bool get popGestureEnabled => false;
}

int lessonPercent(List<RowData> progress, String lessonId) {
  final count = progress.where((r) => r['lessons_id'] == lessonId && ['word', 'content', 'grammar'].contains(r['category'])).map((r) => r['category']).toSet().length;
  return count == 3 ? 100 : count * 33;
}

Color bookColor(RowData book) {
  final intermediate = intOf(book, 'lvl', 1) > 1 || textOf(book, 'textbook').contains('中级');
  final second = textOf(book, 'volume').contains('下');
  return intermediate ? (second ? const Color(0xFF294A61) : const Color(0xFF365D74)) : (second ? const Color(0xFF9B4036) : const Color(0xFFB55345));
}

String chineseNumber(int number) {
  const values = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十', '十一', '十二'];
  return number >= 0 && number < values.length ? values[number] : '$number';
}

class StudyApp extends StatelessWidget {
  const StudyApp(this.app, {super.key});
  final AppController app;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: app, builder: (_, __) => MaterialApp(
    title: '语之初', debugShowCheckedModeBanner: false,
    navigatorObservers: [appRouteObserver, courseRouteObserver],
    theme: studyTheme(Brightness.light),
    darkTheme: studyTheme(Brightness.dark),
    themeMode: switch (textOf(app.settings, 'theme')) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system },
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: app.fontScale == 0
        ? MediaQuery.textScalerOf(context) : TextScaler.linear(app.fontScale / 100)),
      child: PlaybackLifecycle(child: studyGlassPageScope(context, child ?? const SizedBox.shrink()))),
    home: Welcome(app),
  ));
}

class Welcome extends StatefulWidget {
  const Welcome(this.app, {super.key});
  final AppController app;
  @override
  State<Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<Welcome> {
  Timer? _timer;
  int _secondsRemaining = 5;
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _entered) return;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _entered) return;
        if (_secondsRemaining <= 1) {
          _enterHome();
        } else {
          setState(() => _secondsRemaining--);
        }
      });
    });
  }

  void _enterHome() {
    if (!mounted || _entered) return;
    _timer?.cancel();
    setState(() => _entered = true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_entered) return NoticeHost(service: widget.app.notices, child: HomeShell(widget.app));
    return PlaybackScaffold(
      body: SafeArea(child: LayoutBuilder(builder: (context, viewport) => SingleChildScrollView(
      padding: const EdgeInsets.all(28), child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: math.max(0.0, viewport.maxHeight - 56)),
        child: IntrinsicHeight(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Spacer(),
    ClipRRect(borderRadius: BorderRadius.circular(24), child: Image.asset('assets/branding/app-icon.png', width: 72, height: 72, fit: BoxFit.cover)),
    const SizedBox(height: 28),
    Text('语言之初，\n从这里生长。', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700, height: 1.18)),
    const SizedBox(height: 14),
    Text('从一本内容、一段声音开始，让词汇、语法与表达慢慢生根。', style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.7, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    const Spacer(),
    Text('$_secondsRemaining 秒后自动进入', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
    const SizedBox(height: 22),
    SizedBox(width: double.infinity, child: StudyButton.filled(onPressed: _enterHome, child: const Text('开始学习'))),
    const SizedBox(height: 10),
    Center(child: Text('无需账号 · 全部学习记录保存在本机', style: Theme.of(context).textTheme.bodySmall)),
  ])))))));
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell(this.app, {super.key});
  final AppController app;
  @override
  State<HomeShell> createState() => _HomeShellState();
}
class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver, RouteAware {
  static const _studyRoomTab = 4;
  int tab = 0;
  int _courseVisit = 0;
  final _profileScrollController = ScrollController();
  final _purchaseSectionKey = GlobalKey();
  Timer? _statisticsTimer;
  ModalRoute<dynamic>? _route;
  bool _foreground = true, _routeVisible = true;
  bool _refreshingStatistics = false, _refreshStatisticsAgain = false;
  bool get _statisticsVisible => mounted && _foreground && _routeVisible && (tab == 0 || tab == 3);

  @override
  void initState() {
    super.initState();
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.app.addListener(_scheduleStatisticsRefresh);
    widget.app.openStudyRoomPurchase = _openStudyRoomPurchase;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route != route) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      _routeVisible = route?.isCurrent ?? true;
      if (route != null) appRouteObserver.subscribe(this, route);
    }
  }
  @override
  void didUpdateWidget(HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != widget.app) {
      oldWidget.app.openStudyRoomPurchase = null;
      widget.app.openStudyRoomPurchase = _openStudyRoomPurchase;
      oldWidget.app.removeListener(_scheduleStatisticsRefresh);
      widget.app.addListener(_scheduleStatisticsRefresh);
      _requestStatisticsRefresh();
    }
  }
  @override
  void didPush() => _requestStatisticsRefresh();
  @override
  void didPushNext() {
    _routeVisible = false;
    _statisticsTimer?.cancel();
  }
  @override
  void didPopNext() {
    _routeVisible = true;
    _requestStatisticsRefresh();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _requestStatisticsRefresh();
  }

  void _selectTab(int value) {
    if (value == _studyRoomTab) unawaited(widget.app.studyResources.check());
    if (tab == value) {
      if (value == 1) setState(() => _courseVisit++);
      return;
    }
    setState(() {
      tab = value;
      if (value == 1) _courseVisit++;
    });
    _requestStatisticsRefresh();
  }

  // Open purchase details directly from the current page.
  void _openStudyRoomPurchase() {
    if (!mounted) return;
    openPage(context, StudyRoomPurchasePage(widget.app.studyRoomPurchase));
  }

  void _requestStatisticsRefresh() {
    _statisticsTimer?.cancel();
    if (_statisticsVisible) unawaited(_refreshStatistics());
  }

  Future<void> _refreshStatistics() async {
    if (_refreshingStatistics) {
      _refreshStatisticsAgain = true;
      return;
    }
    _refreshingStatistics = true;
    try {
      do {
        _refreshStatisticsAgain = false;
        await widget.app.refreshTimeStatistics();
      } while (_refreshStatisticsAgain && _statisticsVisible);
      _scheduleStatisticsRefresh();
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'app', operation: '刷新学习统计');
      // Retry on re-entry/resume; a failed query must not start a rapid loop.
      _statisticsTimer?.cancel();
      if (_statisticsVisible) ScaffoldMessenger.of(context).showSnackBar(
        GlassSnackBar(content: const Text('学习统计刷新失败，请重新进入页面重试')));
    } finally {
      _refreshingStatistics = false;
    }
  }

  void _scheduleStatisticsRefresh() {
    _statisticsTimer?.cancel();
    if (!_statisticsVisible) return;
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
    final nextDue = intOf(widget.app.stats, 'next_review_time');
    final next = nextDue > 0 ? math.min(nextDue, midnight) : midnight;
    final delay = next - now.millisecondsSinceEpoch;
    _statisticsTimer = Timer(Duration(milliseconds: delay > 0 ? delay : 1), _requestStatisticsRefresh);
  }
  @override
  void dispose() {
    _statisticsTimer?.cancel();
    widget.app.removeListener(_scheduleStatisticsRefresh);
    widget.app.openStudyRoomPurchase = null;
    _profileScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => PlaybackScaffold(
    backgroundColor: tab == _studyRoomTab
      ? (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF25231F) : const Color(0xFFF3E9D6))
      : null,
    body: IndexedStack(index: tab, children: [HomePanel(widget.app, onNavigate: _selectTab), CoursePanel(widget.app, key: ValueKey('course-$_courseVisit')), ReviewPanel(widget.app, active: tab == 2),
      ProfilePanel(widget.app, scrollController: _profileScrollController, purchaseSectionKey: _purchaseSectionKey),
      StudyRoomModule(widget.app.studyRoomHost)]),
    bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
      StudyNavigationBar(selectedIndex: tab, isStudyRoomUnlocked: widget.app.studyRoomUnlocked,
        onDestinationSelected: (value) async {
      if (value == 1 && textOf(widget.app.position, 'textbook_id').isEmpty) {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LibraryPage(widget.app)));
      }
      if (mounted) _selectTab(value);
    }),
    ]),
  );
}

class HomePanel extends StatefulWidget {
  const HomePanel(this.app, {super.key, required this.onNavigate});
  final AppController app;
  final ValueChanged<int> onNavigate;
  @override
  State<HomePanel> createState() => _HomePanelState();
}

class _HomePanelState extends State<HomePanel> {
  RowData? book, current;
  List<RowData> lessons = [], progressRows = [];
  int mistakeCount = 0, completedTotal = 0, completedPractices = 0;
  String? error;
  int _request = 0, _observedRevision = -1;
  bool loading = true, canResume = false, resourceReady = false;
  bool _hasSnapshot = false, _loadAgain = false;
  String? _loadingBookId;
  String _loadedBookId = '';
  @override
  void initState() {
    super.initState();
    widget.app.addListener(_changed);
    _changed();
  }
  void _changed() {
    if (!mounted) return;
    if (_observedRevision != widget.app.homeDataRevision) {
      _observedRevision = widget.app.homeDataRevision;
      unawaited(_load());
    } else {
      // Statistics and purchase notifications do not invalidate course data.
      setState(() {});
    }
  }
  @override
  void didUpdateWidget(HomePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app == widget.app) return;
    oldWidget.app.removeListener(_changed);
    widget.app.addListener(_changed);
    _request++;
    _loadingBookId = null;
    _hasSnapshot = false;
    _observedRevision = -1;
    _changed();
  }
  Future<void> _load() async {
    if (!mounted) return;
    final bookId = textOf(widget.app.position, 'textbook_id');
    if (_loadingBookId == bookId) {
      // Finish this request, discard its stale result, then fetch once more.
      _loadAgain = true;
      return;
    }
    final request = ++_request;
    _loadingBookId = bookId;
    _loadAgain = false;
    setState(() { loading = true; error = null; });
    try {
      final store = widget.app.store;
      final result = await Future.wait<List<RowData>>([
        store.db.query('yzc_textbook', where: 'id=?', whereArgs: [bookId]),
        store.lessons(bookId),
        store.progress(bookId),
        store.homeOverviewCounts(),
        store.bookPosition(bookId),
      ]);
      final installed = bookId.isEmpty ? null : await widget.app.resources.installation(bookId);
      if (!mounted || request != _request || _loadAgain ||
          bookId != textOf(widget.app.position, 'textbook_id')) return;
      final saved = result[4].isEmpty ? null : result[4].single;
      final matches = result[1].where((r) => r['id'] == saved?['lessons_id']);
      final counts = result[3].single;
      setState(() {
        book = result[0].isEmpty ? null : result[0].single;
        lessons = result[1]; progressRows = result[2];
        current = matches.isNotEmpty ? matches.first : lessons.isEmpty ? null : lessons.first;
        canResume = matches.isNotEmpty;
        resourceReady = installed?['status'] == 'ready' && !widget.app.resources.unavailable.contains(bookId);
        _loadedBookId = bookId; _hasSnapshot = true; loading = false;
        completedPractices = intOf(counts, 'completed_practices');
        mistakeCount = intOf(counts, 'mistakes');
        completedTotal = intOf(counts, 'completed_lessons'); error = null;
      });
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'app', operation: '读取学习概览');
      if (mounted && request == _request && !_loadAgain) setState(() {
        loading = false; error = userError(e, fallback: '学习数据读取失败');
      });
    } finally {
      if (mounted && request == _request) {
        _loadingBookId = null;
        if (_loadAgain || bookId != textOf(widget.app.position, 'textbook_id')) {
          unawaited(_load());
        }
      }
    }
  }
  Future<void> _continue() async {
    if (loading || error != null || _loadedBookId != textOf(widget.app.position, 'textbook_id')) return;
    final request = _request;
    final book = this.book, current = this.current;
    if (book == null || current == null) { openPage(context, LibraryPage(widget.app)); return; }
    final installed = await widget.app.resources.installation(textOf(book, 'id'));
    if (!mounted || request != _request || loading || _loadedBookId != textOf(widget.app.position, 'textbook_id')) return;
    if (installed?['status'] != 'ready' || widget.app.resources.unavailable.contains(book['id'])) {
      openPage(context, LibraryPage(widget.app));
    } else {
      openPage(context, CourseLessonPage(widget.app, book, current,
        openPractice: (context, id) => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => PracticePage(widget.app, id)))));
    }
  }
  @override
  void dispose() { widget.app.removeListener(_changed); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final hasCurrentSnapshot = _hasSnapshot && _loadedBookId == textOf(widget.app.position, 'textbook_id');
    final book = hasCurrentSnapshot ? this.book : null;
    final current = hasCurrentSnapshot ? this.current : null;
    final lessons = hasCurrentSnapshot ? this.lessons : <RowData>[];
    final currentLabel = current == null ? '' : lessonLabel(current);
    final progress = current == null ? 0.0 : lessonPercent(progressRows, textOf(current, 'id')) / 100;
    final completed = lessons.where((row) => lessonPercent(progressRows, textOf(row, 'id')) == 100).length;
    final textbookProgress = lessons.isEmpty ? 0.0 : completed / lessons.length;
    final waiting = error == null && !hasCurrentSnapshot;
    final unavailable = !resourceReady || widget.app.resources.unavailable.contains(_loadedBookId);
    final studyHint = waiting ? '正在读取所选内容…' : error != null && !hasCurrentSnapshot ? '学习数据读取失败，请重试'
      : book == null ? '请选择内容开始学习' : unavailable ? '学习资源不可用，请前往内容选择页处理'
      : current == null ? '本内容暂无课程，请前往内容选择页' : '';
    return PageBody(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_fire_department, color: Colors.orange),
                  Text(
                    ' ${intOf(widget.app.stats, 'streak')} 天',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                _greeting(),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '今日も、言葉のはじまり。',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'), fontSize: 20, fontWeight: FontWeight.w600, height: 1.4),
        ),
        const SizedBox(height: 20),
        if (!waiting && studyHint.isNotEmpty) StudyCard(child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(children: [
            Expanded(child: Text(studyHint)),
          ]),
        )) else Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [indigo, Color(0xFF526D82)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book == null
                    ? '当前学习课程'
                    : '当前学习课程 · ${textOf(book, 'textbook')} ${textOf(book, 'volume')}${currentLabel.isEmpty ? '' : ' · $currentLabel'}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 6),
              Text(
                waiting ? '正在读取所选内容…' : current == null ? '请选择内容开始学习' : textOf(current, 'title'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontFamily: waiting || current == null ? 'PingFang SC' : 'Hiragino Sans', locale: waiting || current == null ? const Locale('zh', 'CN') : const Locale('ja', 'JP'),
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!waiting && book == null) ...[
                const SizedBox(height: 5),
                const Text(
                  '完成单词、课文、文法后，本课进度为 100%',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
              const SizedBox(height: 18),
              const Text('课程进度', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: StudyLinearProgressIndicator(
                        value: progress,
                        minHeight: 9,
                        backgroundColor: Colors.white24,
                        color: const Color(0xFFF4C95D),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    waiting ? '—%' : '${(progress * 100).round()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text('内容进度', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: StudyLinearProgressIndicator(
                        value: textbookProgress,
                        minHeight: 9,
                        backgroundColor: Colors.white24,
                        color: const Color(0xFFF4C95D),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    waiting ? '—/—' : '$completed/${lessons.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (error != null) StudyButton.text(onPressed: () => unawaited(_load()),
          child: Text(hasCurrentSnapshot ? '刷新失败，当前显示上次数据，点击重试' : '学习概览读取失败，点击重试')),
        const SectionTitle('快捷学习'),
        StudyCardRow(
          children: [
            Expanded(
              child: QuickCard(
                icon: Icons.play_arrow_rounded,
                title: waiting ? '正在加载' : error != null && !hasCurrentSnapshot ? '暂不可用'
                    : studyHint.isNotEmpty ? '选择内容' : canResume ? '继续学习' : '开始学习',
                subtitle: studyHint.isNotEmpty
                    ? studyHint
                    : current == null ? '请选择内容开始学习' : '${lessonLabel(current)} · ${textOf(current, 'title')}',
                subtitleColor: Colors.grey,
                subtitleMaxLines: 1,
                onTap: () => perform(context, _continue),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: QuickCard(
                icon: Icons.refresh,
                title: '到期复习',
                subtitle: '${intOf(widget.app.stats, 'due')} 张卡片',
                onTap: () => widget.onNavigate(2),
              ),
            ),
          ],
        ),
        const SectionTitle('学习概览'),
        StudyCardRow(children: [
          Expanded(child: QuickCard(
            icon: Icons.assignment_outlined,
            title: '练习记录',
            subtitle: '$completedPractices 次练习已完成',
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => HistoryPage(widget.app),
            )),
          )),
          const SizedBox(width: 12),
          Expanded(child: QuickCard(
            icon: Icons.error_outline,
            title: '错题记录',
            subtitle: '$mistakeCount 道历史错题',
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => HistoryPage(widget.app, mistakes: true),
            )),
          )),
        ]),
        const SizedBox(height: 12),
        StudyCardRow(
          children: [
            Expanded(
              child: StudyStat(
                value:
                    '$completedTotal',
                label: '完成课程',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StudyStat(value: '${intOf(widget.app.stats, 'total')}', label: '累计答题'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StudyStat(
                value: '${(intOf(widget.app.stats, 'total') == 0 ? 0 : (intOf(widget.app.stats, 'correct') * 100 / intOf(widget.app.stats, 'total')).round())}%',
                label: '正确率',
              ),
            ),
          ],
        ),
        const SectionTitle('学习建议'),
        StudyCard(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline, color: vermilion),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    intOf(widget.app.stats, 'due') > 0
                        ? '有 ${intOf(widget.app.stats, 'due')} 张卡片需要复习。先回忆再看答案，记忆会更牢。'
                        : '今天没有到期卡片。完成一课，让新知识进入复习计划吧！',
                    style: const TextStyle(height: 1.55),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12
        ? '早上好'
        : h < 18
        ? '下午好'
        : '晚上好';
  }
}

class LibraryPage extends StatefulWidget {
  const LibraryPage(this.app, {super.key});
  final AppController app;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}
class _LibraryPageState extends State<LibraryPage> with WidgetsBindingObserver {
  List<RowData> books = [];
  Map<String, RowData> localBooks = {};
  Map<String, RowData> installed = {};
  Map<String, int> lessonCounts = {};
  bool fetching = false, selecting = false;
  String? _operatingBookId;
  String _operationLabel = '资源处理';
  String? error;
  bool _errorNeedsRecheck = false;
  bool permissionError = false;
  bool _refreshAgain = false;
  bool? _serverReady;
  int _checkRevision = 0;
  bool _leaving = false, _wasResourceActive = false;
  bool get _pageCurrent => mounted && !_leaving && ModalRoute.of(context)?.isCurrent == true;
  bool get _operationBusy => selecting || widget.app.resources.activeBook != null;
  bool get _canLeaveDownload => widget.app.resources.activeBook != null && widget.app.resources.stage != 'delete';
  bool get _resourceBusy => fetching || _operationBusy;
  bool _checkCurrent(int revision) => _pageCurrent && revision == _checkRevision && !_operationBusy;
  bool _canDownload(RowData book) {
    final id = textOf(book, 'id');
    final remote = widget.app.resources.publishedTextbook(id);
    return _serverReady != false && remote != null &&
        !widget.app.resources.hasInvalidPublishedTextbookHash(id) && textOf(remote, 'sfky') == '1';
  }
  @override
  void initState() {
    super.initState();
    error = widget.app.resources.lastError;
    _wasResourceActive = widget.app.resources.activeBook != null;
    widget.app.resources.addListener(_resourceChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (_operationBusy) { unawaited(_local()); }
        else { unawaited(_refresh()); }
      }
    });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ModalRoute.of(context)?.isCurrent == true) {
      if (_resourceBusy) { _refreshAgain = true; } else { unawaited(_refresh()); }
    }
  }
  void _resourceChanged() {
    final active = widget.app.resources.activeBook != null;
    final finished = _wasResourceActive && !active;
    _wasResourceActive = active;
    if (finished && mounted) unawaited(_reloadFinishedResource());
  }
  Future<void> _reloadFinishedResource() async {
    try {
      await _local();
      if (mounted) setState(() => error = widget.app.resources.lastError);
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'app', operation: '刷新已完成的资源任务');
      if (mounted) setState(() => error = '资源状态读取失败，请刷新重试。');
    }
  }
  @override
  void dispose() {
    widget.app.resources.removeListener(_resourceChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  Future<bool> _checkConnection({int? checkRevision}) async {
    bool current() => _pageCurrent && (checkRevision == null || _checkCurrent(checkRevision));
    if (!current()) return false;
    final server = await widget.app.network.checkServer();
    if (!current()) return false;
    setState(() {
      _serverReady = server.ready;
      permissionError = server.permissionDenied;
      _errorNeedsRecheck = permissionError || server.networkError;
      error = [
        if (!server.ready) '${server.title}。',
        if (!server.ready && server.detail.isNotEmpty) server.detail,
      ].join('\n');
      if (error!.isEmpty) error = null;
    });
    // A cellular restriction must not block a working Wi-Fi server connection.
    return server.ready;
  }
  Future<void> _openNetworkSettings() async {
    final opened = await widget.app.network.openSettings();
    if (!opened && _pageCurrent) {
      setState(() {
        error = '请手动打开系统设置，找到“语之初”，检查无线数据设置。';
        _errorNeedsRecheck = true;
      });
    }
  }
  void _finishFetching() {
    if (!mounted) return;
    setState(() => fetching = false);
    _resumeRefresh();
  }
  void _finishOperation() {
    if (!mounted) return;
    setState(() { selecting = false; _operatingBookId = null; _operationLabel = '资源处理'; });
    _resumeRefresh();
  }
  void _resumeRefresh() {
    if (_refreshAgain && _pageCurrent && !_resourceBusy) {
      _refreshAgain = false;
      unawaited(_refresh());
    }
  }
  Future<void> _local({int? checkRevision}) async {
    final rows = await widget.app.store.textbooks();
    final localById = {for (final row in rows) textOf(row, 'id'): row};
    final published = widget.app.resources.publishedTextbooks;
    final publishedIds = {for (final row in published) textOf(row, 'id')};
    final combined = <RowData>[
      if (widget.app.resources.hasPublishedCatalog) ...published,
      for (final row in rows)
        if (!publishedIds.contains(textOf(row, 'id'))) row,
    ];
    final installs = await widget.app.resources.installations();
    final counts = await widget.app.store.db.rawQuery('SELECT textbook_id,COUNT(*) count FROM yzc_lessons GROUP BY textbook_id');
    if (mounted && (checkRevision == null || _checkCurrent(checkRevision))) setState(() {
      books = combined;
      localBooks = localById;
      installed = {for (final r in installs) textOf(r, 'textbook_id'): r};
      lessonCounts = {for (final r in counts) textOf(r, 'textbook_id'): intOf(r, 'count')};
    });
  }
  Future<void> _refresh() async {
    if (_resourceBusy || !_pageCurrent) return;
    final revision = ++_checkRevision;
    setState(() { fetching = true; error = widget.app.resources.lastError; permissionError = false; });
    try {
      widget.app.resources.clearPublishedTextbooks();
      await _local(checkRevision: revision);
      if (!_checkCurrent(revision)) return;
      if (!(await _checkConnection(checkRevision: revision))) {
        if (_checkCurrent(revision)) {
          widget.app.resources.clearPublishedTextbooks();
          await _local(checkRevision: revision);
        }
        return;
      }
      await widget.app.resources.refreshTextbooks();
      if (!_checkCurrent(revision)) return;
      await _local(checkRevision: revision);
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'app', operation: '刷新内容目录');
      if (!_checkCurrent(revision)) return;
      widget.app.resources.clearPublishedTextbooks();
      await _local(checkRevision: revision);
      if (_isNetworkError(e) && !(await _checkConnection(checkRevision: revision))) return;
      if (_checkCurrent(revision)) _showOperationError('内容目录更新失败', e);
    } finally { _finishFetching(); }
  }
  String _errorDetail(Object error) => userError(error, fallback: '处理失败');
  bool _isNetworkError(Object error) => error is SocketException || error is HttpException ||
      error is HandshakeException || error is TimeoutException;
  void _showOperationError(String title, Object cause) {
    setState(() {
      error = cause is StateError && cause.message == '学习资源包更新失败'
          ? '学习资源包更新失败' : '$title：${_errorDetail(cause)}';
      _errorNeedsRecheck = _isNetworkError(cause);
      permissionError = false;
    });
  }
  void _closeError() {
    widget.app.resources.lastError = null;
    setState(() { error = null; permissionError = false; _errorNeedsRecheck = false; });
  }
  void _back() {
    if (_operationBusy && !_canLeaveDownload) {
      showResourceWait(context, _operationLabel);
      return;
    }
    Navigator.of(context).maybePop();
  }
  Future<void> _leaveAfterOperation() async {
    if (!_pageCurrent) return;
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }
  Future<void> _download(String id, {bool select = false}) async {
    if (_resourceBusy || !_pageCurrent) return;
    ++_checkRevision;
    setState(() { selecting = true; _operatingBookId = id;
      _operationLabel = installed[id]?['status'] == 'ready' ? '资源更新' : '资源下载';
      error = null; permissionError = false; });
    try {
      try {
        await widget.app.resources.download(id);
        if (select && _pageCurrent) await widget.app.store.selectBook(id);
        await widget.app.reload();
      } finally { await _local(); }
      if (_pageCurrent) {
        final summary = widget.app.resources.lastInstallSummary;
        ScaffoldMessenger.of(context).showSnackBar(GlassSnackBar(content: Text(
          summary == null ? '内容已安装，可离线学习' : '内容已安装：$summary')));
      }
      if (_pageCurrent && select) await _leaveAfterOperation();
    } catch (e, stack) {
      if (e is! ResourceCancelled) SystemErrors.record(e, stack, module: 'app', operation: '下载内容');
      if (!mounted) return;
      if (_pageCurrent) setState(() {
        error = widget.app.resources.lastError ?? '内容下载失败：${_errorDetail(e)}';
        _errorNeedsRecheck = _isNetworkError(e) || e is ResourceHashMismatch;
      });
    } finally { _finishOperation(); }
  }
  Future<void> _select(String id) async {
    if (_operationBusy || !_pageCurrent) return;
    if (installed[id]?['status'] != 'ready' || widget.app.resources.unavailable.contains(id)) {
      final book = books.firstWhere((book) => textOf(book, 'id') == id);
      if (!_canDownload(book)) return;
      await _download(id, select: true);
      return;
    }
    ++_checkRevision;
    setState(() { selecting = true; _operationLabel = '内容切换'; });
    try {
    await perform(context, () async {
      await widget.app.store.selectBook(id);
      await widget.app.reload();
      if (_pageCurrent) await _leaveAfterOperation();
    });
    } finally { _finishOperation(); }
  }
  Future<void> _remove(RowData book) async {
    if (_resourceBusy || !_pageCurrent) return;
    ++_checkRevision;
    setState(() { selecting = true; _operationLabel = '资源删除'; });
    try {
    final id = textOf(book, 'id');
    final yes = await showGlassDialog<bool>(context: context, builder: (context) => GlassAlertDialog(
      title: const Text('删除本地内容？'),
      content: Text('将删除“${textOf(book, 'textbook')} · ${textOf(book, 'volume')}”的单元、课程、单词、课文、文法、练习和音频。练习、复习及学习记录会保留。删除后只能下载服务器仍提供的内容；服务器已移除的内容将无法再次下载。'),
      actions: [
        StudyButton.text(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        StudyButton.filled(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
      ],
    ));
    if (yes != true || !_pageCurrent || widget.app.resources.activeBook != null) return;
    setState(() => _operatingBookId = id);
    await perform(context, () async {
      try {
        await widget.app.resources.remove(id);
        await widget.app.reload();
      } finally {
        await _local();
      }
      if (_pageCurrent) ScaffoldMessenger.of(context).showSnackBar(GlassSnackBar(content: Text('本地学习资源已删除，学习记录已保留')));
    });
    } finally { _finishOperation(); }
  }
  Widget _bookCard(RowData book, Resources resource) {
    final id = textOf(book, 'id');
    final textbook = textOf(book, 'textbook').trim();
    final displayTextbook = textbook.isEmpty ? '内容' : textbook;
    final coverParts = displayTextbook.split(RegExp(r'\s*[-－—–]\s*')).where((part) => part.isNotEmpty).toList();
    final coverTitleLines = coverParts.length <= 2
        ? coverParts
        : [coverParts.first, coverParts.skip(1).join('-')];
    final operating = (_operatingBookId ?? resource.activeBook) == id;
    final ready = installed[id]?['status'] == 'ready' && !resource.unavailable.contains(id);
    final remote = resource.publishedTextbook(id);
    final localOnly = resource.hasPublishedCatalog && remote == null && localBooks.containsKey(id);
    final invalidHash = resource.hasInvalidPublishedTextbookHash(id);
    final remoteHash = remote?['sha256'];
    final update = ready && remoteHash is String && remoteHash != installed[id]?['sha256'];
    final missing = !ready;
    final disabled = _operationBusy;
    final canDownload = _canDownload(book);
    final removable = localBooks.containsKey(id) || installed.containsKey(id);
    final String statusText;
    if (localOnly) {
      statusText = ready
          ? '本地数据，服务器已删除，可离线使用'
          : '本地资源异常，服务器已删除，可删除本地数据';
    } else if (ready) {
      statusText = '可离线使用';
    } else if (installed[id]?['status'] == 'broken') {
      statusText = resource.hasPublishedCatalog && remote != null
          ? '音频缺失或资源需修复，请重新下载'
          : '本地资源异常，可删除本地数据';
    } else {
      statusText = '选择后下载';
    }
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: StudyCard(child: StudyInkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: disabled || (!ready && !(missing && canDownload && !fetching)) ? null : () => _select(id),
      child: Stack(children: [
        Padding(padding: const EdgeInsets.fromLTRB(18, 18, 58, 18), child: Row(children: [
          Container(width: 62, height: 78, decoration: BoxDecoration(color: bookColor(book), borderRadius: BorderRadius.circular(10)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var index = 0; index < coverTitleLines.length; index++) ...[
              if (index > 0) const SizedBox(height: 2),
              SizedBox(width: 54, height: 16, child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(coverTitleLines[index], maxLines: 1, softWrap: false,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              )),
            ],
            const SizedBox(height: 5), Text(textOf(book, 'volume'), style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ])),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(displayTextbook, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
              const SizedBox(width: 8),
              Text(textOf(book, 'volume'), style: TextStyle(color: bookColor(book), fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 5), Text(textOf(book, 'descr'), style: Theme.of(context).textTheme.bodySmall),
            if (!invalidHash || ready) ...[
              const SizedBox(height: 7),
              Row(children: [const Icon(Icons.headphones, size: 16), const SizedBox(width: 5), Expanded(child: Text(
                resource.activeBook == id
                  ? '${resource.detail.isNotEmpty ? resource.detail : '正在处理资源'}${resource.progress == null ? '' : ' ${(resource.progress! * 100).round()}%'}'
                  : '${lessonCounts.containsKey(id) ? '${lessonCounts[id]} 课 · ' : ''}$statusText',
                style: Theme.of(context).textTheme.labelMedium,
              ))]),
            ],
            if (resource.activeBook == id) ...[
              const SizedBox(height: 8), StudyLinearProgressIndicator(value: resource.progress),
              if (resource.stage != 'delete') ...[
                StudyButton.text(onPressed: resource.canCancel ? resource.cancelDownload : null,
                  child: Text(resource.cancelling ? '正在取消…' : resource.canCancel ? '取消下载' : '正在安全收尾…')),
                Text(resource.canCancel ? '可返回其他页面，下载将继续；取消会保留原有内容。' : '正在保存或恢复内容，可返回其他页面；完成后可在这里查看。'),
              ],
            ],
          ])),
        ])),
        if (operating) Positioned(top: 7, right: 7, child: Semantics(
          label: '正在处理内容',
          child: SizedBox(width: 48, height: 48, child: Center(child: IconTheme(
            data: IconThemeData(color: Theme.of(context).colorScheme.primary),
            child: const ResourceActivityIcon(checking: true),
          ))),
        )),
        if (!operating && invalidHash) Positioned(top: 7, right: 7, child: Tooltip(
          message: '内容校验错误',
          child: Semantics(
            label: '内容校验错误',
            child: SizedBox(width: 48, height: 48, child: Center(child: Icon(
              Icons.error_outline, color: Theme.of(context).colorScheme.error,
            ))),
          ),
        )),
        if (!operating && !invalidHash && !_resourceBusy && canDownload && (missing || update)) Positioned(top: 7, right: 7, child: StudyIconButton(
          tooltip: update ? '更新内容' : '下载内容',
          icon: Icon(update ? Icons.system_update_alt : Icons.download_outlined),
          color: Theme.of(context).colorScheme.primary,
          onPressed: canDownload ? () => _download(id) : null,
        )),
        if (removable) Positioned(bottom: 7, right: 7, child: StudyIconButton(
          tooltip: '删除本地内容',
          icon: const Icon(Icons.delete_outline),
          color: Theme.of(context).colorScheme.error,
          onPressed: disabled || fetching ? null : () => _remove(book),
        )),
      ]),
    )));
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: widget.app.resources, builder: (_, __) {
    final resource = widget.app.resources;
    final displayError = error ?? resource.lastError;
    return PopScope(
      canPop: !_operationBusy || _canLeaveDownload || _leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _operationBusy && !_canLeaveDownload && !_leaving) showResourceWait(context, _operationLabel);
      },
      child: PlaybackScaffold(appBar: StudyAppBar(title: const Text('学习资源'),
        leading: StudyIconButton(tooltip: '返回', onPressed: _back,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20)),
        actions: [StudyIconButton(tooltip: _operationBusy ? '正在$_operationLabel' : fetching ? '正在检查内容' : '刷新内容',
          onPressed: _resourceBusy ? null : _refresh,
          icon: ResourceActivityIcon(checking: _resourceBusy))]), body: ListView(padding: const EdgeInsets.all(20), children: [
      Text('从哪里开始？', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text('可随时切换内容，学习记录会分别保留。', style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: 20),
      if (displayError != null) StudyCard(child: Padding(padding: const EdgeInsets.all(12), child: Row(
        crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(displayError),
            if (installed.values.any((row) => row['status'] == 'ready'))
              const Padding(padding: EdgeInsets.only(top: 8), child: Text('本地内容可继续离线学习。')),
            if (resource.lastFailedBook != null) StudyButton.text(
              onPressed: _resourceBusy ? null : () => _download(resource.lastFailedBook!),
              child: const Text('重试下载')),
            if (permissionError) StudyButton.text(onPressed: _operationBusy ? null : _openNetworkSettings, child: const Text('前往设置')),
          ])),
          const SizedBox(width: 12),
          StudyButton.text(
            onPressed: _resourceBusy ? null : (_errorNeedsRecheck ? _refresh : _closeError),
            child: Text(_errorNeedsRecheck ? '重新检查' : '关闭'),
          ),
        ],
      ))),
      if (!fetching && books.isEmpty && error == null) const Padding(padding: EdgeInsets.all(24), child: Text('暂无内容目录，可刷新获取。')),
      for (final book in books) _bookCard(book, resource),
    ])));
  });
}

class CoursePanel extends StatefulWidget {
  const CoursePanel(this.app, {super.key});
  final AppController app;
  @override
  State<CoursePanel> createState() => _CoursePanelState();
}
class _CoursePanelState extends State<CoursePanel> {
  late Future<List<Object>> data;
  String bookId = '';
  @override
  void initState() { super.initState(); widget.app.addListener(_changed); _load(); }
  void _load() {
    bookId = textOf(widget.app.position, 'textbook_id');
    data = Future.wait<Object>([
      widget.app.store.db.query('yzc_textbook', where: 'id=?', whereArgs: [bookId]),
      widget.app.store.lessons(bookId), widget.app.store.progress(bookId),
      widget.app.store.db.query('yzc_unit', where: 'textbook_id=?', whereArgs: [bookId], orderBy: 'num IS NULL,num,id'),
      widget.app.store.bookPosition(bookId),
    ]);
  }
  void _changed() { if (mounted) setState(_load); }
  @override
  void dispose() { widget.app.removeListener(_changed); super.dispose(); }
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Object>>(future: data, builder: (_, snapshot) {
    if (snapshot.hasError) return const Center(child: Text('课程读取失败'));
    if (!snapshot.hasData) return const Center(child: StudyCircularProgressIndicator());
    final books = snapshot.data![0] as List<RowData>, lessons = snapshot.data![1] as List<RowData>, progress = snapshot.data![2] as List<RowData>, units = snapshot.data![3] as List<RowData>, positions = snapshot.data![4] as List<RowData>;
    if (books.isEmpty || lessons.isEmpty) return PageBody(children: [
      Text('我的课程', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 80),
      Icon(Icons.menu_book_outlined, size: 74, color: Theme.of(context).colorScheme.outlineVariant),
      const SizedBox(height: 22),
      Text('还没有选择内容', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text('选择一本内容，从第一课开始建立自己的语言小径。', textAlign: TextAlign.center, style: TextStyle(height: 1.6, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 26),
      StudyButton.filledIcon(onPressed: () => openPage(context, LibraryPage(widget.app)), icon: const Icon(Icons.add), label: const Text('选择内容')),
    ]);
    final book = books.single;
    final currentLessonId = positions.isEmpty ? '' : textOf(positions.single, 'lessons_id');
    final currentLesson = lessons.where((lesson) => textOf(lesson, 'id') == currentLessonId);
    final currentUnitId = currentLesson.isEmpty ? null : currentLesson.single['unit_id'];
    Widget lessonTile(RowData lesson) {
      final done = lessonPercent(progress, textOf(lesson, 'id')) == 100;
      return StudyInkWell(onTap: () => openPage(
        context,
        CourseLessonPage(widget.app, book, lesson,
          openPractice: (context, id) => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => PracticePage(widget.app, id)),
          ),
        ),
      ), child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15), child: Row(children: [
          SizedBox(width: 66, child: Text(lessonLabel(lesson), style: TextStyle(fontWeight: FontWeight.w600, color: done ? Colors.green : null))),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(textOf(lesson, 'title'), style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'), fontSize: 16, fontWeight: FontWeight.w600)),
            if (textOf(lesson, 'sub_title').isNotEmpty) ...[const SizedBox(height: 2), Text(textOf(lesson, 'sub_title'), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP')))],
          ])),
          Icon(done ? Icons.check_circle : Icons.chevron_right, size: 21, color: done ? Colors.green : Theme.of(context).colorScheme.outline),
        ]),
      ));
    }
    Widget unitCard(RowData unit, List<RowData> children, bool expanded, {bool useUnitTitle = true}) => Padding(
      padding: const EdgeInsets.only(bottom: 12), child: StudyCard(clipBehavior: Clip.antiAlias, child: StudyExpansionTile(
        key: PageStorageKey('$bookId:${unit['id']}'), initiallyExpanded: expanded,
        shape: const Border(), collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3), childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
        title: Text(intOf(unit, 'num') > 0 ? '第${chineseNumber(intOf(unit, 'num'))}单元' : textOf(unit, 'title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: bookColor(book))),
        subtitle: useUnitTitle && textOf(unit, 'title').trim().isNotEmpty
          ? Text(textOf(unit, 'title'))
          : children.isEmpty ? null : Text(children.length == 1 ? lessonLabel(children.first) : '${lessonLabel(children.first)}—${lessonLabel(children.last)}'),
        children: [for (var i = 0; i < children.length; i++) ...[if (i > 0) const StudyDivider(height: 1), lessonTile(children[i])]],
      )),
    );
    final unitIds = units.map((unit) => unit['id']).toSet();
    final currentLessonIsUngrouped = currentLesson.isNotEmpty && !unitIds.contains(currentUnitId);
    final lessonsByUnit = <Object?, List<RowData>>{};
    final ungrouped = <RowData>[];
    for (final lesson in lessons) {
      if (unitIds.contains(lesson['unit_id'])) {
        lessonsByUnit.putIfAbsent(lesson['unit_id'], () => []).add(lesson);
      } else {
        ungrouped.add(lesson);
      }
    }
    return SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${textOf(book, 'textbook')} · ${textOf(book, 'volume')}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4), Text('${lessons.length} 课 · ${widget.app.resources.unavailable.contains(bookId) ? '学习资源需要重新下载' : '课文与单词录音已就绪'}'),
      ])), StudyIconButton.filledTonal(tooltip: '切换内容', onPressed: () => openPage(context, LibraryPage(widget.app)), icon: const Icon(Icons.swap_horiz))])),
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 28), children: [
        for (var i = 0; i < units.length; i++) unitCard(units[i], lessonsByUnit[units[i]['id']] ?? [],
          currentLesson.isEmpty ? i == 0 : !currentLessonIsUngrouped && units[i]['id'] == currentUnitId),
        if (ungrouped.isNotEmpty) unitCard({'id': 'ungrouped', 'title': '课程目录'}, ungrouped,
          currentLessonIsUngrouped || currentLesson.isEmpty && units.isEmpty, useUnitTitle: false),
      ])),
    ]));
  });
}

class RubyText extends StatelessWidget {
  const RubyText(this.text, {required this.ruby, this.source = true, this.centered = false, this.active = false, this.fontSize = 19, this.color, super.key});
  final String text;
  final bool ruby, source, centered, active;
  final double fontSize;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = <Widget>[];
    void add(String surface, String reading) {
      final highlighted = active && surface.trim().isNotEmpty;
      tokens.add(Column(mainAxisSize: MainAxisSize.min, children: [
        keepSpace(ruby, Text(reading.isEmpty ? ' ' : reading, style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'), fontSize: 12, height: 1.3,
          color: Color(0xFF32AA43)))),
        keepSpace(source, Text(surface, style: TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'), fontSize: fontSize, height: 1.5, fontWeight: FontWeight.normal,
          color: highlighted ? (dark ? const Color(0xFFFFB366) : const Color(0xFFB85C00)) : color))),
      ]));
    }
    var offset = 0;
    for (final match in RegExp(r'!([^!\s()]+)\(([^)]*)\)').allMatches(text)) {
      for (final rune in text.substring(offset, match.start).runes) { add(String.fromCharCode(rune), ''); }
      add(match.group(1)!, match.group(2)!);
      offset = match.end;
    }
    for (final rune in text.substring(offset).runes) { add(String.fromCharCode(rune), ''); }
    return Wrap(alignment: centered ? WrapAlignment.center : WrapAlignment.start, crossAxisAlignment: WrapCrossAlignment.end, children: tokens);
  }
}

class ReviewPanel extends StatefulWidget {
  const ReviewPanel(this.app, {required this.active, super.key});
  final AppController app;
  final bool active;
  @override
  State<ReviewPanel> createState() => _ReviewPanelState();
}
class _ReviewPanelState extends State<ReviewPanel> with WidgetsBindingObserver, RouteAware {
  bool busy = false;
  Timer? _dueTimer;
  ModalRoute<dynamic>? _route;
  bool _foreground = true, _routeVisible = true;
  bool _refreshing = false, _refreshAgain = false;
  bool get _visible => mounted && widget.active && _foreground && _routeVisible;

  @override
  void initState() {
    super.initState();
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.app.addListener(_scheduleDueRefresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route != route) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      _routeVisible = route?.isCurrent ?? true;
      if (route != null) appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didUpdateWidget(ReviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != widget.app) {
      oldWidget.app.removeListener(_scheduleDueRefresh);
      widget.app.addListener(_scheduleDueRefresh);
    }
    if (oldWidget.active != widget.active || oldWidget.app != widget.app) {
      _requestDueRefresh();
    }
  }

  @override
  void didPush() => _requestDueRefresh();

  @override
  void didPushNext() {
    _routeVisible = false;
    _dueTimer?.cancel();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _requestDueRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _requestDueRefresh();
  }

  void _requestDueRefresh() {
    _dueTimer?.cancel();
    if (!_visible) return;
    unawaited(_refreshDue());
  }

  Future<void> _refreshDue() async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        await widget.app.refreshReviewStatistics();
      } while (_refreshAgain && _visible);
      _scheduleDueRefresh();
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'app', operation: '刷新复习统计');
      // Retry on the next entry/resume, without a rapid failure loop.
      _dueTimer?.cancel();
      if (_visible) {
        ScaffoldMessenger.of(context).showSnackBar(
          GlassSnackBar(content: Text('复习统计刷新失败，请重新进入复习页重试')),
        );
      }
    } finally {
      _refreshing = false;
    }
  }

  void _scheduleDueRefresh() {
    _dueTimer?.cancel();
    if (!_visible) return;
    final next = intOf(widget.app.stats, 'next_review_time');
    if (next == 0) return;
    final delay = next - nowMs();
    _dueTimer = Timer(Duration(milliseconds: delay > 0 ? delay : 1), _requestDueRefresh);
  }

  @override
  void dispose() {
    _dueTimer?.cancel();
    widget.app.removeListener(_scheduleDueRefresh);
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  Future<void> _start(bool mistakes) async {
    setState(() => busy = true);
    await perform(context, () async {
      final pool = await widget.app.store.reviewPool(mistakes: mistakes);
      if (pool.isEmpty) throw StateError(mistakes ? '暂无错题' : '暂无到期复习题');
      final id = await widget.app.store.startPractice(pool, review: true);
      if (mounted) openPage(context, PracticePage(widget.app, id));
    });
    if (mounted) setState(() => busy = false);
  }
  @override
  Widget build(BuildContext context) => PageBody(children: [
    Text('记忆复习', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
    const SizedBox(height: 5), Text('在快要忘记时再见一次。', style: Theme.of(context).textTheme.bodyLarge),
    const SizedBox(height: 28),
    Center(child: Stack(alignment: Alignment.center, children: [
      SizedBox(width: 170, height: 170, child: StudyCircularProgressIndicator(
        value: (intOf(widget.app.stats, 'due') / (intOf(widget.app.stats, 'cards') == 0 ? 1 : intOf(widget.app.stats, 'cards'))).clamp(0.0, 1.0).toDouble(),
        strokeWidth: 12, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest, color: vermilion,
      )),
      Column(children: [Text('${intOf(widget.app.stats, 'due')}', style: Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w700)), const Text('今日到期')]),
    ])),
    const SizedBox(height: 28),
    SizedBox(width: double.infinity, child: StudyButton.filledIcon(onPressed: busy || intOf(widget.app.stats, 'due') == 0 ? null : () => _start(false), icon: const Icon(Icons.refresh), label: Text(busy ? '准备中' : '开始复习'))),
    const SectionTitle('记忆统计'),
    StudyCardRow(children: [Expanded(child: StudyStat(value: '${intOf(widget.app.stats, 'cards')}', label: '学习卡片')), const SizedBox(width: 10), Expanded(child: StudyStat(value: '${intOf(widget.app.stats, 'mistakes')}', label: '历史错题'))]),
    const SectionTitle('复习规则'),
    const StudyCard(child: Padding(padding: EdgeInsets.all(18), child: Text('答对后，卡片会依次在 2、4、7、14、30 天后出现；答错会回到本轮末尾，直到答对。点选答案后会立即判断并保存。', style: TextStyle(height: 1.65)))),
  ]);
}

class PracticePage extends StatefulWidget {
  const PracticePage(this.app, this.id, {super.key});
  final AppController app;
  final String id;
  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  List<RowData> items = [], options = [];
  RowData session = {};
  int index = 0;
  bool busy = true, showResult = false;
  String? error, selected, previousRating;
  final clock = Stopwatch();
  final _resultScrollController = ScrollController(keepScrollOffset: false);
  final _mediaPlayback = IosLessonPlayback.instance;
  final _mediaVideo = CourseVideoController();
  @override
  void initState() { super.initState(); unawaited(_load(initial: true)); }
  @override
  void dispose() {
    clock.stop();
    _resultScrollController.dispose();
    if (_mediaPlayback.lesson == 'practice:${widget.id}') unawaited(_mediaPlayback.stop());
    _mediaVideo.dispose();
    super.dispose();
  }

  Future<void> _playQuestionAudio(RowData item, {String? filename, String? title}) async {
    await perform(context, () async {
      await _mediaVideo.stop();
      if (_mediaPlayback.active) await _mediaPlayback.stop();
      final book = textOf(item, 'textbook_id');
      final path = filename == null
        ? await widget.app.resources.mediaPath(book, textOf(item, 'media_src'), 'audio')
        : await widget.app.resources.audioPath(book, filename);
      await _mediaPlayback.start({
        'lesson': 'practice:${widget.id}', 'title': title ?? '练习听力', 'words': false,
        'batch': false, 'speed': widget.app.speed, 'repeat': 1, 'intervalSteps': 0,
        'startIndex': 0,
        'clips': [{'id': 'practice-media:${item['id']}:${filename ?? item['media_src']}', 'path': path}],
      });
    });
  }

  Future<void> _playQuestionHotspot(RowData item, CourseImageHotspot hotspot) =>
    _playQuestionAudio(item, filename: hotspot.audioSource, title: hotspot.label);

  Future<void> _playQuestionVideo(RowData item) async {
    final book = textOf(item, 'textbook_id');
    await _mediaVideo.play(id: textOf(item, 'id'), book: book,
      resolvePath: () => widget.app.resources.mediaPath(book, textOf(item, 'media_src'), 'video'),
      beforePlay: () async { if (_mediaPlayback.active) await _mediaPlayback.stop(); });
  }

  Widget _questionMedia(RowData item) {
    final type = textOf(item, 'media_type');
    final book = textOf(item, 'textbook_id');
    if (type.isEmpty || type == 'text') return const SizedBox.shrink();
    if (type == 'audio') {
      return Padding(padding: const EdgeInsets.only(bottom: 18), child: StudyButton.outlined(
        onPressed: busy ? null : () => _playQuestionAudio(item),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.volume_up_outlined), SizedBox(width: 8), Text('播放听力材料'),
        ])));
    }
    if (type == 'image') {
      return Padding(padding: const EdgeInsets.only(bottom: 18), child: CourseImageCard(
        source: textOf(item, 'media_src'), label: '练习题插图',
        resolvePath: () => widget.app.resources.mediaPath(book, textOf(item, 'media_src'), 'image')));
    }
    if (type == 'interactive_image') {
      return Padding(padding: const EdgeInsets.only(bottom: 18), child: CourseInteractiveImageCard(
        source: textOf(item, 'media_src'), label: '互动练习题插图',
        mediaConfig: textOf(item, 'media_config'),
        resolvePath: () => widget.app.resources.mediaPath(book, textOf(item, 'media_src'), 'interactive_image'),
        hotspotAvailable: (hotspot) => widget.app.resources.hasAudio(book, hotspot.audioSource),
        onActivate: (hotspot) => _playQuestionHotspot(item, hotspot), interactionEnabled: !busy));
    }
    if (type == 'video') {
      return Padding(padding: const EdgeInsets.only(bottom: 18), child: CourseVideoCard(
        controller: _mediaVideo, id: textOf(item, 'id'), source: textOf(item, 'media_src'),
        resolvePath: () => widget.app.resources.mediaPath(book, textOf(item, 'media_src'), 'video'),
        onPlay: () => _playQuestionVideo(item), enabled: !busy));
    }
    return const Padding(padding: EdgeInsets.only(bottom: 18), child: Text('此练习媒体类型暂不支持'));
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final store = widget.app.store;
      final result = await store.practiceItems(widget.id);
      if (result.isEmpty) throw StateError('练习记录为空');
      if (initial) {
        final next = result.indexWhere((r) => r['answer_time'] == null);
        index = next < 0 ? 0 : next;
        final sessions = await store.db.query('yzc_user_practice', where: 'id=? AND user_id=?', whereArgs: [widget.id, store.userId]);
        if (!mounted) return;
        session = sessions.single;
        showResult = next < 0;
      }
      final current = result[index];
      final choices = await store.options(textOf(current, 'question_id'));
      final priorRating = current['answer_time'] != null && intOf(current, 'correct') == 0
          ? await store.previousMistakeRating(current)
          : null;
      if (!mounted) return;
      setState(() {
        items = result; options = choices; previousRating = priorRating; busy = false; error = null;
        if (items[index]['answer_time'] != null) selected = textOf(items[index], 'answer');
      });
      clock..reset()..start();
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'app', operation: '读取练习', hint: userError(e, fallback: '练习读取失败'));
      if (mounted) setState(() { busy = false; error = userError(e, fallback: '练习读取失败'); });
    }
  }

  Future<void> _answer(String answer) async {
    if (busy || items[index]['answer_time'] != null) return;
    setState(() { selected = answer; busy = true; });
    await perform(context, () async {
      await widget.app.store.answer(items[index], answer, clock.elapsedMilliseconds);
      await widget.app.reload();
      await _load();
    });
    if (mounted && items[index]['answer_time'] != null && intOf(items[index], 'correct') == 1) {
      setState(() => busy = true);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (mounted) await _advance();
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _rate(String? rating) async {
    if (busy || items[index]['answer_time'] == null || intOf(items[index], 'correct') != 0) return;
    setState(() => busy = true);
    await perform(context, () async {
      await widget.app.store.rateMistake(items[index], rating);
      await _load();
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> _advance() async {
    if (index == items.length - 1) { setState(() => showResult = true); }
    else {
      setState(() { index++; selected = null; previousRating = null; busy = true; });
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty || error != null || (busy && selected == null)) return PlaybackScaffold(appBar: StudyAppBar(title: const Text('练习')), body: Center(child: error == null
      ? const StudyCircularProgressIndicator() : StudyButton.text(onPressed: () => _load(initial: items.isEmpty), child: const Text('练习读取失败，点击重试'))));
    if (showResult) return PlaybackScaffold(appBar: StudyAppBar(title: const Text('练习结果')), body: ListView(
      key: const ValueKey('practice-result'),
      controller: _resultScrollController,
      padding: const EdgeInsets.all(20), children: [
      Text('共作答 ${items.length} 次 · 答对 ${items.where((r) => intOf(r, 'correct') == 1).length} 次', style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.5)),
      for (final relation in questionRelations)
        if (items.any((r) => r['relation'] == relation)) Text('${questionRelationLabel(relation)}：${items.where((r) => r['relation'] == relation && intOf(r, 'correct') == 1).length} / ${items.where((r) => r['relation'] == relation).length} 题正确'),
      const SizedBox(height: 12), const Text('练习记录已保存。错题可在首页“错题记录”中再次练习。'),
      const SizedBox(height: 20), StudyButton.filled(onPressed: () => Navigator.pop(context), child: const Text('返回')),
      for (var i = 0; i < items.length; i++) AnswerTile(widget.app.store, items[i], number: i + 1),
    ]));
    final item = items[index], checked = item['answer_time'] != null;
    final polishPractice = session['type'] != 'review';
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = dark ? const Color(0xFF252525) : Colors.white;
    final correctColor = dark ? const Color(0xFF81C995) : const Color(0xFF247A46);
    final incorrectColor = dark ? const Color(0xFFFFB4AB) : const Color(0xFFB53D35);
    Widget practiceOption(RowData option) {
      final isCorrect = checked && option['code'] == item['correct_answer'];
      final isIncorrect = checked && !isCorrect && option['code'] == selected;
      final isSelected = option['code'] == selected;
      final accent = isCorrect ? correctColor : isIncorrect ? incorrectColor : isSelected ? colors.primary : colors.onSurfaceVariant;
      final emphasized = isCorrect || isIncorrect || isSelected;
      final background = emphasized ? Color.alphaBlend(accent.withValues(alpha: .10), cardColor) : cardColor;
      return Padding(padding: const EdgeInsets.only(bottom: 10), child: StudyButton.outlined(
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: const Size(double.infinity, 56),
          padding: const EdgeInsets.all(16),
          backgroundColor: background,
          disabledBackgroundColor: background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: emphasized ? accent : colors.outlineVariant, width: emphasized ? 1.5 : 1),
        ),
        onPressed: checked || busy ? null : () => _answer(textOf(option, 'code')),
        child: Row(children: [
          Container(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: accent.withValues(alpha: .10), borderRadius: BorderRadius.circular(9)),
            child: Text(textOf(option, 'code'), textAlign: TextAlign.center, style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text.rich(contentTextSpan(questionDisplayText(textOf(option, 'content')), japanese: true), style: TextStyle(color: colors.onSurface, height: 1.5))),
          if (isCorrect || isIncorrect) ...[
            const SizedBox(width: 8),
            Icon(isCorrect ? Icons.check_circle_outline : Icons.cancel_outlined, color: accent, size: 22,
              semanticLabel: isCorrect ? '正确答案' : '所选答案错误'),
          ],
        ]),
      ));
    }
    return PlaybackScaffold(appBar: StudyAppBar(title: Text(session['type'] == 'review' ? '复习' : '练习')), body: ListView(padding: const EdgeInsets.all(20), children: [
      StudyLinearProgressIndicator(value: items.where((r) => r['answer_time'] != null).length / items.length),
      const SizedBox(height: 12), Text('${index + 1} / ${items.length} · ${questionRelationLabel(item['relation'])}'),
      const SizedBox(height: 18),
      _questionMedia(item),
      if (polishPractice) Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(18), border: Border.all(color: colors.outlineVariant)),
        child: PracticeQuestionBody(textOf(item, 'content'), key: ValueKey('practice-body-$index'),
          headingFontSize: 17, bodyFontSize: 18, footerFontSize: 17, secondaryFontSize: 15, highlightBodySection: true),
      ) else PracticeQuestionBody(textOf(item, 'content'), key: ValueKey('practice-body-$index')),
      const SizedBox(height: 20),
      for (final option in options) if (polishPractice) practiceOption(option) else Padding(padding: const EdgeInsets.only(bottom: 10), child: StudyButton.outlined(
        style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.all(16), side: BorderSide(
          color: checked && option['code'] == item['correct_answer'] ? Colors.green : checked && option['code'] == selected ? Colors.red : option['code'] == selected ? Theme.of(context).colorScheme.primary : Colors.grey)),
        onPressed: checked || busy ? null : () => _answer(textOf(option, 'code')),
        child: Text.rich(contentTextSpan('${option['code']}. ${questionDisplayText(textOf(option, 'content'))}', japanese: true), style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
      )),
      if (checked) ...[
        if (polishPractice) Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Color.alphaBlend((item['correct'] == 1 ? correctColor : incorrectColor).withValues(alpha: .08), cardColor),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: (item['correct'] == 1 ? correctColor : incorrectColor).withValues(alpha: .30)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(item['correct'] == 1 ? Icons.check_circle_outline : Icons.cancel_outlined,
                color: item['correct'] == 1 ? correctColor : incorrectColor, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text(item['correct'] == 1 ? '回答正确' : '回答错误 · 正确答案：${item['correct_answer']}',
                style: TextStyle(color: item['correct'] == 1 ? correctColor : incorrectColor, fontWeight: FontWeight.w700, height: 1.5))),
            ]),
            if (textOf(item, 'definition').trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('解析', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text.rich(contentTextSpan(textOf(item, 'definition')), style: TextStyle(color: colors.onSurface, height: 1.6)),
            ],
          ]),
        ) else ...[
          Text(item['correct'] == 1 ? '回答正确' : '回答错误 · 正确答案：${item['correct_answer']}', style: TextStyle(color: item['correct'] == 1 ? Colors.green : Colors.red)),
          const SizedBox(height: 8), Text.rich(contentTextSpan(textOf(item, 'definition')), style: const TextStyle(height: 1.6)),
        ],
        const SizedBox(height: 20),
      ],
      if (checked && intOf(item, 'correct') != 1) ...[
        if (previousRating != null) ...[
          Text('上次评价：${selfRatingLabel(previousRating)}', style: TextStyle(color: selfRatingColor(context, previousRating), fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
        ],
        const Text('你觉得这道题怎么样？（可选）'),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, constraints) {
          final minWidth = MediaQuery.textScalerOf(context).scale(12) * 4 + 24;
          final columns = constraints.maxWidth >= minWidth * 4 + 18 ? 4 : constraints.maxWidth >= minWidth * 2 + 6 ? 2 : 1;
          final width = (constraints.maxWidth - (columns - 1) * 6) / columns;
          return Wrap(spacing: 6, runSpacing: 8, children: [
          for (final rating in const ['again', 'hard', 'good', 'easy'])
            SizedBox(width: width,
              child: StudyChoiceChip(
                label: SizedBox(width: double.infinity, child: Center(
                  heightFactor: 1, child: Text(selfRatingLabel(rating), textAlign: TextAlign.center),
                )),
                labelStyle: TextStyle(fontSize: 12, color: selfRatingColor(context, rating)),
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                showCheckmark: false,
                backgroundColor: selfRatingColor(context, rating).withValues(alpha: .06),
                selectedColor: selfRatingColor(context, rating).withValues(alpha: .20),
                side: BorderSide(color: selfRatingColor(context, rating).withValues(alpha: .65)),
                selected: item['self_rating'] == rating,
                onSelected: busy ? null : (selected) => _rate(selected ? rating : null),
              ),
            ),
        ]);
        }),
        const SizedBox(height: 24),
      ],
      if (checked && intOf(item, 'correct') != 1) StudyButton.filled(
        onPressed: busy || error != null ? null : _advance,
        child: Text(index == items.length - 1 ? '查看结果' : '下一题'),
      ),
      const SizedBox(height: 12), const Text('点选答案后立即判断并保存；退出后可从练习记录继续。', style: TextStyle(color: Colors.grey)),
    ]));
  }
}

String displayDate(int value) {
  final date = DateTime.fromMillisecondsSinceEpoch(value);
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String selfRatingLabel(Object? value) => const {
  'again': '完全忘记',
  'hard': '很难',
  'good': '一般',
  'easy': '其实会',
}[value] ?? '';

Color selfRatingColor(BuildContext context, Object? value) => const {
  'again': Color(0xFFC94F3D),
  'hard': Color(0xFFD9822B),
  'good': Color(0xFF397CC6),
  'easy': Color(0xFF32A05A),
}[value] ?? Theme.of(context).colorScheme.onSurfaceVariant;

String sessionTitle(RowData session) {
  final title = textOf(session, 'textbook');
  final lesson = textOf(session, 'title');
  return '${session['type'] == 'review' ? '复习' : '练习'} · ${title.isEmpty ? '跨课复习' : '$title${lesson.isEmpty ? '' : ' · $lesson'}'}';
}

class AnswerTile extends StatefulWidget {
  const AnswerTile(this.store, this.item, {super.key, this.number});
  final AppStore store;
  final RowData item;
  final int? number;
  @override
  State<AnswerTile> createState() => _AnswerTileState();
}
class _AnswerTileState extends State<AnswerTile> {
  late Future<List<RowData>> options;
  @override
  void initState() { super.initState(); options = widget.store.options(textOf(widget.item, 'question_id')); }
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return StudyExpansionTile(
      title: Text.rich(contentTextSpan('${widget.number == null ? '' : '${widget.number}. '}${questionDisplayText(textOf(item, 'content'))}')),
      subtitle: Text(item['answer_time'] == null ? '未作答' : item['correct'] == 1 ? '正确' : '错误'),
      children: [if (item['answer_time'] != null) FutureBuilder<List<RowData>>(future: options, builder: (_, snapshot) {
        if (snapshot.hasError) return StudyButton.text(onPressed: () => setState(() => options = widget.store.options(textOf(item, 'question_id'))), child: const Text('答案读取失败，点击重试'));
        if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(16), child: StudyCircularProgressIndicator());
        return Padding(padding: const EdgeInsets.all(16), child: Align(alignment: Alignment.centerLeft, child: Text.rich(
          TextSpan(children: [
            contentTextSpan('你的答案：${item['answer']}\n正确答案：${item['correct_answer']}'
              '${textOf(item, 'self_rating').isEmpty ? '' : '\n主观评分：${selfRatingLabel(item['self_rating'])}'}\n'),
            contentTextSpan(snapshot.data!.map((o) => '${o['code']}. ${questionDisplayText(textOf(o, 'content'))}').join('\n'), japanese: true),
            contentTextSpan('\n\n${textOf(item, 'definition')}'),
          ]),
          style: const TextStyle(height: 1.6),
        )));
      })],
    );
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage(this.app, {super.key, this.mistakes = false});
  final AppController app;
  final bool mistakes;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}
class _HistoryPageState extends State<HistoryPage> {
  late Future<List<RowData>> future;
  bool busy = false;
  @override
  void initState() { super.initState(); future = _load(); }
  Future<List<RowData>> _load() async {
    final store = widget.app.store;
    if (widget.mistakes) {
      return store.db.rawQuery('SELECT q.*,r.mistake FROM yzc_user_review r JOIN yzc_user_question q ON q.id=r.snapshot_id AND q.user_id=r.user_id WHERE r.user_id=? AND r.mistake>0 ORDER BY r.review_time', [store.userId]);
    }
    final history = await store.history();
    final titles = await store.db.rawQuery("SELECT i.practice_id,q.textbook,q.title,COUNT(DISTINCT q.textbook_id || ':' || COALESCE(q.lessons_id,'')) scopes FROM yzc_user_practice_item i JOIN yzc_user_question q ON q.id=i.question_id AND q.user_id=i.user_id WHERE i.user_id=? GROUP BY i.practice_id", [store.userId]);
    final map = {for (final row in titles) textOf(row, 'practice_id'): row};
    final result = <RowData>[];
    for (final row in history) {
      final title = map[row['id']];
      final hasSingleScope = title != null && title['scopes'] == 1;
      result.add({
        ...row,
        'textbook': hasSingleScope ? title['textbook'] : null,
        'title': hasSingleScope ? title['title'] : null,
      });
    }
    return result;
  }
  Future<void> _startMistakes() async {
    setState(() => busy = true);
    await perform(context, () async {
      final pool = await widget.app.store.reviewPool(mistakes: true);
      if (pool.isEmpty) throw StateError('暂无错题');
      final id = await widget.app.store.startPractice(pool, review: true);
      if (mounted) await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PracticePage(widget.app, id)));
    });
    if (mounted) setState(() { busy = false; future = _load(); });
  }
  @override
  Widget build(BuildContext context) => PlaybackScaffold(appBar: StudyAppBar(title: Text(widget.mistakes ? '错题记录' : '练习记录')), body: FutureBuilder<List<RowData>>(future: future, builder: (_, snapshot) {
    if (snapshot.hasError) return Center(child: StudyButton.text(onPressed: () => setState(() => future = _load()), child: const Text('记录读取失败，点击重试')));
    if (!snapshot.hasData) return const Center(child: StudyCircularProgressIndicator());
    final rows = snapshot.data!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (widget.mistakes) ...[
        Text('历史错题 ${rows.length} 道 · 答对后仍保留历史记录'), const SizedBox(height: 12),
        StudyButton.filled(onPressed: busy || rows.isEmpty ? null : _startMistakes, child: Text(busy ? '准备中' : '复习错题（${rows.length < 10 ? rows.length : 10} 题）')),
        for (final row in rows) MistakeTile(widget.app.store, row),
      ] else ...[
        if (rows.isEmpty) const Text('暂无练习记录。'),
        for (final row in rows) StudyCard(child: StudyListTile(
          title: Text(sessionTitle(row)), subtitle: Text('${displayDate(intOf(row, 'start_time'))}\n${row['status'] == 'complete' ? '已完成' : '未完成'} · 已答 ${row['answered']}/${row['count']} · 正确 ${row['correct']}'),
          trailing: const Icon(Icons.chevron_right), onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PracticeDetailsPage(widget.app, row)));
            if (mounted) setState(() => future = _load());
          },
        )),
      ],
    ]);
  }));
}

class MistakeTile extends StatefulWidget {
  const MistakeTile(this.store, this.row, {super.key});
  final AppStore store;
  final RowData row;
  @override
  State<MistakeTile> createState() => _MistakeTileState();
}
class _MistakeTileState extends State<MistakeTile> {
  late Future<List<RowData>> options;
  @override
  void initState() { super.initState(); options = widget.store.options(textOf(widget.row, 'id')); }
  @override
  void didUpdateWidget(covariant MistakeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row['id'] != widget.row['id']) options = widget.store.options(textOf(widget.row, 'id'));
  }
  @override
  Widget build(BuildContext context) => StudyExpansionTile(
    title: Text.rich(contentTextSpan(questionDisplayText(textOf(widget.row, 'content')))),
    subtitle: Text.rich(TextSpan(children: [
      contentTextSpan(textOf(widget.row, 'title'), japanese: true),
      contentTextSpan(' · 累计答错 ${widget.row['mistake']} 次'),
    ])),
    children: [FutureBuilder<List<RowData>>(future: options, builder: (_, snapshot) {
      if (snapshot.hasError) return StudyButton.text(onPressed: () => setState(() => options = widget.store.options(textOf(widget.row, 'id'))), child: const Text('答案读取失败，点击重试'));
      if (!snapshot.hasData) return const StudyCircularProgressIndicator();
      final correct = snapshot.data!.where((r) => r['code'] == widget.row['answer']);
      return Padding(padding: const EdgeInsets.all(16), child: Text.rich(TextSpan(children: [
        contentTextSpan('正确答案：${widget.row['answer']}. '),
        contentTextSpan(correct.isEmpty ? '' : questionDisplayText(textOf(correct.first, 'content')), japanese: true),
        contentTextSpan('\n${textOf(widget.row, 'definition')}'),
      ]), style: const TextStyle(height: 1.6)));
    })],
  );
}

class PracticeDetailsPage extends StatefulWidget {
  const PracticeDetailsPage(this.app, this.session, {super.key});
  final AppController app;
  final RowData session;
  @override
  State<PracticeDetailsPage> createState() => _PracticeDetailsPageState();
}
class _PracticeDetailsPageState extends State<PracticeDetailsPage> {
  late Future<List<RowData>> future;
  @override
  void initState() { super.initState(); future = widget.app.store.practiceItems(textOf(widget.session, 'id')); }
  @override
  Widget build(BuildContext context) => PlaybackScaffold(appBar: StudyAppBar(title: const Text('练习详情')), body: FutureBuilder<List<RowData>>(future: future, builder: (_, snapshot) {
    if (snapshot.hasError) return Center(child: StudyButton.text(onPressed: () => setState(() => future = widget.app.store.practiceItems(textOf(widget.session, 'id'))), child: const Text('详情读取失败，点击重试')));
    if (!snapshot.hasData) return const Center(child: StudyCircularProgressIndicator());
    final items = snapshot.data!, session = widget.session;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(sessionTitle(session)), Text('开始：${displayDate(intOf(session, 'start_time'))}'),
      if (session['end_time'] != null) Text('完成：${displayDate(intOf(session, 'end_time'))}'),
      Text('作答用时：${items.fold<int>(0, (sum, row) => sum + intOf(row, 'duration')) ~/ 1000} 秒'),
      if (items.any((r) => r['answer_time'] == null)) StudyButton.filled(onPressed: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PracticePage(widget.app, textOf(session, 'id'))));
        if (mounted) Navigator.pop(context);
      }, child: const Text('继续练习')),
      for (var i = 0; i < items.length; i++) AnswerTile(widget.app.store, items[i], number: i + 1),
    ]);
  }));
}

class FontSettingsPage extends StatefulWidget {
  const FontSettingsPage(this.app, {super.key});
  final AppController app;
  @override
  State<FontSettingsPage> createState() => _FontSettingsPageState();
}

class _FontSettingsPageState extends State<FontSettingsPage> {
  late bool followSystem;
  late int percent;
  bool saving = false;
  String? saveHint;
  @override
  void initState() {
    super.initState();
    followSystem = widget.app.fontScale == 0;
    percent = followSystem ? 100 : widget.app.fontScale;
  }

  Future<void> _save() async {
    if (saving) return;
    setState(() { saving = true; saveHint = null; });
    try {
      await widget.app.setting('font_scale', followSystem ? 0 : percent);
      if (mounted) Navigator.pop(context);
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'app', operation: '保存字体设置');
      if (mounted) setState(() => saveHint = '设置暂未保存，请重试。');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewScaler = followSystem ? MediaQueryData.fromView(View.of(context)).textScaler : TextScaler.linear(percent / 100);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PlaybackScaffold(appBar: StudyAppBar(title: const Text('字体大小')), body: SafeArea(top: false, child: ListView(
      padding: const EdgeInsets.all(20), children: [
        StudySwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('跟随系统'),
          subtitle: const Text('使用系统设置的文字大小'), value: followSystem,
          onChanged: saving ? null : (value) => setState(() => followSystem = value)),
        if (!followSystem) ...[
          Text('文字大小：$percent%'),
          StudySlider(value: percent.toDouble(), min: 90, max: 150, divisions: 6, label: '$percent%',
            onChanged: saving ? null : (value) => setState(() => percent = (value / 10).round() * 10)),
          const Text('90% 较小 · 100% 标准 · 150% 最大'),
        ],
        const SizedBox(height: 16),
        const Text('预览'),
        const SizedBox(height: 8),
        MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: previewScaler), child: StudyCard(
          child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const RubyText('!日本語(にほんご)', ruby: true),
            const Text('日语 · 名词', style: TextStyle(fontSize: 16, height: 1.6)),
            const SizedBox(height: 16),
            Text.rich(TextSpan(children: [const TextSpan(text: '文法：'), contentTextSpan('名は名です', japanese: true)]), style: TextStyle(fontSize: 18, height: 1.4, fontWeight: FontWeight.w600,
              color: dark ? const Color(0xFFFFB366) : const Color(0xFFB85C00))),
            const Text('用于说明某人或某事物是什么。', style: TextStyle(fontSize: 16, height: 1.6)),
            const Padding(padding: EdgeInsets.only(left: 16, top: 8), child: Text.rich(TextSpan(children: [TextSpan(text: '李さんは学生です。', style: TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'))), TextSpan(text: '\n小李是学生。')]), style: TextStyle(fontSize: 14, height: 1.6))),
            const SizedBox(height: 16),
            const Text('请选择正确的读音。', style: TextStyle(fontSize: 22, height: 1.5)),
            const Text('A. にほんご', style: TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'), fontSize: 16, height: 1.6)),
          ])),
        )),
        const SizedBox(height: 16),
        const Text('保存后应用于全 App 的文字。自定义大小不叠加系统缩放，关闭并重新打开 App 后仍保留。'),
        if (saveHint != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(saveHint!)),
        const SizedBox(height: 20),
        StudyButton.filled(onPressed: saving ? null : _save, child: Text(saving ? '保存中' : '保存')),
        const SizedBox(height: 8),
        StudyButton.text(onPressed: saving ? null : () => setState(() { followSystem = true; percent = 100; }), child: const Text('恢复默认（跟随系统）')),
      ],
    )));
  }
}

class ProfilePanel extends StatefulWidget {
  const ProfilePanel(this.app, {super.key, this.scrollController, this.purchaseSectionKey});
  final AppController app;
  final ScrollController? scrollController;
  final GlobalKey? purchaseSectionKey;
  @override
  State<ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends State<ProfilePanel> with WidgetsBindingObserver {
  AppController get app => widget.app;
  ScrollController? get scrollController => widget.scrollController;
  GlobalKey? get purchaseSectionKey => widget.purchaseSectionKey;
  int _versionTapCount = 0;
  DateTime? _lastVersionTap;
  DateTime? _systemInfoVisibleUntil;
  Timer? _systemInfoHideTimer;

  bool get _systemInfoVisible => _systemInfoVisibleUntil?.isAfter(DateTime.now()) ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _onVersionTap() {
    if (_systemInfoVisible) return;
    final now = DateTime.now();
    final elapsed = _lastVersionTap == null ? null : now.difference(_lastVersionTap!);
    _versionTapCount = elapsed != null && !elapsed.isNegative && elapsed <= const Duration(seconds: 1)
        ? _versionTapCount + 1 : 1;
    _lastVersionTap = now;
    if (_versionTapCount < 10) return;
    _versionTapCount = 0;
    _lastVersionTap = null;
    setState(() => _systemInfoVisibleUntil = now.add(const Duration(minutes: 5)));
    _systemInfoHideTimer?.cancel();
    _systemInfoHideTimer = Timer(const Duration(minutes: 5), () {
      if (mounted) setState(() => _systemInfoVisibleUntil = null);
    });
  }

  Future<void> _requestAppReview() async {
    try {
      final requested = await const MethodChannel('yuzhichu/device')
          .invokeMethod<bool>('openAppReviewPage') ?? false;
      if (!requested && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          GlassSnackBar(content: const Text('暂时无法打开评价页面，请稍后重试')),
        );
      }
    } on PlatformException catch (e, stack) {
      SystemErrors.record(e, stack, module: 'profile', operation: '请求 App 评价');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          GlassSnackBar(content: const Text('暂时无法打开评价页面，请稍后重试')),
        );
      }
    } on MissingPluginException catch (e, stack) {
      SystemErrors.record(e, stack, module: 'profile', operation: '请求 App 评价');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          GlassSnackBar(content: const Text('暂时无法打开评价页面，请稍后重试')),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _versionTapCount = 0;
      _lastVersionTap = null;
    } else if (_systemInfoVisibleUntil != null && !_systemInfoVisible) {
      _systemInfoHideTimer?.cancel();
      setState(() => _systemInfoVisibleUntil = null);
    }
  }

  @override
  void dispose() {
    _systemInfoHideTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageBody(
    controller: scrollController,
    children: [
      Text(
        '我的',
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 18),
      StudyCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: vermilion.withValues(alpha: .13),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text(
                    '学',
                    style: TextStyle(
                      fontSize: 26,
                      color: vermilion,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '语之初',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text('连续学习 ${intOf(app.stats, 'streak')} 天'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SectionTitle('基础知识'),
      for (var i = 0; i < basicKnowledgeCategories.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        _settingCard(
          context,
          icon: basicKnowledgeCategories[i].icon,
          iconSize: 28,
          title: basicKnowledgeCategories[i].title,
          subtitle: basicKnowledgeCategories[i].subtitle,
          onTap: () => openPage(
            context,
            BasicKnowledgeCategoryPage(
              category: basicKnowledgeCategories[i],
              onOpenKana: () => openPage(context, KanaPage(app)),
            ),
          ),
        ),
      ],
      const SectionTitle('系统'),
      AnimatedBuilder(
        key: purchaseSectionKey,
        animation: app.studyRoomPurchase,
        builder: (context, _) {
          final purchase = app.studyRoomPurchase;
          return _settingCard(
            context,
            icon: Icons.shopping_bag_outlined,
            title: purchase.unlocked ? '自习室 已解锁': purchase.initialized ? '自习室 未购买' : '自习室 正在确认购买状态…',
            subtitle: purchase.unlocked ? '自习室功能已可使用' : '查看自习室购买内容',
            onTap: () => openPage(context, StudyRoomPurchasePage(purchase)),
          );
        },
      ),
      const SizedBox(height: 10),
      _settingCard(
        context,
        icon: Icons.star_outline,
        title: '给个好评',
        subtitle: '前往 App Store 评价语之初',
        onTap: _requestAppReview,
      ),
      const SizedBox(height: 10),
      _settingCard(
        context,
        icon: Icons.volunteer_activism_outlined,
        title: '打赏开发者',
        subtitle: '通过 App Store 支持开发者',
        onTap: () => openPage(context, DeveloperTipPage(app.developerTip)),
      ),
      const SizedBox(height: 10),
      _settingCard(
              context,
              icon: Icons.notifications_outlined,
              title: '通知公告',
              subtitle: '查看最新通知与历史公告',
              onTap: () => openPage(context, NoticeHistoryPage(app.notices)),
      ),
      const SectionTitle('设置'),
      _settingCard(
        context,
        icon: Icons.palette_outlined,
        title: '外观',
        subtitle: switch (textOf(app.settings, 'theme')) {
          'light' => '浅色',
          'dark' => '深色',
          _ => '跟随系统',
        },
        onTap: () => _appearance(context),
      ),
      const SizedBox(height: 10),
      _settingCard(
        context,
        icon: Icons.text_fields,
        iconSize: 28,
        title: '字体大小',
        subtitle: app.fontScale == 0 ? '跟随系统' : '${app.fontScale}%',
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FontSettingsPage(app))),
      ),
      const SizedBox(height: 10),
      _settingCard(
        context,
        icon: Icons.timer_outlined,
        title: '每日目标',
        subtitle: switch (intOf(app.settings, 'daily_goal', 10)) {
          5 => '轻松 · 5 分钟',
          20 => '进阶 · 20 分钟',
          _ => '标准 · 10 分钟',
        },
        onTap: () => _dailyGoal(context),
      ),
      const SectionTitle('信息'),
      _settingCard(
        context,
        icon: Icons.privacy_tip_outlined,
        title: '隐私政策',
        subtitle: '了解信息处理与隐私保护',
        onTap: () => openPage(context, const PrivacyPolicyPage()),
      ),
      const SizedBox(height: 10),
      _settingCard(
        context,
        icon: Icons.info_outline,
        title: '语之初 ${app.appVersionLabel}',
        subtitle: '语言学习初始的地方',
        showChevron: false,
        onTap: _onVersionTap,
      ),
      const SizedBox(height: 10),
      _settingCard(
        context,
        icon: Icons.copyright_outlined,
        title: '内容与版权',
        subtitle: '内容内容来源于网络资源，如有问题请联系作者。',
      ),
      const SizedBox(height: 10),
      _settingCard(
        context,
        icon: Icons.mail_outline,
        title: '关于',
        subtitle: '联系我们',
        onTap: () => openPage(context, AppInformationPage(app)),
      ),
      const SectionTitle('资源包'),
      _settingCard(
        context,
        icon: Icons.menu_book_outlined,
        title: '学习资源',
        subtitle: '下载与更新学习资源',
        onTap: () => openPage(context, LibraryPage(app)),
      ),
      const SizedBox(height: 10),
      _settingCard(
        context,
        icon: Icons.download_outlined,
        title: '自习资源',
        subtitle: '下载与更新自习资源',
        onTap: () => openPage(context, StudyResourcePage(app.studyRoomHost)),
      ),
      const SectionTitle('数据'),
      _settingCard(
        context,
        icon: Icons.delete_outline,
        iconSize: 32,
        iconColor: Colors.red,
        title: '清空 内容学习记录',
        subtitle: '删除本机内容学习记录，并重置外观和每日目标。',
        showChevron: false,
        onTap: () => _confirmReset(context),
      ),
      const SizedBox(height: 10),
      _settingCard(
        context,
        icon: Icons.delete_outline,
        iconSize: 32,
        iconColor: Colors.red,
        title: '清空 自习学习记录',
        subtitle: '删除本机自习学习记录。',
        showChevron: false,
        onTap: () => _confirmResetJlpt(context),
      ),
      if (_systemInfoVisible) ...[
        const SizedBox(height: 10),
        _settingCard(
          context,
          icon: Icons.bug_report_outlined,
          title: '系统信息记录',
          subtitle: '查看信息详情',
          onTap: () => openPage(context, SystemErrorPage(app.store)),
        ),
      ],
    ],
  );
  Widget _settingCard(BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    double iconSize = 30,
    Color iconColor = vermilion,
    bool showChevron = true,
    VoidCallback? onTap,
  }) => StudyCard(
    clipBehavior: Clip.antiAlias,
    child: StudyListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      minLeadingWidth: 32,
      horizontalTitleGap: 16,
      leading: SizedBox(
        width: 32,
        height: 32,
        child: Center(child: Icon(icon, color: iconColor, size: iconSize)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      subtitle: Text(subtitle),
      trailing: showChevron && onTap != null ? const Icon(Icons.chevron_right_rounded, size: 24) : null,
      onTap: onTap,
    ),
  );
  Future<void> _dailyGoal(BuildContext context) async {
    final current = intOf(app.settings, 'daily_goal', 10);
    await showGlassBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true, builder: (sheetContext) => SafeArea(child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const StudyListTile(title: Text('每日目标', style: TextStyle(fontWeight: FontWeight.w600))),
        for (final option in const [(5, '轻松 · 5 分钟'), (10, '标准 · 10 分钟'), (20, '进阶 · 20 分钟')])
          StudyListTile(
            title: Text(option.$2),
            trailing: Icon(current == option.$1 ? Icons.check_circle : Icons.circle_outlined, color: current == option.$1 ? vermilion : null),
            onTap: () async {
              await perform(sheetContext, () => app.setting('daily_goal', option.$1));
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
          ),
        const SizedBox(height: 8),
      ],
    ))));
  }
  Future<void> _appearance(BuildContext context) async {
    final current = textOf(app.settings, 'theme');
    await showGlassBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true, builder: (sheetContext) => SafeArea(child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const StudyListTile(title: Text('外观', style: TextStyle(fontWeight: FontWeight.w600))),
        for (final option in const [('system', '跟随系统'), ('light', '浅色'), ('dark', '深色')])
          StudyListTile(
            title: Text(option.$2),
            trailing: Icon(current == option.$1 ? Icons.check_circle : Icons.circle_outlined, color: current == option.$1 ? vermilion : null),
            onTap: () async {
              await perform(sheetContext, () => app.setting('theme', option.$1));
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
          ),
        const SizedBox(height: 8),
      ],
    ))));
  }
  Future<void> _confirmResetJlpt(BuildContext context) async {
    final yes = await showGlassDialog<bool>(context: context, builder: (context) => GlassAlertDialog(
      title: const Text('清空 自习学习记录？'),
      content: const Text('当前用户的 J练习、J测试全部数据（含历史记录、未完成进度、答题明细、错题、复习记录、等级设置及旧版记录）将被删除，无法撤销。已下载题库、用户身份和其他自习室功能的数据保留。'),
      actions: [
        StudyButton.text(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        StudyButton.filled(onPressed: () => Navigator.pop(context, true), child: const Text('确认清空')),
      ],
    ));
    if (yes == true && context.mounted) await perform(context, () async {
      await app.store.resetJlpt();
      await app.reload();
    });
  }
  Future<void> _confirmReset(BuildContext context) async {
    final yes = await showGlassDialog<bool>(context: context, builder: (context) => GlassAlertDialog(
      title: const Text('清空 内容学习记录？'),
      content: const Text('当前用户的内容课程进度、学习时长、答题记录、复习卡片和上次学习位置将被删除，无法撤销。外观恢复为跟随系统，每日目标恢复为 10 分钟。已下载内容、用户身份、字体大小和自习室记录保留。'),
      actions: [
        StudyButton.text(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        StudyButton.filled(onPressed: () => Navigator.pop(context, true), child: const Text('确认清空')),
      ],
    ));
    if (yes == true && context.mounted) await perform(context, () async { await app.store.reset(); await app.reload(); });
  }
}

class AppInformationPage extends StatelessWidget {
  const AppInformationPage(this.app, {super.key});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    Widget informationCard(Widget child) => StudyCard(margin: EdgeInsets.zero,
      child: Padding(padding: const EdgeInsets.all(24), child: child));

    return PlaybackScaffold(
      backgroundColor: dark ? theme.scaffoldBackgroundColor : const Color(0xFFF5F8FA),
      appBar: StudyAppBar(title: const Text('关于')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  informationCard(SizedBox(width: double.infinity, child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      const StudyGlassLogo(),
                      const SizedBox(height: 28),
                      Text('版本号：${app.appVersionLabel}',
                        textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 12),
                      Text('Copyright © 语之初', textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 16),
                    ],
                  ))),
                  const SizedBox(height: 24),
                  informationCard(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('联系我们', style: theme.textTheme.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 20),
                      SelectableText('32661267@qq.com', style: theme.textTheme.bodyLarge?.copyWith(
                        color: dark ? const Color(0xFF70B5FF) : const Color(0xFF007AFF))),
                    ],
                  )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

RowData kana(String hiragana, String katakana, String romaji, [String? audio]) =>
    {'id': 'kana:${hiragana}', 'hiragana': hiragana, 'katakana': katakana, 'romaji': romaji, 'audio': '${audio ?? romaji}.mp3'};

final voicedKana = <RowData>[
  kana('が', 'ガ', 'ga'), kana('ぎ', 'ギ', 'gi'), kana('ぐ', 'グ', 'gu'), kana('げ', 'ゲ', 'ge'), kana('ご', 'ゴ', 'go'),
  kana('ざ', 'ザ', 'za'), kana('じ', 'ジ', 'ji', 'zi'), kana('ず', 'ズ', 'zu'), kana('ぜ', 'ゼ', 'ze'), kana('ぞ', 'ゾ', 'zo'),
  kana('だ', 'ダ', 'da'), kana('ぢ', 'ヂ', 'ji', 'di'), kana('づ', 'ヅ', 'zu', 'du'), kana('で', 'デ', 'de'), kana('ど', 'ド', 'do'),
  kana('ば', 'バ', 'ba'), kana('び', 'ビ', 'bi'), kana('ぶ', 'ブ', 'bu'), kana('べ', 'ベ', 'be'), kana('ぼ', 'ボ', 'bo'),
  kana('ぱ', 'パ', 'pa'), kana('ぴ', 'ピ', 'pi'), kana('ぷ', 'プ', 'pu'), kana('ぺ', 'ペ', 'pe'), kana('ぽ', 'ポ', 'po'),
];

final contractedKana = <RowData>[
  kana('きゃ', 'キャ', 'kya'), kana('きゅ', 'キュ', 'kyu'), kana('きょ', 'キョ', 'kyo'),
  kana('ぎゃ', 'ギャ', 'gya'), kana('ぎゅ', 'ギュ', 'gyu'), kana('ぎょ', 'ギョ', 'gyo'),
  kana('しゃ', 'シャ', 'sha', 'sya'), kana('しゅ', 'シュ', 'shu', 'syu'), kana('しょ', 'ショ', 'sho', 'syo'),
  kana('じゃ', 'ジャ', 'ja', 'zya'), kana('じゅ', 'ジュ', 'ju', 'zyu'), kana('じょ', 'ジョ', 'jo', 'zyo'),
  kana('ちゃ', 'チャ', 'cha', 'cya'), kana('ちゅ', 'チュ', 'chu', 'cyu'), kana('ちょ', 'チョ', 'cho', 'cyo'),
  kana('にゃ', 'ニャ', 'nya'), kana('にゅ', 'ニュ', 'nyu'), kana('にょ', 'ニョ', 'nyo'),
  kana('ひゃ', 'ヒャ', 'hya'), kana('ひゅ', 'ヒュ', 'hyu'), kana('ひょ', 'ヒョ', 'hyo'),
  kana('びゃ', 'ビャ', 'bya'), kana('びゅ', 'ビュ', 'byu'), kana('びょ', 'ビョ', 'byo'),
  kana('ぴゃ', 'ピャ', 'pya'), kana('ぴゅ', 'ピュ', 'pyu'), kana('ぴょ', 'ピョ', 'pyo'),
  kana('みゃ', 'ミャ', 'mya'), kana('みゅ', 'ミュ', 'myu'), kana('みょ', 'ミョ', 'myo'),
  kana('りゃ', 'リャ', 'rya'), kana('りゅ', 'リュ', 'ryu'), kana('りょ', 'リョ', 'ryo'),
];

class KanaPage extends StatefulWidget {
  const KanaPage(this.app, {super.key});
  final AppController app;
  @override
  State<KanaPage> createState() => _KanaPageState();
}

class _KanaPageState extends State<KanaPage> {
  final playback = IosLessonPlayback.instance;
  bool katakana = false;
  late Future<List<RowData>> data;
  List<RowData> all = [];
  int? selectedIndex;
  bool busy = false;
  bool get owns => playback.lesson == 'kana';
  @override
  void initState() {
    super.initState();
    playback.addListener(_changed);
    data = widget.app.store.db.query('yzc_kana', orderBy: 'row_num,column_num');
    unawaited(perform(context, playback.refresh));
  }
  void _changed() { if (mounted) setState(() {}); }
  @override
  void dispose() { playback.removeListener(_changed); super.dispose(); }

  String _audioName(RowData row) {
    if (row['audio'] != null) return textOf(row, 'audio');
    final hira = textOf(row, 'hiragana');
    if (hira == 'を') return 'o.mp3';
    final name = switch (textOf(row, 'romaji')) {
      'shi' => 'si', 'chi' => 'ci', 'tsu' => 'cu', 'fu' => 'hu',
      final value => value,
    };
    return '$name.mp3';
  }

  Future<String> _audioPath(RowData row) async {
    final name = _audioName(row);
    final directory = Directory('${widget.app.store.root.path}/kana');
    final output = File('${directory.path}/$name');
    if (!await output.exists()) {
      final bytes = await rootBundle.load('assets/kana/$name');
      await directory.create(recursive: true);
      await output.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes), flush: true);
    }
    return output.path;
  }

  Future<void> _playFrom(int start, bool batch) async {
    if (busy || start < 0 || start >= all.length) return;
    if (!batch && owns && playback.active && playback.playingId == textOf(all[start], 'id')) {
      await perform(context, playback.paused ? playback.resume : playback.stop);
      return;
    }
    setState(() { selectedIndex = start; busy = true; });
    await perform(context, () async {
      if (playback.active) await playback.stop();
      final stopRevision = playback.stopRevision;
      final end = batch ? all.length : start + 1;
      final clips = <RowData>[];
      for (var i = start; i < end; i++) {
        clips.add({'id': textOf(all[i], 'id'), 'path': await _audioPath(all[i])});
      }
      if (!mounted || playback.stopRevision != stopRevision || playback.stopping) return;
      await playback.start({
        'lesson': 'kana', 'title': '五十音', 'words': true, 'batch': batch,
        'speed': widget.app.speed, 'repeat': 1, 'intervalSteps': 0, 'clips': clips,
      });
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> _continuous() async {
    if (owns && playback.active && playback.batch) {
      await perform(context, playback.stop);
      return;
    }
    final current = owns ? all.indexWhere((row) => textOf(row, 'id') == playback.playingId) : -1;
    await _playFrom(current >= 0 ? current : selectedIndex ?? 0, true);
  }

  Future<void> _tap(RowData row) async {
    final index = all.indexWhere((item) => item['id'] == row['id']);
    await _playFrom(index, false);
    if (!mounted) return;
    await showGlassBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 38),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${textOf(row, 'hiragana')}  ${textOf(row, 'katakana')}', style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'), fontSize: 52, fontWeight: FontWeight.w700)),
          Text(textOf(row, 'romaji'), style: Theme.of(context).textTheme.titleLarge?.copyWith(color: vermilion)),
          if (textOf(row, 'content').isNotEmpty) ...[const SizedBox(height: 12), Text(textOf(row, 'content'), style: const TextStyle(fontSize: 18))],
        ]),
      ),
    );
  }

  Widget _grid(List<RowData> cells, int columns) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: cells.length,
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns, crossAxisSpacing: 7, mainAxisSpacing: 7,
      childAspectRatio: .8 / math.pow(math.max(1.0, MediaQuery.textScalerOf(context).scale(26) / 26), 2),
    ),
    itemBuilder: (context, i) {
      final row = cells[i];
      if (intOf(row, 'placeholder') == 1) return const SizedBox.shrink();
      final active = owns && playback.active && playback.playingId == textOf(row, 'id');
      return StudyInkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: busy ? null : () => _tap(row),
        child: Container(
          decoration: BoxDecoration(
            color: active ? vermilion.withValues(alpha: .13) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? vermilion : Theme.of(context).colorScheme.outlineVariant, width: active ? 2 : 1),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(katakana ? textOf(row, 'katakana') : textOf(row, 'hiragana'), style: const TextStyle(fontFamily: 'Hiragino Sans', locale: Locale('ja', 'JP'), fontSize: 26, fontWeight: FontWeight.w700)),
            Text(textOf(row, 'romaji'), style: Theme.of(context).textTheme.labelSmall),
          ]),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => PlaybackScaffold(
    appBar: StudyAppBar(title: const Text('五十音'), actions: [
      StudyIconButton(
        tooltip: owns && playback.active && playback.batch ? '停止播放' : '连续播放',
        onPressed: busy ? null : _continuous,
        icon: Icon(owns && playback.active && playback.batch ? Icons.stop_rounded : Icons.play_arrow_rounded),
      ),
    ]),
    body: FutureBuilder<List<RowData>>(future: data, builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: StudyButton.text(onPressed: () => setState(() => data = widget.app.store.db.query('yzc_kana', orderBy: 'row_num,column_num')), child: const Text('五十音读取失败，点击重试')));
      if (!snapshot.hasData) return const Center(child: StudyCircularProgressIndicator());
      final cells = snapshot.data!;
      all = [...cells.where((row) => intOf(row, 'placeholder') != 1), ...voicedKana, ...contractedKana];
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: SizedBox(
            width: double.infinity,
            child: StudySegments<bool>(values: const {false: '平假名', true: '片假名'},
              selected: katakana, onChanged: (value) => setState(() => katakana = value)),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            children: [
              const SectionTitle('清音'),
              _grid(cells, 5),
              const SectionTitle('浊音与半浊音'),
              _grid(voicedKana, 5),
              const SectionTitle('拗音'),
              _grid(contractedKana, 3),
            ],
          ),
        ),
      ]);
    }),
  );
}

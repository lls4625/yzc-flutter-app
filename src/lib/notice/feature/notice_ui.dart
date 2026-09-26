import 'dart:async';
import 'package:flutter/material.dart';
import '../../ui.dart';
import '../../system_errors.dart';
import 'notice_service.dart';

String _date(AppNotice notice) {
  final date = notice.publishedAt.toLocal();
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${pad(date.month)}-${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}';
}

String _type(AppNotice notice) => switch (notice.type) {
  'warning' => '警告', 'important' => '重要', 'urgent' => '非常重要', _ => '告知',
};
IconData _icon(AppNotice notice) => switch (notice.type) {
  'warning' => Icons.warning_amber_rounded,
  'important' || 'urgent' => Icons.priority_high_rounded,
  _ => Icons.info_outline,
};

/// Lives below the navigator, outside both feature and demo page routes.
class NoticeHost extends StatefulWidget {
  const NoticeHost({super.key, required this.service, required this.child});
  final NoticeService service;
  final Widget child;
  @override
  State<NoticeHost> createState() => _NoticeHostState();
}

class _NoticeHostState extends State<NoticeHost> with WidgetsBindingObserver {
  bool _backgrounded = false;
  bool _busy = false;
  bool _showing = false;
  bool get _foreground => WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) unawaited(_check()); });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _backgrounded = true;
    } else if (state == AppLifecycleState.resumed && _backgrounded) {
      _backgrounded = false;
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    if (_busy) return;
    _busy = true;
    // A foreground event while an existing dialog is open never adds another.
    final allowDialog = !_showing;
    try {
      await widget.service.refresh();
      if (!mounted || !_foreground || _showing || !allowDialog) return;
      final notice = widget.service.latest;
      if (notice == null || widget.service.count(notice) >= notice.target) return;
      _showing = true;
      unawaited(_show(notice));
    } finally {
      _busy = false;
    }
  }

  Future<void> _show(AppNotice notice) async {
    try {
      await showGlassDialog<void>(context: context, barrierDismissible: false,
        builder: (_) => _NoticeDialog(service: widget.service, notice: notice));
    } catch (e, s) {
      SystemErrors.record(e, s, module: 'notice', operation: '展示公告');
    } finally {
      _showing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _NoticeDialog extends StatefulWidget {
  const _NoticeDialog({required this.service, required this.notice});
  final NoticeService service;
  final AppNotice notice;
  @override
  State<_NoticeDialog> createState() => _NoticeDialogState();
}

class _NoticeDialogState extends State<_NoticeDialog> with WidgetsBindingObserver {
  final Stopwatch _elapsed = Stopwatch();
  Timer? _timer;
  bool _saving = false;
  String? _error;
  int get _remaining {
    final value = widget.notice.delay - _elapsed.elapsed.inSeconds;
    return value > 0 ? value : 0;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) _elapsed.start();
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) setState(() {});
        if (_remaining == 0) _timer?.cancel();
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _elapsed.start();
    } else {
      _elapsed.stop();
    }
  }

  Future<void> _confirm() async {
    if (_saving || _remaining > 0) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.service.confirm(widget.notice);
      if (mounted) Navigator.of(context).pop();
    } catch (e, s) {
      SystemErrors.record(e, s, module: 'notice', operation: '保存公告确认');
      if (mounted) setState(() { _saving = false; _error = '确认暂未保存，请重试。'; });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _elapsed.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: GlassAlertDialog(
      title: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(_icon(widget.notice), color: widget.notice.type == 'info'
          ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error),
        const SizedBox(width: 12),
        Expanded(child: Text(widget.notice.title)),
      ]),
      content: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(widget.notice.content),
        const SizedBox(height: 16),
        Text('通知时间：${_date(widget.notice)}', style: Theme.of(context).textTheme.bodySmall),
        if (widget.notice.target > 1) ...[
          const SizedBox(height: 16),
          Text('已确认 ${widget.service.count(widget.notice)} / ${widget.notice.target} 次', style: Theme.of(context).textTheme.bodySmall),
        ],
        if (_error != null) ...[const SizedBox(height: 12), Text(_error!)],
      ]),
      actions: [StudyButton.filled(
        onPressed: _remaining > 0 || _saving ? null : _confirm,
        child: Text(_saving ? '正在保存…' : _remaining > 0 ? '我知道了（${_remaining}s）' : '我知道了'),
      )],
    ),
  );
}

class NoticeHistoryPage extends StatefulWidget {
  const NoticeHistoryPage(this.service, {super.key});
  final NoticeService service;
  @override
  State<NoticeHistoryPage> createState() => _NoticeHistoryPageState();
}

class _NoticeHistoryPageState extends State<NoticeHistoryPage> {
  @override
  void initState() {
    super.initState();
    // Local history never initiates an additional network request.
    unawaited(widget.service.initialize().catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('通知公告')),
    body: AnimatedBuilder(animation: widget.service, builder: (context, _) {
      final service = widget.service;
      final notices = service.visibleNotices.where((n) => !n.publishedAt.isAfter(DateTime.now())).toList();
      return ListView(padding: const EdgeInsets.all(16), children: [
        if (service.loadError != null) Padding(
          padding: const EdgeInsets.only(bottom: 16), child: Text(service.loadError!)),
        if (notices.isEmpty) const Padding(
          padding: EdgeInsets.all(32), child: Center(child: Text('暂无通知'))),
        for (final notice in notices) Card(child: ListTile(
          leading: Icon(_icon(notice)),
          title: Text(notice.title),
          subtitle: Text('${_date(notice)} · ${_type(notice)}\n${service.count(notice) == 0 ? '未确认' : '已确认 ${service.count(notice)} / ${notice.target} 次'}${notice.active(DateTime.now()) ? '' : ' · 已失效'}'),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => _NoticeDetailPage(
              service: service,
              notice: notice,
              canDelete: notice.id != notices.first.id,
            ))),
        )),
      ]);
    }),
  );
}

class _NoticeDetailPage extends StatefulWidget {
  const _NoticeDetailPage({required this.service, required this.notice, required this.canDelete});
  final NoticeService service;
  final AppNotice notice;
  final bool canDelete;
  @override
  State<_NoticeDetailPage> createState() => _NoticeDetailPageState();
}

class _NoticeDetailPageState extends State<_NoticeDetailPage> {
  bool _deleting = false;

  Future<void> _delete() async {
    if (_deleting) return;
    final confirmed = await showGlassDialog<bool>(context: context,
      builder: (dialogContext) => GlassAlertDialog(
        title: const Text('删除通知？'),
        content: const Text('确定删除此通知？'),
        actions: [
          StudyButton.text(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          StudyButton.filled(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('删除')),
        ],
      ));
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.service.dismiss(widget.notice);
      if (mounted) Navigator.of(context).pop();
    } catch (e, s) {
      SystemErrors.record(e, s, module: 'notice', operation: '删除本地通知');
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(GlassSnackBar(content: const Text('通知暂未删除，请重试。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('通知详情')),
    body: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.notice.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(_type(widget.notice)),
        const SizedBox(height: 24),
        SelectableText(widget.notice.content),
        const SizedBox(height: 24),
        Text('通知时间：${_date(widget.notice)}'),
      ],
    )),
    floatingActionButton: widget.canDelete ? FloatingActionButton.extended(
      onPressed: _deleting ? null : _delete,
      icon: const Icon(Icons.delete_outline),
      label: Text(_deleting ? '正在删除…' : '删除'),
    ) : null,
  );
}

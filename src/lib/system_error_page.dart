import 'package:flutter/material.dart';
import 'data.dart';
import 'playback_scaffold.dart';
import 'system_errors.dart';
import 'ui.dart';

class SystemErrorPage extends StatefulWidget {
  const SystemErrorPage(this.store, {super.key});
  final AppStore store;
  @override
  State<SystemErrorPage> createState() => _SystemErrorPageState();
}

class _SystemErrorPageState extends State<SystemErrorPage> {
  final List<RowData> _rows = [];
  bool _loading = false, _hasMore = true;
  bool _retryRefresh = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load({bool refresh = false}) async {
    if (_loading || _deleting) return;
    setState(() { _loading = true; _error = null; _retryRefresh = refresh; });
    try {
      await SystemErrors.flush();
      final last = refresh || _rows.isEmpty ? null : _rows.last;
      final rows = await widget.store.db.query('yzc_system_error',
        where: last == null ? null : '(occurred_at < ? OR (occurred_at = ? AND id < ?))',
        whereArgs: last == null ? null : [last['occurred_at'], last['occurred_at'], last['id']],
        orderBy: 'occurred_at DESC, id DESC', limit: 30);
      if (!mounted) return;
      setState(() {
        if (refresh) _rows.clear();
        _rows.addAll(rows);
        _hasMore = rows.length == 30;
      });
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'system', operation: '读取系统信息记录', hint: '信息记录读取失败，请重试');
      if (mounted) setState(() => _error = '信息记录读取失败，请重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _time(RowData row) => DateTime.fromMillisecondsSinceEpoch(intOf(row, 'occurred_at'))
      .toLocal().toString();

  Future<void> _deleteAll() async {
    if (_loading || _deleting) return;
    setState(() => _deleting = true);
    var deleted = false;
    try {
      final confirmed = await showGlassDialog<bool>(context: context,
        builder: (dialogContext) => GlassAlertDialog(
          title: const Text('删除全部系统信息？'),
          content: const Text('将删除本机全部系统信息记录，删除后无法恢复。'),
          actions: [
            StudyButton.text(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
            StudyButton.filled(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('确定')),
          ],
        ));
      if (confirmed != true || !mounted) return;
      await SystemErrors.deleteAll();
      deleted = true;
      if (mounted) setState(() {
        _rows.clear();
        _hasMore = false;
        _error = null;
        _retryRefresh = false;
      });
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'system', operation: '删除系统信息记录', hint: '删除失败，请重试');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败，请重试')));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
    if (deleted && mounted) await _load(refresh: true);
  }

  Widget _detail(String title, Object? value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      SelectableText(value == null || value.toString().isEmpty ? '未记录' : value.toString()),
    ]),
  );

  @override
  Widget build(BuildContext context) => PlaybackScaffold(
    appBar: AppBar(centerTitle: true, title: const Text('系统信息记录'), actions: [
      IconButton(tooltip: '删除全部记录', onPressed: _loading || _deleting ? null : _deleteAll,
        icon: const Icon(Icons.delete_outline)),
      IconButton(tooltip: '刷新', onPressed: _loading || _deleting ? null : () => _load(refresh: true), icon: const Icon(Icons.refresh)),
    ]),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('按发生时间倒序显示，点击记录可查看详细信息。'),
      const SizedBox(height: 12),
      if (!_loading && _error == null && _rows.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('暂无系统信息记录'))),
      for (final row in _rows) StudyCard(
        key: ValueKey(row['id']),
        child: ExpansionTile(
          title: Text(textOf(row, 'operation').isEmpty ? '系统信息' : textOf(row, 'operation')),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 6),
            Text(textOf(row, 'message').isEmpty ? textOf(row, 'user_hint') : textOf(row, 'message'),
              maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Text('${_time(row)}\n${textOf(row, 'module')} · ${textOf(row, 'error_type')}',
              style: Theme.of(context).textTheme.bodySmall),
          ]),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _detail('用户提示', row['user_hint']),
            _detail('记录编号 / 级别', '${row['id']} / ${row['severity']}'),
            _detail('异常类型 / 错误码', '${textOf(row, 'error_type')} / ${textOf(row, 'error_code')}'),
            _detail('详细错误', row['message']),
            _detail('调用堆栈', row['stack_trace']),
            _detail('关联信息', row['context_json']),
            _detail('应用版本 / 系统', '${textOf(row, 'app_version')} / ${textOf(row, 'platform')}\n${textOf(row, 'os_version')}'),
            _detail('用户 / 启动会话', '${textOf(row, 'user_id')} / ${textOf(row, 'session_id')}'),
          ],
        ),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!)),
      if (_loading) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
      else if (_error != null || _hasMore)
        StudyButton.text(onPressed: _deleting ? null : () => _load(refresh: _error != null && _retryRefresh), child: Text(_error != null ? '重试' : '加载更多')),
    ])),
  );
}

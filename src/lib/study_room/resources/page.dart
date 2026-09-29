import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../system_errors.dart';
import '../../glass_ui.dart';
import '../../resource_operation_ui.dart';
import '../host_contracts.dart';
import 'manager.dart';

Future<bool> ensureStudyResources(BuildContext context, StudyRoomHost host, String level) async {
  if (host.resources.isReady(level) && !host.resources.busy) return true;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudyResourcePage(host)));
  return host.resources.isReady(level) && !host.resources.busy;
}

class StudyResourcePage extends StatefulWidget {
  const StudyResourcePage(this.host, {super.key});
  final StudyRoomHost host;
  @override
  State<StudyResourcePage> createState() => _StudyResourcePageState();
}

class _StudyResourcePageState extends State<StudyResourcePage> with WidgetsBindingObserver {
  String _operationLabel = '资源下载';
  bool _confirming = false, _refreshAgain = false;
  bool get _pageCurrent => mounted && ModalRoute.of(context)?.isCurrent == true;
  bool get _operationBusy => _confirming || widget.host.resources.busy;
  bool get _resourceBusy => _operationBusy || widget.host.resources.checking;

  Future<void> _refresh() async {
    if (_resourceBusy || !_pageCurrent) return;
    await widget.host.resources.check();
    _resumeRefresh();
  }

  void _resumeRefresh() {
    if (_refreshAgain && _pageCurrent && !_resourceBusy) {
      _refreshAgain = false;
      unawaited(_refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pageCurrent) {
      if (_resourceBusy) { _refreshAgain = true; } else { unawaited(_refresh()); }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _openSettings() async {
    if (_operationBusy || !_pageCurrent) return;
    try {
      final opened = await const MethodChannel('yuzhichu/device').invokeMethod<bool>('openSettings');
      if (opened != true) _notice('请手动打开系统设置，检查“语之初”的无线数据设置。');
    } catch (error, stack) {
      SystemErrors.record(error, stack, module: 'selfstudy', operation: '打开网络设置');
      _notice('请手动打开系统设置，检查“语之初”的无线数据设置。');
    }
  }

  void _notice(String text) {
    if (_pageCurrent) ScaffoldMessenger.of(context).showSnackBar(GlassSnackBar(content: Text(text)));
  }

  void _back() {
    if (_operationBusy) {
      showResourceWait(context, _operationLabel);
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _install(String level) async {
    final resources = widget.host.resources;
    if (_resourceBusy || !_pageCurrent) return;
    if (!resources.canDownload(level)) return;
    setState(() => _operationLabel = resources.isReady(level) ? '资源更新' : '资源下载');
    try {
      await resources.install(level);
      if (resources.error.isEmpty && resources.isReady(level) && !resources.hasInvalidHash(level)) {
        _notice('题库已安装，可离线使用');
      }
    } finally { _resumeRefresh(); }
  }

  Future<void> _remove(String level) async {
    final resources = widget.host.resources;
    if (_resourceBusy || !_pageCurrent) return;
    setState(() { _confirming = true; _operationLabel = '资源删除'; });
    try {
      final confirmed = await showGlassDialog<bool>(context: context, builder: (context) => GlassAlertDialog(
        title: Text(resources.needsCleanup(level) && !resources.isReady(level) ? '清理剩余资源文件？' : '删除 ${level.toUpperCase()} 题库？'),
        content: Text('删除本机 ${level.toUpperCase()} 的题目、试卷及资源文件，保留其他级别、作答历史和错题记录。使用该级别开始新的练习或测试前需要重新下载。'),
        actions: [
          StudyButton.text(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          StudyButton.filled(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ));
      if (confirmed != true || !_pageCurrent || resources.busy) return;
      setState(() => _operationLabel = '资源删除');
      await resources.remove(level);
      if (resources.error.isEmpty) _notice('本地题库资源已删除，作答历史和错题记录已保留');
    } finally {
      if (mounted) setState(() => _confirming = false);
      _resumeRefresh();
    }
  }

  Future<void> _cleanup(String level) async {
    final resources = widget.host.resources;
    if (_resourceBusy || !_pageCurrent) return;
    setState(() => _operationLabel = '资源清理');
    try {
      await resources.cleanup(level);
      if (resources.error.isEmpty) _notice('资源文件已清理');
    } finally { _resumeRefresh(); }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Checking notifies shared listeners, including widgets outside this route.
    // Wait until mounting finishes before asking those widgets to rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Widget _levelCard(String level, StudyResources resources) {
    final colors = Theme.of(context).colorScheme;
    final ready = resources.isReady(level);
    final update = resources.hasLevelUpdate(level);
    final invalidHash = resources.hasInvalidHash(level);
    final operating = resources.busy && resources.activeLevel == level;
    final removable = resources.hasLocalData(level);
    final canDownload = resources.canDownload(level);
    final localOnly = resources.hasPublishedCatalog && !resources.isPublished(level) && removable;
    final counts = resources.attachmentCounts[level];
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: StudyCard(
      child: Stack(children: [
        Padding(padding: const EdgeInsets.fromLTRB(18, 18, 58, 18), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 58, height: 72,
                decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: Text(level.toUpperCase(), style: TextStyle(color: colors.onPrimary,
                  fontSize: 22, fontWeight: FontWeight.w700))),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(resources.textbook(level) ?? '', style: Theme.of(context).textTheme.titleMedium),
                if (!invalidHash || ready) ...[
                  const SizedBox(height: 6),
                  Text(operating ? '${resources.message}${resources.progress == null ? '' : ' ${(resources.progress! * 100).round()}%'}'
                    : resources.checking ? '检查更新中'
                    : !ready ? (removable
                        ? (localOnly
                            ? '本地资源异常，服务器已移除，可删除本地数据'
                            : canDownload ? '本地资源异常，可重新下载或删除' : '本地资源异常，可删除本地数据')
                        : '未下载')
                    : localOnly ? '本地资源，服务器已移除 · 可离线使用'
                    : update ? '有可用更新' : '已下载 · 可离线使用',
                    style: TextStyle(color: colors.primary)),
                ],
              ])),
            ]),
            if (ready) ...[
              const SizedBox(height: 12),
              Text(resources.infoError.isEmpty
                ? '当前题库共 ${resources.questionCounts[level.toUpperCase()] ?? 0} 题'
                : '题目数量暂不可用'),
              Text(counts == null ? '附件数量暂不可用' : '音频 ${counts.audio} 个 · 图片 ${counts.images} 张',
                style: Theme.of(context).textTheme.bodySmall),
            ],
            if (resources.needsCleanup(level)) ...[
              const SizedBox(height: 8),
              Text('有资源文件待清理', style: TextStyle(color: colors.error)),
              StudyButton.text(onPressed: _resourceBusy ? null : () => _cleanup(level),
                child: const Text('重试清理')),
            ],
            if (operating) ...[
              const SizedBox(height: 12),
              StudyLinearProgressIndicator(value: resources.progress),
            ],
            // Keep the two 48px controls separate even for a broken installation.
            if (!ready && removable && !resources.needsCleanup(level) && !operating)
              const SizedBox(height: 24),
          ],
        )),
        if (operating) Positioned(top: 7, right: 7, child: Semantics(
          label: '正在处理题库',
          child: SizedBox(width: 48, height: 48, child: Center(child: IconTheme(
            data: IconThemeData(color: colors.primary),
            child: const ResourceActivityIcon(checking: true),
          ))),
        )),
        if (!operating && invalidHash) Positioned(top: 7, right: 7, child: Tooltip(
          message: '资源校验错误',
          child: Semantics(
            label: '资源校验错误',
            child: SizedBox(width: 48, height: 48, child: Center(child: Icon(
              Icons.error_outline, color: colors.error,
            ))),
          ),
        )),
        if (!operating && !invalidHash && !_resourceBusy && canDownload && (!ready || update))
          Positioned(top: 7, right: 7, child: StudyIconButton(
            tooltip: update ? '更新题库' : '下载题库',
            icon: Icon(update ? Icons.system_update_alt : Icons.download_outlined),
            color: colors.primary,
            onPressed: canDownload ? () => _install(level) : null,
          )),
        if (removable) Positioned(bottom: 7, right: 7, child: StudyIconButton(
          tooltip: '删除本地题库', icon: const Icon(Icons.delete_outline), color: colors.error,
          onPressed: _resourceBusy ? null : () => _remove(level),
        )),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final resources = widget.host.resources;
    return AnimatedBuilder(animation: resources, builder: (context, _) {
      final visibleLevels = resources.visibleLevels;
      return PopScope(
        canPop: !_operationBusy,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _operationBusy) showResourceWait(context, _operationLabel);
        },
        child: Scaffold(
          appBar: StudyAppBar(title: const Text('自习资源'),
            leading: StudyIconButton(tooltip: '返回', onPressed: _back,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20)),
            actions: [StudyIconButton(
              tooltip: _operationBusy ? '正在$_operationLabel' : resources.checking ? '正在检查题库' : '刷新题库信息',
              onPressed: _resourceBusy ? null : _refresh,
              icon: ResourceActivityIcon(checking: _resourceBusy),
            )]),
          body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
            if (resources.error.isNotEmpty || resources.infoError.isNotEmpty)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: StudyCard(
                child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text([resources.error, resources.infoError].where((text) => text.isNotEmpty).join('\n')),
                    if (resources.ready) const Padding(padding: EdgeInsets.only(top: 8),
                      child: Text('已下载题库可继续离线使用。')),
                    if (resources.permissionError) StudyButton.text(
                      onPressed: _operationBusy ? null : _openSettings, child: const Text('前往设置')),
                  ])),
                  const SizedBox(width: 12),
                  StudyButton.text(
                    onPressed: _resourceBusy ? null : (resources.errorNeedsRecheck || resources.infoError.isNotEmpty
                      ? _refresh : resources.clearError),
                    child: Text(resources.errorNeedsRecheck || resources.infoError.isNotEmpty ? '重新检查' : '关闭')),
                ])),
              )),
            if (!resources.checking && visibleLevels.isEmpty &&
                resources.error.isEmpty && resources.infoError.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Text('暂无自习资源目录，可刷新获取。')),
            for (final level in visibleLevels) _levelCard(level, resources),
            const SizedBox(height: 14),
            const Text('按需下载 N1～N5 题库，J练习与J测试共用对应级别资源。更新或删除仅影响该级别，保留作答历史和错题记录。'),
          ])),
        ),
      );
    });
  }
}

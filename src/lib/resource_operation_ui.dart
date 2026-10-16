import 'package:flutter/material.dart';

import 'glass_ui.dart';
import 'resource_operation_coordinator.dart';

void showResourceWait(BuildContext context, String operation) {
  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(
      GlassSnackBar(
        duration: const Duration(seconds: 3),
        content: Text('请等待$operation完成'),
      ),
    );
}

String resourceOperationText(
  ResourceOperationStage? stage,
  double? progress, {
  required String subject,
}) {
  final percent = progress == null
      ? ''
      : ' ${(progress.clamp(0, 1) * 100).round()}%';
  return switch (stage) {
    ResourceOperationStage.catalog => '正在获取$subject信息',
    ResourceOperationStage.spaceCheck => '正在检查存储空间',
    ResourceOperationStage.download => '正在下载$percent',
    ResourceOperationStage.verify => '正在校验资源包',
    ResourceOperationStage.extract => '正在解压$percent',
    ResourceOperationStage.validate => '正在校验$subject',
    ResourceOperationStage.prepareInstall => '正在准备安装',
    ResourceOperationStage.installMedia => '正在安装$subject$percent',
    ResourceOperationStage.commit => '正在安全收尾',
    ResourceOperationStage.activation => '正在启用$subject',
    ResourceOperationStage.cleanup => '正在清理资源',
    ResourceOperationStage.rollback => '正在取消并恢复原内容',
    _ => '正在准备$subject',
  };
}

class ResourceOperationPanel extends StatelessWidget {
  const ResourceOperationPanel({
    required this.progress,
    required this.canCancel,
    required this.cancelling,
    required this.onCancel,
    super.key,
  });

  final double? progress;
  final bool canCancel;
  final bool cancelling;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      StudyLinearProgressIndicator(value: progress),
      const SizedBox(height: 4),
      StudyButton.text(
        onPressed: canCancel && !cancelling ? onCancel : null,
        child: Text(
          cancelling
              ? '正在取消…'
              : canCancel
              ? '取消下载'
              : '正在安全收尾…',
        ),
      ),
      Text(
        canCancel && !cancelling
            ? '取消后会恢复原有内容，完成前请留在当前页面。'
            : '正在保存或恢复内容，完成前请留在当前页面。',
      ),
    ],
  );
}

class ResourceActivityIcon extends StatefulWidget {
  const ResourceActivityIcon({required this.checking});
  final bool checking;

  @override
  State<ResourceActivityIcon> createState() => _ResourceActivityIconState();
}

class _ResourceActivityIconState extends State<ResourceActivityIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.checking) _rotation.repeat();
  }

  @override
  void didUpdateWidget(covariant ResourceActivityIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checking == widget.checking) return;
    if (widget.checking) {
      _rotation.repeat();
    } else {
      _rotation.reset();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RotationTransition(turns: _rotation, child: const Icon(Icons.refresh));
}

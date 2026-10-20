import 'package:flutter/material.dart';

import 'l10n/l10n.dart';

import 'glass_ui.dart';
import 'resource_operation_coordinator.dart';

void showResourceWait(BuildContext context, String operation) {
  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(
      GlassSnackBar(
        duration: const Duration(seconds: 3),
        content: Text(
          context.tr(
            '请等待${context.ui(operation)}完成',
            '請等待${context.ui(operation)}完成',
            'Please wait for ${context.ui(operation)} to finish.',
            '${context.ui(operation)}が完了するまでお待ちください。',
          ),
        ),
      ),
    );
}

String resourceOperationText(
  ResourceOperationStage? stage,
  double? progress, {
  required String subject,
  BuildContext? context,
}) {
  final percent = progress == null
      ? ''
      : ' ${(progress.clamp(0, 1) * 100).round()}%';
  String tr(String zhHans, String zhHant, String en, String ja) =>
      context == null ? zhHans : context.tr(zhHans, zhHant, en, ja);
  final label = context?.ui(subject) ?? subject;
  return switch (stage) {
    ResourceOperationStage.catalog => tr(
      '正在获取$subject信息',
      '正在取得$label資訊',
      'Getting $label information',
      '$label の情報を取得中',
    ),
    ResourceOperationStage.spaceCheck => tr(
      '正在检查存储空间',
      '正在檢查儲存空間',
      'Checking storage space',
      '空き容量を確認中',
    ),
    ResourceOperationStage.download => tr(
      '正在下载$percent',
      '正在下載$percent',
      'Downloading$percent',
      'ダウンロード中$percent',
    ),
    ResourceOperationStage.verify => tr(
      '正在校验资源包',
      '正在驗證資源包',
      'Verifying resource pack',
      'リソースパックを検証中',
    ),
    ResourceOperationStage.extract => tr(
      '正在解压$percent',
      '正在解壓縮$percent',
      'Extracting$percent',
      '展開中$percent',
    ),
    ResourceOperationStage.validate => tr(
      '正在校验$subject',
      '正在驗證$label',
      'Validating $label',
      '$label を検証中',
    ),
    ResourceOperationStage.prepareInstall => tr(
      '正在准备安装',
      '正在準備安裝',
      'Preparing installation',
      'インストールを準備中',
    ),
    ResourceOperationStage.installMedia => tr(
      '正在安装$subject$percent',
      '正在安裝$label$percent',
      'Installing $label$percent',
      '$label をインストール中$percent',
    ),
    ResourceOperationStage.commit => tr(
      '正在安全收尾',
      '正在安全收尾',
      'Finishing safely',
      '安全に仕上げ処理中',
    ),
    ResourceOperationStage.activation => tr(
      '正在启用$subject',
      '正在啟用$label',
      'Activating $label',
      '$label を有効化中',
    ),
    ResourceOperationStage.cleanup => tr(
      '正在清理资源',
      '正在清理資源',
      'Cleaning up resources',
      'リソースを整理中',
    ),
    ResourceOperationStage.rollback => tr(
      '正在取消并恢复原内容',
      '正在取消並復原原內容',
      'Cancelling and restoring original content',
      'キャンセルして元の教材を復元中',
    ),
    _ => tr('正在准备$subject', '正在準備$label', 'Preparing $label', '$label を準備中'),
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
              ? context.tr('正在取消…', '正在取消…', 'Cancelling…', 'キャンセル中…')
              : canCancel
              ? context.tr('取消下载', '取消下載', 'Cancel download', 'ダウンロードをキャンセル')
              : context.tr(
                  '正在安全收尾…',
                  '正在安全收尾…',
                  'Finishing safely…',
                  '安全に仕上げ処理中…',
                ),
        ),
      ),
      Text(
        canCancel && !cancelling
            ? context.tr(
                '取消后会恢复原有内容，完成前请留在当前页面。',
                '取消後會復原原有內容，完成前請留在目前頁面。',
                'Cancelling restores original content. Stay on this page until it finishes.',
                'キャンセル後は元の教材を復元します。完了するまでこのページに留まってください。',
              )
            : context.tr(
                '正在保存或恢复内容，完成前请留在当前页面。',
                '正在儲存或復原內容，完成前請留在目前頁面。',
                'Saving or restoring content. Stay on this page until it finishes.',
                '教材を保存または復元中です。完了するまでこのページに留まってください。',
              ),
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

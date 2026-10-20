import '../../l10n/l10n.dart';

import 'package:flutter/material.dart';

import '../../glass_ui.dart';
import '../host_contracts.dart';

class StudyRoomAccess {
  StudyRoomAccess(this.host);
  final StudyRoomHost host;
  bool _promptVisible = false;
  bool get available => host.isUnlocked() && !host.isPurchaseSaving();

  Future<bool> ensure(BuildContext context) async {
    if (available) return true;
    if (host.isPurchaseSaving()) {
      ScaffoldMessenger.of(context).showSnackBar(
        GlassSnackBar(
          content: Text(
            context.tr(
              '正在更新自习室购买状态，请稍后重试',
              '正在更新自習室購買狀態，請稍後重試',
              'Updating purchase status. Try again shortly.',
              '購入状況を更新中です。しばらくして再試行してください。',
            ),
          ),
        ),
      );
      return false;
    }
    if (_promptVisible) return false;
    _promptVisible = true;
    try {
      final confirmed = await showGlassDialog<bool>(
        context: context,
        builder: (dialogContext) => GlassAlertDialog(
          title: Text(context.tr('收费功能', '付費功能', 'Paid feature', '有料機能')),
          content: Text(
            context.tr(
              '此功能属于自习室收费功能，需要购买后才能使用。点击“确定”前往购买页面。',
              '此功能屬於自習室付費功能，需要購買後才能使用。點擊「確定」前往購買頁面。',
              'This Study Room feature requires a purchase. Tap OK to view purchase details.',
              'この自習室の機能は有料です。「OK」で購入内容の説明に進みます。',
            ),
          ),
          actions: [
            StudyButton.text(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.tr('取消', '取消', 'Cancel', 'キャンセル')),
            ),
            StudyButton.filled(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.tr('确定', '確定', 'OK', 'OK')),
            ),
          ],
        ),
      );
      if (confirmed == true && context.mounted) host.openPurchase();
    } finally {
      _promptVisible = false;
    }
    return false;
  }
}

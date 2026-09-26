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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(GlassSnackBar(content: const Text('正在更新自习室购买状态，请稍后重试')));
      return false;
    }
    if (_promptVisible) return false;
    _promptVisible = true;
    try {
      final confirmed = await showGlassDialog<bool>(
        context: context,
        builder: (dialogContext) => GlassAlertDialog(
          title: const Text('收费功能'),
          content: const Text('此功能属于自习室收费功能，需要购买后才能使用。点击“确定”前往购买页面。'),
          actions: [
            StudyButton.text(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            StudyButton.filled(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确定'),
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

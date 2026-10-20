import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';

/// Render stable native status codes at display time, including after a locale change.
String purchaseMessage(BuildContext context, String code) => switch (code) {
  'verification' => context.tr(
    '购买验证失败，请稍后恢复购买',
    '購買驗證失敗，請稍後恢復購買',
    'Purchase verification failed. Try restoring purchases later.',
    '購入の検証に失敗しました。後で購入を復元してください。',
  ),
  'sync_pending' => context.tr(
    '购买权益尚未同步，请稍后恢复购买',
    '購買權益尚未同步，請稍後恢復購買',
    'Your purchase has not synced yet. Try restoring it later.',
    '購入情報はまだ同期されていません。後で購入を復元してください。',
  ),
  'product_unavailable' => context.tr(
    '商品暂不可用，请重新加载',
    '商品暫不可用，請重新載入',
    'The product is unavailable. Reload to try again.',
    '商品を取得できません。再読み込みしてください。',
  ),
  'restricted' => context.tr(
    '当前设备不允许购买，可尝试恢复购买',
    '目前裝置不允許購買，可嘗試恢復購買',
    'Purchases are restricted on this device. You can try restoring purchases.',
    'この端末では購入が制限されています。購入の復元をお試しください。',
  ),
  'product' => context.tr(
    '商品加载失败，请检查网络后重试',
    '商品載入失敗，請檢查網路後重試',
    'Could not load the product. Check your connection and retry.',
    '商品を読み込めませんでした。接続を確認して再試行してください。',
  ),
  'busy' => context.tr(
    '正在处理购买，请稍候',
    '正在處理購買，請稍候',
    'Processing your purchase. Please wait.',
    '購入を処理しています。お待ちください。',
  ),
  'restore_empty' => context.tr(
    '未找到可恢复的自习室购买记录',
    '找不到可恢復的自習室購買紀錄',
    'No Study Room purchase was found to restore.',
    '復元できる自習室の購入履歴がありません。',
  ),
  'product_mismatch' => context.tr(
    '购买商品不匹配，请恢复购买',
    '購買商品不符，請恢復購買',
    'The purchased product does not match. Restore purchases.',
    '購入した商品が一致しません。購入を復元してください。',
  ),
  'pending' => context.tr(
    '购买待批准，批准后将自动解锁',
    '購買待核准，核准後將自動解鎖',
    'Purchase awaiting approval. Access unlocks after approval.',
    '購入は承認待ちです。承認後に自動でアンロックされます。',
  ),
  'cancelled' => context.tr(
    '已取消购买',
    '已取消購買',
    'Purchase cancelled.',
    '購入をキャンセルしました。',
  ),
  'incomplete' => context.tr(
    '购买尚未完成，请稍后恢复购买',
    '購買尚未完成，請稍後恢復購買',
    'Purchase is incomplete. Try restoring it later.',
    '購入は完了していません。後で購入を復元してください。',
  ),
  'restore' => context.tr(
    '恢复购买失败，请稍后重试',
    '恢復購買失敗，請稍後重試',
    'Could not restore purchases. Try again later.',
    '購入を復元できませんでした。後で再試行してください。',
  ),
  'purchase' => context.tr(
    '购买失败，请稍后重试',
    '購買失敗，請稍後重試',
    'Purchase failed. Try again later.',
    '購入に失敗しました。後で再試行してください。',
  ),
  'unsupported' => context.tr(
    '请在 iPhone 或 iPad 上购买或恢复购买',
    '請在 iPhone 或 iPad 上購買或恢復購買',
    'Use an iPhone or iPad to purchase or restore purchases.',
    '購入または購入の復元には iPhone または iPad を使用してください。',
  ),
  _ => context.tr(
    '购买服务暂不可用，请稍后重试',
    '購買服務暫不可用，請稍後重試',
    'Purchase service is unavailable. Try again later.',
    '購入サービスを利用できません。後で再試行してください。',
  ),
};

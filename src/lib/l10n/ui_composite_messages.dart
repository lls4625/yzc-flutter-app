import 'package:flutter/widgets.dart';

import 'l10n.dart';

/// Canonical legacy messages stay stored without locale. Interpret their fixed
/// wrappers only when rendering so a language change also updates cached errors.
String localizedCompositeMessage(BuildContext context, String message) {
  if (message.contains('\n'))
    return message.split('\n').map(context.ui).join('\n');
  if (message.endsWith('。学习记录已保留。')) {
    final cause = message.substring(0, message.length - '。学习记录已保留。'.length);
    return '${context.ui(cause)} ${context.l10n.recordsPreserved}';
  }
  if (message.startsWith('内容目录更新失败：')) {
    final cause = context.ui(message.substring('内容目录更新失败：'.length));
    return '${context.ui('内容目录更新失败')}：$cause';
  }
  if (message.startsWith('内容下载失败：')) {
    final cause = context.ui(message.substring('内容下载失败：'.length));
    return context.tr(
      '内容下载失败：$cause',
      '內容下載失敗：$cause',
      'Download failed: $cause',
      'ダウンロードに失敗しました：$cause',
    );
  }
  final summary = RegExp(r'^正常 (\d+)，跳过 (\d+)，降级 (\d+)$').firstMatch(message);
  if (summary != null)
    return context.tr(
      message,
      '正常 ${summary[1]}，略過 ${summary[2]}，降級 ${summary[3]}',
      '${summary[1]} normal, ${summary[2]} skipped, ${summary[3]} degraded',
      '正常 ${summary[1]}、スキップ ${summary[2]}、機能制限 ${summary[3]}',
    );
  if (message.endsWith('。')) {
    final plain = message.substring(0, message.length - 1);
    final translated = context.ui(plain);
    if (translated != plain) return translated;
  }
  return message;
}

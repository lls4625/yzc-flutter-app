import 'package:flutter/material.dart';

import '../../playback_scaffold.dart';
import '../../ui.dart';
import 'purchase.dart';

class StudyRoomPurchasePage extends StatelessWidget {
  const StudyRoomPurchasePage(this.purchase, {super.key});
  final StudyRoomPurchaseController purchase;

  @override
  Widget build(BuildContext context) => PlaybackScaffold(
    appBar: StudyAppBar(title: const Text('购买内容')),
    body: PageBody(children: [_StudyRoomPurchaseContent(purchase)]),
  );
}

class _StudyRoomPurchaseContent extends StatelessWidget {
  const _StudyRoomPurchaseContent(this.purchase);
  final StudyRoomPurchaseController purchase;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: purchase,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 10),
          child: Text(
            '自习室',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
        StudyCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('自习室功能解锁',
                  style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(purchase.unlocked ? '✓ 已解锁'
                    : !purchase.initialized ? '正在确认购买状态…' : '未购买',
                  style: Theme.of(context).textTheme.titleMedium),
                if (purchase.unlocked) ...[
                  const SizedBox(height: 4),
                  Text('自习室功能已可使用',
                    style: Theme.of(context).textTheme.bodyMedium),
                ],
                if (purchase.initialized && !purchase.unlocked) ...[
                  const SizedBox(height: 12),
                  StudyButton.filled(
                    onPressed: purchase.canPurchase ? purchase.purchase : null,
                    child: Text(purchase.busy ? '正在处理…'
                        : purchase.price != null ? '解锁自习室 ${purchase.price}'
                        : purchase.loadingProduct ? '正在加载价格…' : '购买暂不可用'),
                  ),
                  const SizedBox(height: 8),
                  if (purchase.price == null && purchase.supported) ...[
                    StudyButton.text(
                      onPressed: purchase.loadingProduct || purchase.busy
                          ? null : purchase.loadProduct,
                      child: const Text('重新加载'),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
                if (purchase.initialized)
                  StudyButton.text(
                    onPressed: purchase.busy || !purchase.supported ? null : () async {
                      await purchase.restore();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(GlassSnackBar(
                        content: Text(purchase.message ?? (purchase.unlocked
                            ? '购买权益已恢复，自习室已解锁'
                            : '未找到可恢复的自习室购买记录')),
                      ));
                    },
                    child: Text(purchase.busy ? '正在处理…' : '恢复购买'),
                  ),
                if (purchase.message != null) ...[
                  const SizedBox(height: 4),
                  Text(purchase.message!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

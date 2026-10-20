import 'package:flutter/material.dart';

import '../../playback_scaffold.dart';
import '../../ui.dart';
import 'purchase.dart';
import 'purchase_messages.dart';
import '../../l10n/l10n.dart';

class StudyRoomPurchasePage extends StatelessWidget {
  const StudyRoomPurchasePage(
    this.purchase, {
    super.key,
    this.learningTarget,
    this.changes,
  });
  final StudyRoomPurchaseController purchase;
  final String Function()? learningTarget;
  final Listenable? changes;

  @override
  Widget build(BuildContext context) => PlaybackScaffold(
    appBar: StudyAppBar(
      title: Text(context.tr('购买内容', '購買內容', 'Purchase content', 'コンテンツの購入')),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: _StudyRoomPurchaseContent(purchase, learningTarget, changes),
      ),
    ),
  );
}

class _StudyRoomPurchaseContent extends StatelessWidget {
  const _StudyRoomPurchaseContent(
    this.purchase,
    this.learningTarget,
    this.changes,
  );
  final String Function()? learningTarget;
  final Listenable? changes;
  final StudyRoomPurchaseController purchase;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([purchase, changes]),
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 10),
          child: Text(
            context.tr('自习室', '自習室', 'Study Room', '自習室'),
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
                Text(
                  context.tr(
                    '自习室功能解锁',
                    '自習室功能解鎖',
                    'Unlock Study Room',
                    '自習室をアンロック',
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Semantics(
                  container: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr(
                          '内容范围说明',
                          '內容範圍說明',
                          'Content availability',
                          '提供内容について',
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.tr(
                          'J练习与J测试目前仅提供日语学习题目，暂无英语对应内容。解锁自习室不会获得英语练习或英语测试题库。',
                          'J練習與J測試目前僅提供日語學習題目，暫無英語對應內容。解鎖自習室不會獲得英語練習或英語測試題庫。',
                          'J Practice and J Test currently provide questions for learning Japanese only. Equivalent English-learning content is not available. Unlocking the Study Room does not include English practice or test question banks.',
                          '「J練習」と「Jテスト」で現在提供しているのは日本語学習用の問題のみです。英語学習向けの対応コンテンツはありません。自習室のアンロックには、英語の練習問題集やテスト問題集は含まれません。',
                        ),
                      ),
                      if (learningTarget?.call() == 'en') ...[
                        const SizedBox(height: 8),
                        Text(
                          context.tr(
                            '你当前的学习目标是英语。J练习与J测试仍为日语学习内容；学习目标不会改变题目语言。',
                            '你目前的學習目標是英語。J練習與J測試仍為日語學習內容；學習目標不會改變題目語言。',
                            'Your current learning target is English. J Practice and J Test still contain Japanese-learning content; your learning target does not change the question language.',
                            '現在の学習目標は英語です。「J練習」と「Jテスト」の内容は日本語学習用のままです。学習目標を変更しても、問題の言語は変わりません。',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  purchase.unlocked
                      ? context.tr('✓ 已解锁', '✓ 已解鎖', '✓ Unlocked', '✓ アンロック済み')
                      : !purchase.initialized
                      ? context.tr(
                          '正在确认购买状态…',
                          '正在確認購買狀態…',
                          'Checking purchase status…',
                          '購入状況を確認中…',
                        )
                      : context.tr('未购买', '未購買', 'Not purchased', '未購入'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (purchase.unlocked) ...[
                  const SizedBox(height: 4),
                  Text(
                    context.tr(
                      '自习室功能已可使用',
                      '自習室功能已可使用',
                      'Study Room is ready to use',
                      '自習室を利用できます',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (purchase.initialized && !purchase.unlocked) ...[
                  const SizedBox(height: 12),
                  StudyButton.filled(
                    onPressed: purchase.canPurchase ? purchase.purchase : null,
                    child: Text(
                      purchase.busy
                          ? context.tr('正在处理…', '正在處理…', 'Processing…', '処理中…')
                          : purchase.price != null
                          ? context.tr(
                              '解锁自习室 ${purchase.price}',
                              '解鎖自習室 ${purchase.price}',
                              'Unlock Study Room ${purchase.price}',
                              '自習室をアンロック ${purchase.price}',
                            )
                          : purchase.loadingProduct
                          ? context.tr(
                              '正在加载价格…',
                              '正在載入價格…',
                              'Loading price…',
                              '価格を読み込み中…',
                            )
                          : context.tr(
                              '购买暂不可用',
                              '購買暫不可用',
                              'Purchase unavailable',
                              '購入できません',
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (purchase.price == null && purchase.supported) ...[
                    StudyButton.text(
                      onPressed: purchase.loadingProduct || purchase.busy
                          ? null
                          : purchase.loadProduct,
                      child: Text(
                        context.tr('重新加载', '重新載入', 'Reload', '再読み込み'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
                if (purchase.initialized)
                  StudyButton.text(
                    onPressed: purchase.busy || !purchase.supported
                        ? null
                        : () async {
                            await purchase.restore();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              GlassSnackBar(
                                content: Text(
                                  (purchase.message == null
                                          ? null
                                          : purchaseMessage(
                                              context,
                                              purchase.message!,
                                            )) ??
                                      (purchase.unlocked
                                          ? context.tr(
                                              '购买权益已恢复，自习室已解锁',
                                              '購買權益已恢復，自習室已解鎖',
                                              'Purchase restored. Study Room is unlocked.',
                                              '購入を復元しました。自習室はアンロック済みです。',
                                            )
                                          : context.tr(
                                              '未找到可恢复的自习室购买记录',
                                              '找不到可恢復的自習室購買紀錄',
                                              'No Study Room purchase was found to restore.',
                                              '復元できる自習室の購入履歴がありません。',
                                            )),
                                ),
                              ),
                            );
                          },
                    child: Text(
                      purchase.busy
                          ? context.tr('正在处理…', '正在處理…', 'Processing…', '処理中…')
                          : context.tr(
                              '恢复购买',
                              '恢復購買',
                              'Restore purchases',
                              '購入を復元',
                            ),
                    ),
                  ),
                if (purchase.message != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    purchaseMessage(context, purchase.message!),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

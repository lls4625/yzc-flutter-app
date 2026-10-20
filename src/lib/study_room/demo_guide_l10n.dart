import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../l10n/l10n.dart';
import 'demo_localization/ui.dart';

/// Keep error identifiers independent of the locale in which they occurred.
/// Rendering resolves the message using the current locale, so changing the UI
/// language never resets the running tour or leaves an old-language failure.
String demoGuideError(BuildContext context, String message) {
  final translations = _errors[message];
  if (translations == null) return studyUi(context, message);
  return context.tr(message, translations.$1, translations.$2, translations.$3);
}

const _errors = <String, (String, String, String)>{
  '演示位置暂不可用，请重新播放。': (
    '示範位置暫時無法使用，請重新播放。',
    'The demo target is unavailable. Replay the tour.',
    'デモの対象を表示できません。ガイドを再生し直してください。',
  ),
  '演示位置尚未完成布局，请重新播放。': (
    '示範位置尚未完成排版，請重新播放。',
    'The demo target is not laid out yet. Replay the tour.',
    'デモの対象の配置が完了していません。ガイドを再生し直してください。',
  ),
  '演示暂时中断，请重新播放或自己试试。': (
    '示範暫時中斷，請重新播放或自行試用。',
    'The tour was interrupted. Replay it or try the demo yourself.',
    'ガイドが中断されました。再生し直すか、自由に試してください。',
  ),
  '样例音频停止失败，请重试。': (
    '範例音訊停止失敗，請重試。',
    'Could not stop the sample audio. Please try again.',
    'サンプル音声を停止できませんでした。もう一度お試しください。',
  ),
  '演示位置尚未完成布局': (
    '示範位置尚未完成排版',
    'The demo target is not laid out yet.',
    'デモの対象の配置が完了していません。',
  ),
  '演示高亮位置暂不可用，请重新播放。': (
    '示範反白位置暫時無法使用，請重新播放。',
    'The demo highlight is unavailable. Replay the tour.',
    'デモの強調表示を利用できません。ガイドを再生し直してください。',
  ),
  '样例读取失败，请重新播放。': (
    '範例讀取失敗，請重新播放。',
    'Could not load the samples. Replay the tour.',
    'サンプルを読み込めませんでした。ガイドを再生し直してください。',
  ),
  '当前样例无法演示错误词组，请检查演示课文。': (
    '目前範例無法示範錯誤詞組，請檢查示範課文。',
    'This sample cannot demonstrate an incorrect phrase. Check the demo text.',
    'このサンプルでは誤った語句の選択を実演できません。デモの本文を確認してください。',
  ),
  '演示暂时中断，请重新播放。': (
    '示範暫時中斷，請重新播放。',
    'The tour was interrupted. Replay it to continue.',
    'ガイドが中断されました。再生し直してください。',
  ),
  '样例音频停止失败，请重新播放。': (
    '範例音訊停止失敗，請重新播放。',
    'Could not stop the sample audio. Replay the tour.',
    'サンプル音声を停止できませんでした。ガイドを再生し直してください。',
  ),
  '演示位置暂不可用，请重新播放': (
    '示範位置暫時無法使用，請重新播放',
    'The demo target is unavailable. Replay the tour.',
    'デモの対象を表示できません。ガイドを再生し直してください。',
  ),
  '演示恢复失败，请重新播放。': (
    '示範恢復失敗，請重新播放。',
    'Could not resume the tour. Replay it to continue.',
    'ガイドを再開できませんでした。再生し直してください。',
  ),
  '样例音频停止失败，请再次退出。': (
    '範例音訊停止失敗，請再次退出。',
    'Could not stop the sample audio. Try exiting again.',
    'サンプル音声を停止できませんでした。もう一度終了してください。',
  ),
  '读音播放未结束，请重新播放或自己试试。': (
    '讀音播放尚未結束，請重新播放或自行試用。',
    'Pronunciation playback has not finished. Replay the tour or try it yourself.',
    '発音の再生が完了していません。ガイドを再生し直すか、自由に試してください。',
  ),
  '演示位置暂不可用': (
    '示範位置暫時無法使用',
    'The demo target is unavailable.',
    'デモの対象を表示できません。',
  ),
  '演示页面仍在切换': (
    '示範頁面仍在切換',
    'The demo page is still changing.',
    'デモの画面を切り替えています。',
  ),
};

/// tutorial_coach_mark queues animation initialization on a zero-delay timer.
/// Removing an overlay in the same frame it mounts would dispose its animation
/// controller before that timer runs. Keep removal ordered after initialization.
void removeDemoGuideOverlay(TutorialCoachMark? coach) {
  if (coach == null) return;
  unawaited(Future<void>.delayed(Duration.zero, coach.removeOverlayEntry));
}

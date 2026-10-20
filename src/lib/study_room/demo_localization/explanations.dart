import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';

/// Presentation-only overlays. Keys include the demo kind, stable ID and version.
/// Formal repositories never import this file; original answers remain untouched.
const demoExplanationVersion = 1;
const demoExplanations = <String, List<String>>{
  'practice:demo-v1:1': [
    '学校读作「がっこう」，意为学校。小写「っ」表示促音。',
    '学校讀作「がっこう」，意為學校。小寫「っ」表示促音。',
    '学校 is read 「がっこう」 and means school. Small 「っ」 marks a doubled consonant.',
    '学校の読み方は「がっこう」です。小さい「っ」は促音を表します。',
  ],
  'practice:demo-v2:1': [
    '水读作「みず」，意为水。',
    '水讀作「みず」，意為水。',
    '水 is read 「みず」 and means water.',
    '水の読み方は「みず」です。',
  ],
  'practice:demo-g1:1': [
    '「を」表示动作的对象。「パンを食べます」意为吃面包。',
    '「を」表示動作的對象。「パンを食べます」意為吃麵包。',
    '「を」 marks the object of an action. 「パンを食べます」 means to eat bread.',
    '「を」は動作の対象を表します。「パンを食べます」では、食べるものがパンです。',
  ],
  'practice:demo-g2:1': [
    '「で」表示动作发生的场所，在学校学习日语。',
    '「で」表示動作發生的場所，在學校學習日語。',
    '「で」 marks where an action takes place: studying Japanese at school.',
    '「で」は動作が行われる場所を表します。日本語を勉強する場所は学校です。',
  ],
  'practice:demo-r1:1': [
    '原文「毎朝七時に起きます」说明每天早上七点起床。',
    '原文「毎朝七時に起きます」說明每天早上七點起床。',
    '「毎朝七時に起きます」 says that Tanaka gets up at seven every morning.',
    '本文の「毎朝七時に起きます」から、起きる時刻は七時だと分かります。',
  ],
  'practice:demo-r2:1': [
    '「月曜日は休みです」表示星期一休息。',
    '「月曜日は休みです」表示星期一休息。',
    '「月曜日は休みです」 means the library is closed on Mondays.',
    '「月曜日は休みです」とあるので、図書館の休館日は月曜日です。',
  ],
  'practice:demo-l1:1': [
    '女方说「お茶をお願いします」，因此选择茶。',
    '女方說「お茶をお願いします」，因此選擇茶。',
    'The woman says 「お茶をお願いします」, asking for tea.',
    '女の人は「お茶をお願いします」と言っているので、答えはお茶です。',
  ],
  'practice:demo-l2:1': [
    '双方约定三点见面。',
    '雙方約定三點見面。',
    'They agree to meet at three.',
    '二人は三時に会う約束をしています。',
  ],
  'test:test-demo-v1:1': [
    '山读作「やま」。',
    '山讀作「やま」。',
    '山 is read 「やま」 and means mountain.',
    '山の読み方は「やま」です。',
  ],
  'test:test-demo-g1:1': [
    '「に」表示动作发生的具体时间，七時に起きます意为七点起床。',
    '「に」表示動作發生的具體時間，七時に起きます意為七點起床。',
    '「に」 marks the specific time of an action. 「七時に起きます」 means to get up at seven.',
    '「に」は動作が行われる具体的な時刻を表します。「七時に起きます」は、起きる時刻が七時であることを示します。',
  ],
  'test:test-demo-l1:1': [
    '男方提议在车站见面，女方同意。',
    '男方提議在車站見面，女方同意。',
    'The man suggests meeting at the station, and the woman agrees.',
    '男の人が駅で会うことを提案し、女の人が同意しています。',
  ],
};

String demoExplanation(
  BuildContext context,
  String kind,
  String id, {
  int version = 1,
}) {
  final text = demoExplanations['$kind:$id:$version'];
  if (text == null || text.length != 4) {
    debugPrint('Missing demo explanation: $kind:$id:$version');
    return context.tr(
      '解析暂不可用',
      '解析暫不可用',
      'Explanation unavailable',
      '解説を表示できません',
    );
  }
  return context.tr(text[0], text[1], text[2], text[3]);
}

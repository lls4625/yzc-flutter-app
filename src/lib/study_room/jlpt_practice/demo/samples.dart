import 'models.dart';

// Authored demonstration samples, independent of installed learning resources.
Bank demoBank() {
  Json question(String id, String type, String stem, List<String> options,
      String answer, String explanation, {String? passage, String? transcript}) => {
    'id': 'demo-$id', 'version': 1, 'level': 'N5', 'type_code': type,
    'group_order': 0, 'selection_policy': 'single',
    'stem_json': {'text': stem},
    'material_json': {
      'blocks': [if (passage != null) {'type': 'text', 'text': passage}],
      if (transcript != null) 'transcript': transcript,
    },
    'presentation_json': {'instruction_ja': '正しい答えを一つ選んでください。',
      'prompt_timing': 'before_dialogue', 'options_channel': 'written_text'},
    'options_json': [for (var i = 0; i < options.length; i++) {'id': '${i + 1}', 'text': options[i]}],
    'answer_json': {'correct_option_ids': [answer]},
    'explanation_json': {'summary': explanation},
    'score_section_code': 'language', 'exam_section_code': 'practice',
  };
  return Bank({'papers': [{'questions': [
    question('v1', 'V_KANJI_READING', '「学校」の読み方はどれですか。',
      ['がっこう', 'がくせい', 'せんせい', 'がいこく'], '1', '学校读作「がっこう」，意为学校。小写「っ」表示促音。'),
    question('v2', 'V_KANJI_READING', '「水」の読み方はどれですか。',
      ['ひ', 'みず', 'き', 'やま'], '2', '水读作「みず」，意为水。'),
    question('g1', 'G_FORM', 'わたしは毎朝パン（　）食べます。',
      ['に', 'で', 'を', 'へ'], '3', '「を」表示动作的对象。「パンを食べます」意为吃面包。'),
    question('g2', 'G_FORM', '学校（　）日本語を勉強します。',
      ['で', 'へ', 'を', 'と'], '1', '「で」表示动作发生的场所，在学校学习日语。'),
    question('r1', 'R_SHORT', '田中さんは何時に起きますか。',
      ['六時', '七時', '八時', '九時'], '2', '原文「毎朝七時に起きます」说明每天早上七点起床。',
      passage: '田中さんは毎朝七時に起きます。八時に家を出ます。'),
    question('r2', 'R_SHORT', '図書館はいつ休みですか。',
      ['月曜日', '火曜日', '土曜日', '日曜日'], '1', '「月曜日は休みです」表示星期一休息。',
      passage: '図書館は午前九時から午後五時までです。月曜日は休みです。'),
    question('l1', 'L_POINT', '女の人は何を飲みますか。',
      ['コーヒー', 'お茶', '水', '牛乳'], '2', '女方说「お茶をお願いします」，因此选择茶。',
      transcript: '男：コーヒーを飲みますか。\n女：いいえ、お茶をお願いします。'),
    question('l2', 'L_POINT', '二人は何時に会いますか。',
      ['一時', '二時', '三時', '四時'], '3', '双方约定三点见面。',
      transcript: '男：明日、三時に会いましょう。\n女：はい、三時ですね。'),
  ]}]});
}

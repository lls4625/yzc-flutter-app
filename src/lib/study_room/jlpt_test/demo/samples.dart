import 'models.dart';

// A self-contained three-question tour paper, not an installed exam resource.
Bank demoBank() {
  Json question(String id, String type, String clock, String band, String stem,
      List<String> options, String answer, String explanation, {String? transcript}) => {
    'id': 'test-demo-$id', 'version': 1, 'level': 'N5', 'type_code': type,
    'paper_position': 1, 'item_id': id,
    'stem_json': {'text': stem},
    'material_json': {'blocks': <Json>[], if (transcript != null) 'transcript': transcript},
    'presentation_json': {'instruction_ja': '正しい答えを一つ選んでください。',
      'prompt_timing': 'before_dialogue', 'options_channel': 'written_text'},
    'options_json': [for (var i = 0; i < options.length; i++) {'id': '${i + 1}', 'text': options[i]}],
    'answer_json': {'correct_option_ids': [answer]},
    'explanation_json': {'summary': explanation},
    'score_section_code': band, 'exam_section_code': clock,
  };
  return Bank({'papers': [{
    'id': 'test-demo-paper', 'version': 1, 'title': 'N5 主流程演示卷 · 3题',
    'parts': [
      {'code': 'vocabulary', 'recommended_seconds': 60},
      {'code': 'grammar_reading', 'recommended_seconds': 60},
      {'code': 'listening', 'recommended_seconds': 60},
    ],
    'type_allocation': [
      {'type_code': 'V_KANJI_READING', 'name_ja': '漢字読み', 'question_count': 1},
      {'type_code': 'G_FORM', 'name_ja': '文法形式', 'question_count': 1},
      {'type_code': 'L_POINT', 'name_ja': 'ポイント理解', 'question_count': 1},
    ],
    'score_policy': {'bands': [
      {'code': 'language_reading', 'max_score': 120},
      {'code': 'listening', 'max_score': 60},
    ]},
    'questions': [
      question('v1', 'V_KANJI_READING', 'vocabulary', 'language_reading',
        '「山」の読み方はどれですか。', ['やま', 'かわ', 'うみ', 'そら'], '1', '山读作「やま」。'),
      question('g1', 'G_FORM', 'grammar_reading', 'language_reading',
        '毎朝、七時（　）起きます。', ['を', 'に', 'で', 'と'], '2', '「に」表示动作发生的具体时间，七時に起きます意为七点起床。'),
      question('l1', 'L_POINT', 'listening', 'listening',
        '二人はどこで会いますか。', ['駅', '学校', '図書館', '公園'], '1', '男方提议在车站见面，女方同意。',
        transcript: '男：明日、駅で会いましょう。\n女：はい、駅ですね。'),
    ],
  }]});
}

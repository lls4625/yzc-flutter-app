import 'dart:convert';

final _optionPattern = RegExp(r'^([A-D])[:：]([\s\S]+)$');

const questionRelations = ['word', 'grammar', 'content'];
String questionRelationLabel(Object? relation) => switch (relation) {
  'word' => '单词',
  'grammar' => '文法',
  'content' => '课文',
  _ => '练习',
};

String questionDisplayText(String text) => text.trim();

bool _emptyQuestionField(Object? value) => value == null || (value is String && value.trim().isEmpty);

/// Open course exercises are display-only. Legacy packages independently use
/// NULL or blank strings for each absent field.
bool isOpenDisplayQuestion(Map<String, Object?> question) =>
    _emptyQuestionField(question['options']) && _emptyQuestionField(question['answer']);

class QuestionAnswerMode {
  const QuestionAnswerMode._(this.open, this.options, this.issue);
  const QuestionAnswerMode.open() : this._(true, const <Map<String, Object?>>[], null);
  const QuestionAnswerMode.degraded(String issue) : this._(false, const <Map<String, Object?>>[], issue);
  const QuestionAnswerMode.choice(List<Map<String, Object?>> options) : this._(false, options, null);
  final bool open;
  final List<Map<String, Object?>> options;
  final String? issue;
  bool get answerable => !open && issue == null;
  bool get degraded => issue != null;
}

QuestionAnswerMode questionAnswerMode(Map<String, Object?> question) {
  if (isOpenDisplayQuestion(question)) return const QuestionAnswerMode.open();
  if (_emptyQuestionField(question['options']) || _emptyQuestionField(question['answer'])) {
    return const QuestionAnswerMode.degraded('练习题 options 与 answer 必须同时为空或同时有效');
  }
  try {
    return QuestionAnswerMode.choice(questionOptions(question['options'], question['answer']));
  } on FormatException catch (error) {
    return QuestionAnswerMode.degraded(error.message.toString());
  } on Object catch (error) {
    return QuestionAnswerMode.degraded('练习题选项无法解析：$error');
  }
}

bool isReadableQuestion(Map<String, Object?> question) {
  final content = question['content'] ?? question['question'];
  return content is String && content.trim().isNotEmpty && questionRelations.contains(question['relation']);
}
bool isAnswerableQuestion(Map<String, Object?> question) =>
    isReadableQuestion(question) && questionAnswerMode(question).answerable;
String questionAnswerCode(Map<String, Object?> question) =>
    question['answer'] is String ? (question['answer'] as String).trim() : '';

void validateQuestionAnswerMode(Map<String, Object?> question) {
  final mode = questionAnswerMode(question);
  if (mode.issue != null) throw FormatException(mode.issue!);
}

class QuestionBodyPart {
  const QuestionBodyPart(this.text);
  final String text;
}

class QuestionBody {
  const QuestionBody(this.heading, this.parts, this.footer);
  final String heading, footer;
  final List<QuestionBodyPart> parts;
}

/// Only recognized question formats are split into heading, body and footer.
/// Unknown formats remain intact so instructions and answers are not misplaced.
QuestionBody questionBody(String source) {
  final text = questionDisplayText(source).replaceAll('\r\n', '\n');
  final heading = RegExp(r'^【([^\n]+)】\n[^\n]+\n[ \t]*\n').firstMatch(text);
  if (heading == null) return QuestionBody(text, const [], '');
  final kind = heading.group(1)!;
  const wordKinds = {'汉字读音', '选择汉字写法', '漢字読み', '表記'};
  const readingKinds = {
    '短文阅读',
    '中篇阅读（课内练习）',
    '查找信息',
    '内容理解・短文',
    '内容理解・中文（課内練習）',
    '内容理解・長文',
    '統合理解',
    '主張理解',
    '情報検索',
  };
  const otherKinds = {
    '根据语境选词',
    '选择意思相近的表达',
    '语法填空',
    '句子排序',
    '短文语法填空',
    '語形成',
    '文脈規定',
    '言い換え類義',
    '用法',
    '文法形式の判断',
    '文の組み立て',
    '文章の文法',
  };
  if (!wordKinds.contains(kind) &&
      !readingKinds.contains(kind) &&
      !otherKinds.contains(kind)) {
    return QuestionBody(text, const [], '');
  }
  final rest = text.substring(heading.end);
  final note = RegExp(
    r'^(?:注|注释|注釈|備考|说明|説明)[：:]|^(?:问题|質問|問)[：:]',
    multiLine: true,
  ).firstMatch(rest);
  var end = note?.start ?? rest.length;
  // Japanese reading questions use a final paragraph without a question label.
  // Keep earlier paragraphs (including A/B passages) in the material.
  if (readingKinds.contains(kind)) {
    final beforeNote = rest.substring(0, end).trimRight();
    final separators = RegExp(r'\n[ \t]*\n').allMatches(beforeNote).toList();
    final explicitQuestion =
        note != null &&
        RegExp(r'^(?:问题|質問|問)[：:]').hasMatch(rest.substring(note.start));
    if (!explicitQuestion) {
      if (separators.isEmpty) return QuestionBody(text, const [], '');
      end = separators.last.start;
    }
  }
  final body = rest.substring(0, end).trim();
  if (body.isEmpty) return QuestionBody(text, const [], '');
  final parts = <QuestionBodyPart>[];
  if (wordKinds.contains(kind)) {
    var offset = 0;
    for (final match in RegExp(r'【([^【】\n]+)】').allMatches(body)) {
      parts.add(QuestionBodyPart(body.substring(offset, match.start + 1)));
      parts.add(QuestionBodyPart(match.group(1)!));
      offset = match.end - 1;
    }
    if (parts.isEmpty) return QuestionBody(text, const [], '');
    parts.add(QuestionBodyPart(body.substring(offset)));
  } else {
    parts.add(QuestionBodyPart(body));
  }
  return QuestionBody(
    text.substring(0, heading.end).trimRight(),
    parts,
    rest.substring(end).trim(),
  );
}

Map<String, int> practiceQuota(Iterable<Map<String, Object?>> rows) =>
    rows.any((row) => row['relation'] == 'content')
        ? const {'word': 4, 'grammar': 3, 'content': 3}
        : const {'word': 5, 'grammar': 5};

/// Parse the source JSON's ["A:...", "B:...", ...] without splitting storage.
List<Map<String, Object?>> questionOptions(Object? value, Object? answer) {
  if (value is! String) throw const FormatException('练习题 options 必须为 JSON 字符串');
  final decoded = jsonDecode(value.trim());
  if (decoded is! List || decoded.length < 2 || decoded.length > 4) {
    throw const FormatException('练习题必须有二至四个选项');
  }
  final result = <Map<String, Object?>>[];
  final codes = <String>{};
  for (final entry in decoded) {
    if (entry is! String) throw const FormatException('练习选项格式错误');
    final match = _optionPattern.firstMatch(entry);
    if (match == null ||
        match.group(2)!.trim().isEmpty ||
        !codes.add(match.group(1)!)) {
      throw const FormatException('练习选项必须为不重复的 A–D 且内容非空');
    }
    result.add({
      'code': match.group(1)!,
      'content': match.group(2)!,
      'sort': result.length,
    });
  }
  if (answer is! String || !codes.contains(answer.trim())) {
    throw const FormatException('练习答案未对应有效选项');
  }
  return result;
}

String encodeQuestionOptions(List<Map<String, Object?>> options) => jsonEncode([
  for (final option in options) '${option['code']}:${option['content']}',
]);

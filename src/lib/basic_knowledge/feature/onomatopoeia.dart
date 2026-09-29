import 'package:flutter/material.dart';

import '../../playback_scaffold.dart';
import '../../ui.dart';

const _accent = Color(0xFF6657A5);
const _categoryOrder = <String>[
  '声音与静寂',
  '天气与自然',
  '动作、速度与移动',
  '外观、光线与排列',
  '触感、形状与食感',
  '心情与心理反应',
  '身体感受与睡眠',
  '说话、学习与做事方式',
];

class OnomatopoeiaPage extends StatefulWidget {
  const OnomatopoeiaPage({super.key});

  @override
  State<OnomatopoeiaPage> createState() => _OnomatopoeiaPageState();
}

class _OnomatopoeiaPageState extends State<OnomatopoeiaPage> {
  int? _selectedLevel = 5;

  List<_OnomatopoeiaEntry> get _filteredEntries => _onomatopoeiaEntries
      .where((entry) => _selectedLevel == null || entry.level == _selectedLevel)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final entries = _filteredEntries;
    return PlaybackScaffold(
      appBar: const StudyAppBar(title: Text('拟声拟态词')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            const _OnomatopoeiaHero(),
            const SizedBox(height: 14),
            const _OnomatopoeiaGuide(),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final level in const [5, 4, 3, 2, 1]) ...[
                    _LevelChip(
                      label: 'N$level',
                      selected: _selectedLevel == level,
                      onSelected: () => setState(() => _selectedLevel = level),
                    ),
                    const SizedBox(width: 8),
                  ],
                  _LevelChip(
                    label: '全部',
                    selected: _selectedLevel == null,
                    onSelected: () => setState(() => _selectedLevel = null),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '显示 ${entries.length} / ${_onomatopoeiaEntries.length} 个词条。建议学习层级表示首次学习的参考难度，并非 JLPT 官方词表；选择某一级仅显示该级词条。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.45,
              ),
            ),
            if (entries.isEmpty)
              const _EmptyResult()
            else
              for (final category in _categoryOrder)
                if (entries.any((entry) => entry.category == category)) ...[
                  SectionTitle(category),
                  for (final entry in entries.where(
                    (entry) => entry.category == category,
                  )) ...[
                    _OnomatopoeiaEntryCard(entry: entry),
                    const SizedBox(height: 10),
                  ],
                ],
          ],
        ),
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    selectedColor: _accent.withValues(alpha: .16),
    side: BorderSide(color: selected ? _accent : Colors.transparent),
    labelStyle: TextStyle(
      color: selected
          ? _accent
          : Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    ),
    onSelected: (_) => onSelected(),
  );
}

class _OnomatopoeiaGuide extends StatelessWidget {
  const _OnomatopoeiaGuide();

  @override
  Widget build(BuildContext context) => StudyCard(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_outlined, color: _accent, size: 21),
              SizedBox(width: 8),
              Text(
                'オノマトペ快速认识',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '日语用声音直接描写声音、动作、状态和感受。常见五类为拟声、拟音、拟态、拟容、拟情；同一个词也可能因场景不同跨越多类。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 10),
          const Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _GuideTag('拟声：人和动物'),
              _GuideTag('拟音：自然和物体'),
              _GuideTag('拟态：状态'),
              _GuideTag('拟容：动作'),
              _GuideTag('拟情：心理和感觉'),
            ],
          ),
          const SizedBox(height: 14),
          const _OnomatopoeiaRubyText(
            '放进句子时怎么接',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          const SizedBox(height: 8),
          const _OnomatopoeiaRubyText(
            '直接修饰动词：ぐっすり!眠(ねむ)る（熟睡）。加「と」：ドアがばたんと!閉(し)まる（门砰地关上）。',
          ),
          const SizedBox(height: 8),
          const _OnomatopoeiaRubyText(
            '接「する／している」：わくわくする（兴奋期待）、つるつるしている（表面光滑）。',
          ),
          const SizedBox(height: 8),
          const _OnomatopoeiaRubyText(
            '修饰名词要按词记：ふわふわのパン（松软的面包）、つるつるした!石(いし)（光滑的石头）。并非所有词都能自由接「と／する／の／した」，请连同词条中的搭配一起学习。',
          ),
        ],
      ),
    ),
  );
}

class _GuideTag extends StatelessWidget {
  const _GuideTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: _accent.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: _accent,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _OnomatopoeiaHero extends StatefulWidget {
  const _OnomatopoeiaHero();

  @override
  State<_OnomatopoeiaHero> createState() => _OnomatopoeiaHeroState();
}

class _OnomatopoeiaHeroState extends State<_OnomatopoeiaHero> {
  var _selected = 0;

  static const _choices = <_RainChoice>[
    _RainChoice(
      word: 'ぽつぽつ',
      label: '零星落下',
      detail: '雨点稀疏地、一滴一滴落下，常用于刚开始下雨。',
      example: '!雨(あめ)がぽつぽつ!降(ふ)ってきた。',
      translation: '雨开始零星地下起来了。',
    ),
    _RainChoice(
      word: 'しとしと',
      label: '轻柔持续',
      detail: '细雨安静而持续地下，声音不大，给人湿润平静的感觉。',
      example: '!朝(あさ)から!雨(あめ)がしとしと!降(ふ)っている。',
      translation: '从早上起细雨一直静静地下着。',
    ),
    _RainChoice(
      word: 'ざあざあ',
      label: '猛烈倾泻',
      detail: '雨势很强、雨声连续而明显，也可描写大量流水声。',
      example: '!外(そと)は!雨(あめ)がざあざあ!降(ふ)っている。',
      translation: '外面正下着倾盆大雨。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final choice = _choices[_selected];
    return StudyCard(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/basic_knowledge/onomatopoeia_rain.jpg',
                    fit: BoxFit.cover,
                    cacheWidth: 960,
                    semanticLabel: '同一街道从零星雨点、持续细雨到猛烈大雨的三段式插画',
                  ),
                  for (var index = 0; index < _choices.length; index++)
                    Positioned(
                      left: constraints.maxWidth * index / 3,
                      top: 0,
                      width: constraints.maxWidth / 3,
                      height: constraints.maxHeight,
                      child: Semantics(
                        button: true,
                        selected: _selected == index,
                        label:
                            '${_choices[index].word}，${_choices[index].label}',
                        child: InkWell(
                          onTap: () => setState(() => _selected = index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            alignment: Alignment.bottomCenter,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _selected == index
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .58),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _choices[index].word,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 18),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Column(
                key: ValueKey(choice.word),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${choice.word} · ${choice.label}',
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(choice.detail, style: const TextStyle(height: 1.5)),
                  const SizedBox(height: 8),
                  _OnomatopoeiaRubyText(
                    choice.example,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    choice.translation,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RainChoice {
  const _RainChoice({
    required this.word,
    required this.label,
    required this.detail,
    required this.example,
    required this.translation,
  });

  final String word;
  final String label;
  final String detail;
  final String example;
  final String translation;
}

class _OnomatopoeiaEntryCard extends StatelessWidget {
  const _OnomatopoeiaEntryCard({required this.entry});

  final _OnomatopoeiaEntry entry;

  @override
  Widget build(BuildContext context) => StudyCard(
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      tilePadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Row(
        children: [
          Expanded(
            child: Text(
              entry.word,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
          ),
          _EntryBadge(label: 'N${entry.level}'),
          const SizedBox(width: 6),
          _EntryBadge(label: entry.kind, secondary: true),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(entry.meaning, style: const TextStyle(height: 1.4)),
      ),
      children: [
        _EntryDetail(label: '常见搭配', text: entry.usage),
        _EntryDetail(label: '例句', text: entry.example),
        _EntryDetail(label: '中文', text: entry.translation),
        _EntryDetail(label: '考试关注', text: entry.focus, isLast: true),
      ],
    ),
  );
}

class _EntryBadge extends StatelessWidget {
  const _EntryBadge({required this.label, this.secondary = false});

  final String label;
  final bool secondary;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: secondary
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : _accent.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: secondary
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : _accent,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _EntryDetail extends StatelessWidget {
  const _EntryDetail({
    required this.label,
    required this.text,
    this.isLast = false,
  });

  final String label;
  final String text;
  final bool isLast;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: const TextStyle(
              color: _accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
        ),
        Expanded(child: _OnomatopoeiaRubyText(text)),
      ],
    ),
  );
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 44),
    child: Column(
      children: [
        Icon(
          Icons.search_off_rounded,
          size: 38,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 10),
        const Text('没有符合条件的词条'),
      ],
    ),
  );
}

class _OnomatopoeiaRubyText extends StatelessWidget {
  const _OnomatopoeiaRubyText(
    this.text, {
    this.fontSize = 14,
    this.fontWeight = FontWeight.normal,
    this.color,
  });

  final String text;
  final double fontSize;
  final FontWeight fontWeight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final baseStyle = TextStyle(
      fontFamilyFallback: const ['Hiragino Sans'],
      fontSize: fontSize,
      height: 1.55,
      fontWeight: fontWeight,
    );
    final matches = RegExp(r'!([^!\s()]+)\(([^)]*)\)')
        .allMatches(text)
        .toList();
    if (matches.isEmpty) {
      return Text(text, style: baseStyle.copyWith(color: resolvedColor));
    }

    final tokens = <Widget>[];
    void addPlain(String value) {
      for (final rune in value.runes) {
        tokens.add(
          Text(
            String.fromCharCode(rune),
            style: baseStyle.copyWith(color: resolvedColor),
          ),
        );
      }
    }

    void addRuby(String surface, String reading) {
      tokens.add(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              reading,
              style: TextStyle(
                fontFamilyFallback: const ['Hiragino Sans'],
                locale: const Locale('ja', 'JP'),
                fontSize: fontSize * .53,
                height: 1.05,
                color: resolvedColor,
              ),
            ),
            Text(
              surface,
              style: baseStyle.copyWith(
                fontFamily: 'Hiragino Sans',
                locale: const Locale('ja', 'JP'),
                color: resolvedColor,
              ),
            ),
          ],
        ),
      );
    }

    var offset = 0;
    for (final match in matches) {
      addPlain(text.substring(offset, match.start));
      addRuby(match.group(1)!, match.group(2)!);
      offset = match.end;
    }
    addPlain(text.substring(offset));
    return Wrap(
      spacing: 0,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: tokens,
    );
  }
}

class _OnomatopoeiaEntry {
  const _OnomatopoeiaEntry(
    this.word,
    this.level,
    this.kind,
    this.category,
    this.meaning,
    this.usage,
    this.example,
    this.translation,
    this.focus,
  );

  final String word;
  final int level;
  final String kind;
  final String category;
  final String meaning;
  final String usage;
  final String example;
  final String translation;
  final String focus;
}

const _onomatopoeiaEntries = <_OnomatopoeiaEntry>[
  _OnomatopoeiaEntry(
    'ワンワン',
    5,
    '拟声',
    '声音与静寂',
    '狗连续吠叫的声音',
    'ワンワン!鳴(な)く',
    '!犬(いぬ)が!庭(にわ)でワンワン!鳴(な)いている。',
    '院子里的狗正汪汪叫。',
    '识别动物声音及「!鳴(な)く」的搭配。',
  ),
  _OnomatopoeiaEntry(
    'ニャーニャー',
    5,
    '拟声',
    '声音与静寂',
    '猫连续叫的声音',
    'ニャーニャー!鳴(な)く',
    '!子猫(こねこ)がニャーニャー!鳴(な)いている。',
    '小猫正在喵喵叫。',
    '注意片假名书写和动物对应关系。',
  ),
  _OnomatopoeiaEntry(
    'コケコッコー',
    5,
    '拟声',
    '声音与静寂',
    '公鸡啼叫的声音',
    'コケコッコーと!鳴(な)く',
    '!朝(あさ)になると、!鶏(にわとり)がコケコッコーと!鳴(な)く。',
    '一到早晨，公鸡就喔喔啼叫。',
    '听力中常通过声音判断动物或时间。',
  ),
  _OnomatopoeiaEntry(
    'ぴよぴよ',
    4,
    '拟声',
    '声音与静寂',
    '小鸡等幼鸟细小地鸣叫',
    'ぴよぴよ!鳴(な)く',
    'ひよこがぴよぴよ!鳴(な)きながら!歩(ある)いている。',
    '小鸡一边叽叽叫一边走。',
    '与幼小、细弱的声音形象关联。',
  ),
  _OnomatopoeiaEntry(
    'げらげら',
    4,
    '拟声',
    '声音与静寂',
    '毫不掩饰地放声大笑',
    'げらげら!笑(わら)う',
    'みんながその!話(はなし)を!聞(き)いてげらげら!笑(わら)った。',
    '大家听了那件事后哈哈大笑。',
    '和「くすくす」比较笑声大小。',
  ),
  _OnomatopoeiaEntry(
    'くすくす',
    3,
    '拟声',
    '声音与静寂',
    '压低声音轻轻窃笑',
    'くすくす!笑(わら)う',
    '!後(うし)ろの!席(せき)からくすくす!笑(わら)う!声(こえ)が!聞(き)こえた。',
    '从后排传来了窃笑声。',
    '重点辨析压低声音的笑与放声大笑。',
  ),
  _OnomatopoeiaEntry(
    'けたけた',
    1,
    '拟声',
    '声音与静寂',
    '发出轻薄而尖的连续笑声',
    'けたけた!笑(わら)う',
    '!子(こ)どもたちは!顔(かお)を!見合(みあ)わせてけたけた!笑(わら)った。',
    '孩子们互相看着对方咯咯地笑了。',
    '结合人物态度判断笑声带来的语感。',
  ),
  _OnomatopoeiaEntry(
    'ぺちゃくちゃ',
    3,
    '拟声',
    '声音与静寂',
    '多人不停地轻快闲聊',
    'ぺちゃくちゃしゃべる',
    '!授業中(じゅぎょうちゅう)にぺちゃくちゃしゃべってはいけない。',
    '上课时不能喋喋不休地聊天。',
    '常带“话多、吵闹”的评价色彩。',
  ),
  _OnomatopoeiaEntry(
    'ひそひそ',
    2,
    '拟声',
    '声音与静寂',
    '怕别人听见而小声交谈',
    'ひそひそ!話(はな)す／ひそひそ!声(ごえ)',
    '!二人(ふたり)は!廊下(ろうか)の!隅(すみ)でひそひそ!話(はな)していた。',
    '两人在走廊角落窃窃私语。',
    '通过场景判断低声交谈的目的。',
  ),
  _OnomatopoeiaEntry(
    'がやがや',
    3,
    '拟声',
    '声音与静寂',
    '许多人同时说话造成的嘈杂声',
    'がやがや!騒(さわ)ぐ／がやがやしている',
    '!駅前(えきまえ)は!人(ひと)が!多(おお)くてがやがやしていた。',
    '车站前人很多，十分嘈杂。',
    '常描述人群场所的整体声音。',
  ),
  _OnomatopoeiaEntry(
    'ざわざわ',
    3,
    '拟声／拟态',
    '声音与静寂',
    '人群骚动，或心里隐隐不安',
    '!会場(かいじょう)がざわざわする／!胸(むね)がざわざわする',
    '!発表(はっぴょう)の!直前(ちょくぜん)、!会場(かいじょう)がざわざわし!始(はじ)めた。',
    '发布前一刻，会场开始骚动起来。',
    '同一词可表示外部声音或内心不安。',
  ),
  _OnomatopoeiaEntry(
    'しーん',
    4,
    '拟态',
    '声音与静寂',
    '周围完全安静、没有声音',
    'しーんと!静(しず)まり!返(かえ)る',
    '!先生(せんせい)が!入(はい)ると、!教室(きょうしつ)はしーんとなった。',
    '老师一进来，教室顿时鸦雀无声。',
    '这是用声音形式描写“无声”的典型。',
  ),
  _OnomatopoeiaEntry(
    'がちゃん',
    4,
    '拟音',
    '声音与静寂',
    '玻璃、金属或硬物猛烈碰撞的声音',
    'がちゃんと!音(おと)がする／!閉(し)める',
    '!風(かぜ)で!窓(まど)ががちゃんと!閉(し)まった。',
    '窗户被风砰地关上了。',
    '根据声音判断物体和动作结果。',
  ),
  _OnomatopoeiaEntry(
    'ばたん',
    4,
    '拟音',
    '声音与静寂',
    '门或较大物体猛然倒下、关上的声音',
    'ばたんと!閉(し)める／!倒(たお)れる',
    '!彼(かれ)はドアをばたんと!閉(し)めて!出(で)ていった。',
    '他砰地关上门出去了。',
    '与「がちゃん」区分物体材质和声音性质。',
  ),
  _OnomatopoeiaEntry(
    'とんとん',
    4,
    '拟音',
    '声音与静寂',
    '轻而有节奏地敲击',
    'とんとんたたく',
    '!肩(かた)をとんとんたたいて!呼(よ)び!止(と)めた。',
    '我轻轻拍了拍他的肩膀叫住了他。',
    '注意轻敲动作及重复节奏。',
  ),

  _OnomatopoeiaEntry(
    'ぽつぽつ',
    5,
    '拟音／拟态',
    '天气与自然',
    '雨点稀疏地一滴滴落下',
    '!雨(あめ)がぽつぽつ!降(ふ)る',
    '!帰(かえ)るころ、!雨(あめ)がぽつぽつ!降(ふ)ってきた。',
    '回去的时候，雨开始零星地下起来。',
    '和「しとしと、ざあざあ」比较雨势。',
  ),
  _OnomatopoeiaEntry(
    'しとしと',
    3,
    '拟音／拟态',
    '天气与自然',
    '细雨安静而持续地下',
    '!雨(あめ)がしとしと!降(ふ)る',
    '!梅雨(つゆ)らしい!雨(あめ)が!一日中(いちにちじゅう)しとしと!降(ふ)っている。',
    '梅雨时节的细雨静静地下了一整天。',
    '关注“轻、细、持续”的综合语感。',
  ),
  _OnomatopoeiaEntry(
    'ざあざあ',
    5,
    '拟音',
    '天气与自然',
    '大雨猛烈而连续的声音',
    '!雨(あめ)がざあざあ!降(ふ)る',
    '!外(そと)は!雨(あめ)がざあざあ!降(ふ)っている。',
    '外面正下着倾盆大雨。',
    '听力中常用于判断天气及是否带伞。',
  ),
  _OnomatopoeiaEntry(
    'ぱらぱら',
    4,
    '拟音／拟态',
    '天气与自然',
    '雨滴等稀疏落下，数量不多',
    '!雨(あめ)がぱらぱら!降(ふ)る',
    '!空(そら)は!明(あか)るいのに、!雨(あめ)がぱらぱら!降(ふ)っている。',
    '天还很亮，却稀稀拉拉地下着雨。',
    '也可表示翻书或颗粒散落，需看名词。',
  ),
  _OnomatopoeiaEntry(
    'びゅうびゅう',
    4,
    '拟音',
    '天气与自然',
    '强风呼啸而过',
    '!風(かぜ)がびゅうびゅう!吹(ふ)く',
    '!台風(たいふう)が!近(ちか)づき、!風(かぜ)がびゅうびゅう!吹(ふ)いている。',
    '台风接近，强风正呼呼地刮。',
    '根据声音强度辨别恶劣天气。',
  ),
  _OnomatopoeiaEntry(
    'そよそよ',
    3,
    '拟态',
    '天气与自然',
    '微风轻柔地吹动',
    '!風(かぜ)がそよそよ!吹(ふ)く',
    '!窓(まど)から!涼(すず)しい!風(かぜ)がそよそよ!入(はい)ってきた。',
    '凉爽的微风从窗外轻轻吹进来。',
    '与强风「びゅうびゅう」形成程度对比。',
  ),
  _OnomatopoeiaEntry(
    'ごろごろ',
    5,
    '拟音／拟态',
    '天气与自然',
    '雷声滚动；也可表示滚动或闲躺',
    '!雷(かみなり)がごろごろ!鳴(な)る',
    '!遠(とお)くで!雷(かみなり)がごろごろ!鳴(な)っている。',
    '远处传来隆隆雷声。',
    '高频一词多义，必须结合主语判断。',
  ),
  _OnomatopoeiaEntry(
    'ぴかっ',
    5,
    '拟态',
    '天气与自然',
    '光突然短促地闪一下',
    'ぴかっと!光(ひか)る',
    '!空(そら)がぴかっと!光(ひか)ったあと、!雷(かみなり)が!鳴(な)った。',
    '天空闪了一下后，雷响了。',
    '促音体现瞬间性，注意和持续闪耀区别。',
  ),
  _OnomatopoeiaEntry(
    'どんより',
    3,
    '拟态',
    '天气与自然',
    '天空阴沉，也可形容心情沉重',
    '!空(そら)がどんより!曇(くも)る',
    '!朝(あさ)から!空(そら)がどんより!曇(くも)っている。',
    '从早上起天空就阴沉沉的。',
    '可从天气引申到表情、心情。',
  ),
  _OnomatopoeiaEntry(
    'じめじめ',
    3,
    '拟态',
    '天气与自然',
    '潮湿闷热，令人不舒服',
    'じめじめしている',
    '!梅雨(つゆ)は!部屋(へや)の!中(なか)までじめじめする。',
    '梅雨时连房间里都湿漉漉的。',
    '与湿度、梅雨、霉菌等语境搭配。',
  ),
  _OnomatopoeiaEntry(
    'むしむし',
    3,
    '拟态',
    '天气与自然',
    '温度和湿度都高，感觉闷热',
    'むしむしする',
    '!今日(きょう)は!朝(あさ)からむしむしして!暑(あつ)い。',
    '今天从早上起就又闷又热。',
    '区分「じめじめ」的潮湿与「むしむし」的闷热。',
  ),
  _OnomatopoeiaEntry(
    'ぽかぽか',
    4,
    '拟态',
    '天气与自然',
    '阳光或环境暖洋洋而舒适',
    'ぽかぽか!暖(あたた)かい／する',
    '!春(はる)の!日差(ひざ)しがぽかぽか!暖(あたた)かい。',
    '春日的阳光暖洋洋的。',
    '通常含舒适的正面感受。',
  ),
  _OnomatopoeiaEntry(
    'ひんやり',
    3,
    '拟态',
    '天气与自然',
    '接触或空气给人微凉感',
    'ひんやりする',
    '!森(もり)に!入(はい)ると、!空気(くうき)がひんやりしていた。',
    '一走进森林，空气微微发凉。',
    '强调接触或空气带来的微凉感。「!冷(つめ)たい」表示冷的感觉，是否舒适取决于对象和语境。',
  ),
  _OnomatopoeiaEntry(
    'しんしん',
    2,
    '拟态',
    '天气与自然',
    '雪在寂静中不停地下',
    '!雪(ゆき)がしんしん!降(ふ)る',
    '!夜(よる)になると、!雪(ゆき)がしんしん!降(ふ)り!始(はじ)めた。',
    '到了夜里，雪静静地下了起来。',
    '声音、寂静和持续状态结合的文学性表达。',
  ),
  _OnomatopoeiaEntry(
    'じわじわ',
    1,
    '拟态',
    '天气与自然',
    '热、冷或影响缓慢而持续地扩散',
    'じわじわ!広(ひろ)がる／!効(き)く',
    '!日差(ひざ)しの!強(つよ)さがじわじわ!体(からだ)にこたえてきた。',
    '强烈阳光的影响渐渐让身体吃不消。',
    '用于过程渐进，需根据主语判断具体变化。',
  ),
  _OnomatopoeiaEntry(
    'のろのろ',
    3,
    '拟容',
    '动作、速度与移动',
    '动作或移动迟缓得令人着急',
    'のろのろ!歩(ある)く／!進(すす)む',
    '!渋滞(じゅうたい)で!車(くるま)がのろのろ!進(すす)んでいる。',
    '因为堵车，汽车慢吞吞地前进。',
    '常带速度太慢的负面评价。',
  ),
  _OnomatopoeiaEntry(
    'うろうろ',
    3,
    '拟容',
    '动作、速度与移动',
    '没有明确目标地来回走动',
    'うろうろする',
    '!道(みち)に!迷(まよ)って!駅(えき)の!周(まわ)りをうろうろした。',
    '迷路后在车站周围转来转去。',
    '重点理解缺少目的或拿不定主意。',
  ),
  _OnomatopoeiaEntry(
    'ぶらぶら',
    4,
    '拟容',
    '动作、速度与移动',
    '悠闲闲逛；也可表示物体摇晃',
    'ぶらぶら!歩(ある)く／ぶら!下(さ)がる',
    '!休(やす)みの!日(ひ)は!商店街(しょうてんがい)をぶらぶら!歩(ある)く。',
    '休息日会在商店街随意逛逛。',
    '根据动词判断“闲逛”还是“摇晃”。',
  ),
  _OnomatopoeiaEntry(
    'てくてく',
    4,
    '拟容',
    '动作、速度与移动',
    '以稳定步伐走较长距离',
    'てくてく!歩(ある)く',
    '!駅(えき)から!家(いえ)まで!二十分(にじゅっぷん)てくてく!歩(ある)いた。',
    '从车站到家稳稳地走了二十分钟。',
    '与小步轻快的「とことこ」比较。',
  ),
  _OnomatopoeiaEntry(
    'とことこ',
    4,
    '拟容',
    '动作、速度与移动',
    '以小步幅轻快地走',
    'とことこ!歩(ある)く',
    '!小(ちい)さな!子(こ)どもが!母親(ははおや)の!後(あと)をとことこ!歩(ある)いている。',
    '小孩子迈着小步跟在妈妈后面。',
    '常和儿童、小动物、小型机器搭配。',
  ),
  _OnomatopoeiaEntry(
    'すたすた',
    3,
    '拟容',
    '动作、速度与移动',
    '脚步利落、毫不犹豫地快走',
    'すたすた!歩(ある)く',
    '!彼女(かのじょ)は!振(ふ)り!返(かえ)らずにすたすた!歩(ある)いていった。',
    '她头也不回地快步走了。',
    '动作方式也可能表现人物态度。',
  ),
  _OnomatopoeiaEntry(
    'よろよろ',
    3,
    '拟容',
    '动作、速度与移动',
    '身体不稳，快要摔倒地走',
    'よろよろ!歩(ある)く',
    '!疲(つか)れた!選手(せんしゅ)がよろよろゴールに!近(ちか)づいた。',
    '疲惫的选手摇摇晃晃地接近终点。',
    '通过身体状态推断疲劳或虚弱。',
  ),
  _OnomatopoeiaEntry(
    'ふらふら',
    3,
    '拟容／拟情',
    '动作、速度与移动',
    '身体摇晃；也可表示随意游荡或意志不定',
    'ふらふらする／!歩(ある)く',
    '!熱(ねつ)があって、!立(た)つと!少(すこ)しふらふらする。',
    '因为发烧，站起来时有点晕晃。',
    '多义词，注意身体、行动和态度三类语境。',
  ),
  _OnomatopoeiaEntry(
    'ぐんぐん',
    3,
    '拟态',
    '动作、速度与移动',
    '势头强劲而连续地增长、前进',
    'ぐんぐん!伸(の)びる／!進(すす)む',
    'この!植物(しょくぶつ)は!夏(なつ)になるとぐんぐん!伸(の)びる。',
    '这种植物一到夏天就迅速生长。',
    '常见于能力、成绩、植物等明显增长。',
  ),
  _OnomatopoeiaEntry(
    'さっと',
    3,
    '拟容',
    '动作、速度与移动',
    '动作迅速、利落，一下完成',
    'さっと!動(うご)く／!拭(ふ)く',
    '!店員(てんいん)はテーブルをさっと!拭(ふ)いた。',
    '店员迅速地擦了一下桌子。',
    '促音体现短促、快速，关注动作结果。',
  ),
  _OnomatopoeiaEntry(
    'ぱっと',
    3,
    '拟态／拟容',
    '动作、速度与移动',
    '瞬间展开、亮起、显现或采取动作',
    'ぱっと!開(ひら)く／!明(あか)るくなる',
    '!名前(なまえ)を!呼(よ)ぶと、!彼(かれ)の!表情(ひょうじょう)がぱっと!明(あか)るくなった。',
    '一叫他的名字，他的表情顿时开朗起来。',
    '意义依赖后接动词，考查语境选择。',
  ),
  _OnomatopoeiaEntry(
    'もたもた',
    2,
    '拟容',
    '动作、速度与移动',
    '动作磨蹭、不够利落',
    'もたもたする',
    'もたもたしていると、!電車(でんしゃ)に!遅(おく)れるよ。',
    '再磨磨蹭蹭就赶不上电车了。',
    '常含催促或批评语气。',
  ),
  _OnomatopoeiaEntry(
    'まごまご',
    2,
    '拟容',
    '动作、速度与移动',
    '因不熟悉或慌乱而不知所措',
    'まごまごする',
    '!初(はじ)めての!機械(きかい)を!前(まえ)にして、!彼(かれ)はまごまごしていた。',
    '面对第一次使用的机器，他不知所措。',
    '重点不是速度慢，而是不知道怎么做。',
  ),
  _OnomatopoeiaEntry(
    'おずおず',
    1,
    '拟容',
    '动作、速度与移动',
    '胆怯、犹豫地采取行动',
    'おずおず!尋(たず)ねる／!差(さ)し!出(だ)す',
    '!学生(がくせい)はおずおず!手(て)を!挙(あ)げて!質問(しつもん)した。',
    '学生怯生生地举手提问。',
    '从动作推断胆怯、缺乏自信的态度。',
  ),
  _OnomatopoeiaEntry(
    'いそいそ',
    1,
    '拟容',
    '动作、速度与移动',
    '因期待高兴而轻快地行动',
    'いそいそ!出(で)かける／!準備(じゅんび)する',
    '!父(ちち)は!旅行(りょこう)の!準備(じゅんび)をいそいそと!始(はじ)めた。',
    '父亲兴冲冲地开始准备旅行。',
    '表面是动作，背后包含愉快期待。',
  ),

  _OnomatopoeiaEntry(
    'きらきら',
    4,
    '拟态',
    '外观、光线与排列',
    '细小光点不断闪耀，给人明亮美感',
    'きらきら!光(ひか)る／!輝(かがや)く',
    '!夜空(よぞら)で!星(ほし)がきらきら!光(ひか)っている。',
    '星星在夜空中闪闪发光。',
    '与表面光洁的「ぴかぴか」区分。',
  ),
  _OnomatopoeiaEntry(
    'ぴかぴか',
    4,
    '拟态',
    '外观、光线与排列',
    '表面擦得发亮；也可表示崭新',
    'ぴかぴか!光(ひか)る／の!一年生(いちねんせい)',
    '!磨(みが)いた!靴(くつ)がぴかぴか!光(ひか)っている。',
    '擦过的鞋亮晶晶的。',
    '既可描述光泽，也可表达“崭新”。',
  ),
  _OnomatopoeiaEntry(
    'ぎらぎら',
    2,
    '拟态',
    '外观、光线与排列',
    '光线刺眼强烈；眼神带强烈欲望',
    'ぎらぎら!照(て)る／した!目(め)',
    '!真夏(まなつ)の!太陽(たいよう)がぎらぎら!照(て)りつけている。',
    '盛夏的太阳火辣辣地照射着。',
    '通常比「きらきら」强烈且可能不舒适。',
  ),
  _OnomatopoeiaEntry(
    'ちらちら',
    3,
    '拟态',
    '外观、光线与排列',
    '小东西零星飘落；视线反复瞟向某处',
    'ちらちら!降(ふ)る／!見(み)る',
    '!雪(ゆき)がちらちら!降(ふ)り!始(はじ)めた。',
    '雪开始零星飘落。',
    '根据动词区分飘落、闪现和偷瞟。',
  ),
  _OnomatopoeiaEntry(
    'ぼんやり',
    3,
    '拟态／拟情',
    '外观、光线与排列',
    '轮廓模糊；也可表示发呆、不集中',
    'ぼんやり!見(み)える／!考(かんが)える',
    '!霧(きり)の!向(む)こうに!建物(たてもの)がぼんやり!見(み)える。',
    '雾的另一边隐约看得见建筑物。',
    '常考视觉模糊与精神不集中的多义。',
  ),
  _OnomatopoeiaEntry(
    'くっきり',
    2,
    '拟态',
    '外观、光线与排列',
    '轮廓、颜色或差异非常清晰',
    'くっきり!見(み)える／!写(うつ)る',
    '!雨上(あめあ)がりの!空(そら)に!虹(にじ)がくっきり!見(み)えた。',
    '雨后的天空中清楚地出现了彩虹。',
    '与「ぼんやり」构成反义对比。',
  ),
  _OnomatopoeiaEntry(
    'はっきり',
    4,
    '拟态',
    '外观、光线与排列',
    '清楚明确，没有模糊或含混',
    'はっきり!見(み)える／!言(い)う',
    '!遠(とお)くの!山(やま)がはっきり!見(み)える。',
    '远处的山看得很清楚。',
    '可修饰视觉、声音、记忆和表达。',
  ),
  _OnomatopoeiaEntry(
    'ずらり',
    2,
    '拟态',
    '外观、光线与排列',
    '许多同类事物整齐地排成一列',
    'ずらりと!並(なら)ぶ',
    '!店(みせ)の!前(まえ)に!新(あたら)しい!自転車(じてんしゃ)がずらりと!並(なら)んでいる。',
    '店前整齐地排着一长列新自行车。',
    '关注数量多且排列整齐的共同条件。',
  ),
  _OnomatopoeiaEntry(
    'ぎっしり',
    2,
    '拟态',
    '外观、光线与排列',
    '空间被紧密地塞满，几乎无空隙',
    'ぎっしり!詰(つ)まる／!並(なら)ぶ',
    '!箱(はこ)の!中(なか)には!本(ほん)がぎっしり!詰(つ)まっていた。',
    '箱子里塞满了书。',
    '和单纯数量多相比，更强调密度。',
  ),
  _OnomatopoeiaEntry(
    'ばらばら',
    3,
    '拟态',
    '外观、光线与排列',
    '分散、不统一，或拆成零散部分',
    'ばらばらになる／!行動(こうどう)する',
    '!意見(いけん)がばらばらで、!結論(けつろん)が!出(で)なかった。',
    '意见各不相同，没能得出结论。',
    '可描述物理分散，也可描述意见不一致。',
  ),
  _OnomatopoeiaEntry(
    'ごちゃごちゃ',
    3,
    '拟态',
    '外观、光线与排列',
    '东西混杂凌乱，或说明复杂难懂',
    'ごちゃごちゃしている',
    '!机(つくえ)の!上(うえ)がごちゃごちゃしていて、!資料(しりょう)が!見(み)つからない。',
    '桌面乱糟糟的，找不到资料。',
    '与整洁的「すっきり」形成对比。',
  ),
  _OnomatopoeiaEntry(
    'すっきり',
    3,
    '拟态／拟情',
    '外观、光线与排列',
    '整洁清爽；心情或身体感到舒畅',
    'すっきり!片(かた)づく／する',
    '!部屋(へや)を!片(かた)づけたら、!気分(きぶん)もすっきりした。',
    '收拾完房间后，心情也舒畅了。',
    '可同时描述外观和内在感受。',
  ),
  _OnomatopoeiaEntry(
    'そっくり',
    3,
    '拟态',
    '外观、光线与排列',
    '外貌、声音或性质非常相似',
    '～にそっくりだ',
    '!妹(いもうと)は!顔(かお)が!母(はは)にそっくりだ。',
    '妹妹的长相和母亲一模一样。',
    '固定使用「AはBにそっくりだ」。',
  ),
  _OnomatopoeiaEntry(
    'けばけば',
    1,
    '拟态',
    '外观、光线与排列',
    '颜色、装饰过分鲜艳而显得俗气',
    'けばけばしい／けばけばした',
    'けばけばした!色(いろ)の!看板(かんばん)が!並(なら)んでいる。',
    '一排招牌颜色花哨刺眼。',
    '带明显负面评价，注意语体和对象。',
  ),
  _OnomatopoeiaEntry(
    'ごてごて',
    1,
    '拟态',
    '外观、光线与排列',
    '装饰、说明等堆得过多而繁杂',
    'ごてごて!飾(かざ)る／している',
    '!壁(かべ)が!写真(しゃしん)や!飾(かざ)りでごてごてしている。',
    '墙上堆满照片和装饰，显得很杂乱。',
    '重点理解“添加过多”造成的累赘感。',
  ),

  _OnomatopoeiaEntry(
    'つるつる',
    4,
    '拟态',
    '触感、形状与食感',
    '表面光滑，没有粗糙或阻力',
    'つるつるしている／!滑(すべ)る',
    'この!石(いし)は!表面(ひょうめん)がつるつるしている。',
    '这块石头的表面很光滑。',
    '可描述物体表面、皮肤或面条入口感。',
  ),
  _OnomatopoeiaEntry(
    'ざらざら',
    3,
    '拟态',
    '触感、形状与食感',
    '表面粗糙，有细小颗粒感',
    'ざらざらしている',
    'この!紙(かみ)は!触(さわ)ると!少(すこ)しざらざらしている。',
    '这张纸摸起来有点粗糙。',
    '与「つるつる」形成触感反义。',
  ),
  _OnomatopoeiaEntry(
    'ふわふわ',
    4,
    '拟态',
    '触感、形状与食感',
    '轻柔蓬松；也可表示飘浮或心神不定',
    'ふわふわしている',
    '!焼(や)きたてのパンがふわふわでおいしい。',
    '刚烤好的面包松松软软，很好吃。',
    '根据对象判断蓬松、飘浮或不踏实。',
  ),
  _OnomatopoeiaEntry(
    'べたべた',
    3,
    '拟态',
    '触感、形状与食感',
    '表面黏腻；也可形容人与人过分亲昵',
    'べたべたする／くっつく',
    '!汗(あせ)でシャツが!肌(はだ)にべたべたくっつく。',
    '衬衫因汗水黏在皮肤上。',
    '物理黏腻和人际评价是两种常见意义。',
  ),
  _OnomatopoeiaEntry(
    'ねばねば',
    3,
    '拟态',
    '触感、形状与食感',
    '有黏性并能拉丝',
    'ねばねばしている',
    '!納豆(なっとう)はねばねばしているが、!栄養(えいよう)がある。',
    '纳豆虽然黏糊糊的，但很有营养。',
    '常见于食物质地，注意与べたべた区别。',
  ),
  _OnomatopoeiaEntry(
    'ぬるぬる',
    3,
    '拟态',
    '触感、形状与食感',
    '表面有黏液，湿滑难抓',
    'ぬるぬるしている／!滑(すべ)る',
    'この!魚(さかな)は!表面(ひょうめん)がぬるぬるして!持(も)ちにくい。',
    '这条鱼表面滑溜溜的，很难拿。',
    '核心是湿滑，通常不是干燥的光滑。',
  ),
  _OnomatopoeiaEntry(
    'かちかち',
    4,
    '拟态／拟音',
    '触感、形状与食感',
    '非常坚硬；也可表示钟表声或紧张僵硬',
    'かちかちに!凍(こお)る／!固(かた)い',
    '!冷凍庫(れいとうこ)の!中(なか)で!肉(にく)がかちかちに!凍(こお)っていた。',
    '肉在冷冻室里冻得硬邦邦的。',
    '多义词，主语决定硬度、声音或紧张。',
  ),
  _OnomatopoeiaEntry(
    'ごわごわ',
    2,
    '拟态',
    '触感、形状与食感',
    '布料、头发等粗硬不柔软',
    'ごわごわしている',
    'このタオルは!洗(あら)ったあと!少(すこ)しごわごわになった。',
    '这条毛巾洗后变得有点粗硬。',
    '常描述纤维类物品的触感。',
  ),
  _OnomatopoeiaEntry(
    'ぶよぶよ',
    2,
    '拟态',
    '触感、形状与食感',
    '松软膨胀，按下会变形且缺乏弹性',
    'ぶよぶよしている',
    '!水(みず)を!吸(す)った!段(だん)ボールがぶよぶよになった。',
    '吸了水的纸箱变得松软发胀。',
    '通常含不结实、不健康的负面感觉。',
  ),
  _OnomatopoeiaEntry(
    'ぷにぷに',
    2,
    '拟态',
    '触感、形状与食感',
    '柔软且富有弹性，按压感明显',
    'ぷにぷにしている',
    'このグミはぷにぷにしていて!弾力(だんりょく)がある。',
    '这种软糖QQ的，很有弹性。',
    '较口语，注意和负面「ぶよぶよ」区分。',
  ),
  _OnomatopoeiaEntry(
    'ぱりぱり',
    3,
    '拟音／拟态',
    '触感、形状与食感',
    '薄而干脆，咬下会发出清脆声',
    'ぱりぱりしている／!食(た)べる',
    '!焼(や)きたてのせんべいはぱりぱりしている。',
    '刚烤好的仙贝香脆可口。',
    '从声音和口感共同判断食物状态。',
  ),
  _OnomatopoeiaEntry(
    'さくさく',
    3,
    '拟音／拟态',
    '触感、形状与食感',
    '酥脆轻快；也可表示工作顺利推进',
    'さくさくした／!進(すす)む',
    'このクッキーは!軽(かる)くてさくさくしている。',
    '这种曲奇轻盈酥脆。',
    '网络和口语中也常表示处理顺畅。',
  ),
  _OnomatopoeiaEntry(
    'もちもち',
    3,
    '拟态',
    '触感、形状与食感',
    '柔软有黏性和弹性',
    'もちもちしている',
    'このパンは!中(なか)がもちもちしている。',
    '这种面包里面柔软又有嚼劲。',
    '常用于面包、面条、米饭及皮肤触感。',
  ),
  _OnomatopoeiaEntry(
    'しっとり',
    3,
    '拟态',
    '触感、形状与食感',
    '含适度水分，柔润而不黏腻',
    'しっとりしている',
    'このケーキはしっとりしていて!食(た)べやすい。',
    '这个蛋糕湿润柔软，很好入口。',
    '与干燥的「ぱさぱさ」形成对比。',
  ),
  _OnomatopoeiaEntry(
    'ぱさぱさ',
    3,
    '拟态',
    '触感、形状与食感',
    '缺少水分，干松不润',
    'ぱさぱさしている',
    '!焼(や)きすぎて、!鶏肉(とりにく)がぱさぱさになった。',
    '烤得太久，鸡肉变柴了。',
    '常描述食物、头发或皮肤缺水。',
  ),

  _OnomatopoeiaEntry(
    'わくわく',
    4,
    '拟情',
    '心情与心理反应',
    '因期待即将发生的事而兴奋',
    'わくわくする',
    '!来週(らいしゅう)の!旅行(りょこう)を!考(かんが)えるとわくわくする。',
    '一想到下周的旅行就很兴奋。',
    '通常面向未来，带积极期待。',
  ),
  _OnomatopoeiaEntry(
    'どきどき',
    4,
    '拟情／拟音',
    '心情与心理反应',
    '因紧张、期待或运动而心跳加快',
    'どきどきする',
    '!面接(めんせつ)の!順番(じゅんばん)が!近(ちか)づいて、どきどきしてきた。',
    '面试顺序临近，我开始紧张得心跳加速。',
    '根据场景判断紧张、期待还是生理心跳。',
  ),
  _OnomatopoeiaEntry(
    'いらいら',
    3,
    '拟情',
    '心情与心理反应',
    '事情不顺而焦躁、烦躁',
    'いらいらする',
    '!電車(でんしゃ)がなかなか!来(こ)なくていらいらした。',
    '电车迟迟不来，让人很烦躁。',
    '常与原因句「～なくて」一起出现。',
  ),
  _OnomatopoeiaEntry(
    'がっかり',
    4,
    '拟情',
    '心情与心理反应',
    '期待落空后失望、泄气',
    'がっかりする',
    '!試合(しあい)が!中止(ちゅうし)になって、みんながっかりした。',
    '比赛取消了，大家都很失望。',
    '先有期待再落空是核心语义。',
  ),
  _OnomatopoeiaEntry(
    'うんざり',
    2,
    '拟情',
    '心情与心理反应',
    '对反复或过量的事情感到厌烦',
    '～にうんざりする',
    '!同(おな)じ!説明(せつめい)を!何度(なんど)も!聞(き)かされてうんざりした。',
    '同样的说明被迫听了很多遍，烦透了。',
    '通常比「!飽(あ)きる」带更强的厌恶。',
  ),
  _OnomatopoeiaEntry(
    'ぞっと',
    2,
    '拟情',
    '心情与心理反应',
    '因恐惧、厌恶或想象而感到寒意',
    'ぞっとする',
    '!事故(じこ)の!話(はなし)を!聞(き)いてぞっとした。',
    '听到事故的事，感到不寒而栗。',
    '不是单纯的冷，而是心理引起的寒意。',
  ),
  _OnomatopoeiaEntry(
    'はらはら',
    3,
    '拟情／拟态',
    '心情与心理反应',
    '担心结果而提心吊胆；也可表示轻物飘落',
    'はらはらする／!落(お)ちる',
    '!子(こ)どもが!高(たか)い!所(ところ)に!登(のぼ)るのを!見(み)てはらはらした。',
    '看孩子爬到高处，让人提心吊胆。',
    '心理意义和花瓣飘落意义需看语境。',
  ),
  _OnomatopoeiaEntry(
    'びくびく',
    2,
    '拟情',
    '心情与心理反应',
    '持续害怕，担心受到责备或伤害',
    'びくびくする／!暮(く)らす',
    '!失敗(しっぱい)がばれないかと!一日中(いちにちじゅう)びくびくしていた。',
    '一整天都害怕失败会不会暴露。',
    '强调恐惧持续存在，而非瞬间受惊。',
  ),
  _OnomatopoeiaEntry(
    'おどおど',
    2,
    '拟容／拟情',
    '心情与心理反应',
    '缺乏自信，神情和举止不安',
    'おどおどする／した!態度(たいど)',
    '!彼(かれ)は!質問(しつもん)されると、おどおど!答(こた)えた。',
    '他一被提问，就忐忑不安地回答。',
    '常从说话方式和动作判断人物心理。',
  ),
  _OnomatopoeiaEntry(
    'しょんぼり',
    3,
    '拟情',
    '心情与心理反应',
    '因失望或被批评而垂头丧气',
    'しょんぼりする',
    '!叱(しか)られた!子(こ)どもがしょんぼりしている。',
    '被训斥的孩子垂头丧气。',
    '常同时呈现表情、姿态和情绪。',
  ),
  _OnomatopoeiaEntry(
    'うっとり',
    2,
    '拟情',
    '心情与心理反应',
    '被美好事物吸引而陶醉',
    '～にうっとりする／!見(み)とれる',
    '!観客(かんきゃく)は!美(うつく)しい!歌声(うたごえ)にうっとりと!聞(き)き!入(い)った。',
    '观众陶醉地聆听美妙歌声。',
    '常与美景、音乐、气味等感官对象搭配。',
  ),
  _OnomatopoeiaEntry(
    'ひしひし',
    1,
    '拟情',
    '心情与心理反应',
    '某种感受迫切而深刻地传来',
    'ひしひしと!感(かん)じる',
    '!家族(かぞく)のありがたさをひしひしと!感(かん)じた。',
    '深切感受到了家人的可贵。',
    '多与「!感(かん)じる、!伝(つた)わる」搭配，语气郑重。',
  ),
  _OnomatopoeiaEntry(
    'つくづく',
    1,
    '拟情',
    '心情与心理反应',
    '经过反复思考而深深感到',
    'つくづく!思(おも)う／!感(かん)じる',
    '!健康(けんこう)の!大切(たいせつ)さをつくづく!感(かん)じた。',
    '深深体会到了健康的重要。',
    '常见于回顾、感叹或反省的语境。',
  ),
  _OnomatopoeiaEntry(
    'やきもき',
    1,
    '拟情',
    '心情与心理反应',
    '因事情不按预期发展而焦急担心',
    'やきもきする',
    '!連絡(れんらく)が!来(こ)ないので、!家族(かぞく)はやきもきしている。',
    '因为一直没有消息，家人焦急不安。',
    '比「いらいら」更突出担心进展和结果。',
  ),
  _OnomatopoeiaEntry(
    'もやもや',
    2,
    '拟情／拟态',
    '心情与心理反应',
    '心里不清爽、有疑问或不满说不明白',
    'もやもやする／した!気持(きも)ち',
    '!理由(りゆう)を!説明(せつめい)してもらえず、!気持(きも)ちがもやもやした。',
    '没有得到理由说明，心里一直不痛快。',
    '也可描述烟雾模糊，常考抽象引申。',
  ),

  _OnomatopoeiaEntry(
    'ずきずき',
    3,
    '拟情',
    '身体感受与睡眠',
    '随脉搏反复跳痛',
    '!頭(あたま)／!歯(は)がずきずき!痛(いた)む',
    '!朝(あさ)から!歯(は)がずきずき!痛(いた)んでいる。',
    '从早上起牙就一跳一跳地疼。',
    '根据疼痛性质选择，常见于就医表达。',
  ),
  _OnomatopoeiaEntry(
    'ちくちく',
    3,
    '拟情／拟态',
    '身体感受与睡眠',
    '针扎般细小而反复的刺痛',
    'ちくちく!痛(いた)む／する',
    'このセーターは!首(くび)のところがちくちくする。',
    '这件毛衣的领口扎得脖子刺刺的。',
    '可表示身体刺痛，也可表示材质扎人。',
  ),
  _OnomatopoeiaEntry(
    'ひりひり',
    3,
    '拟情',
    '身体感受与睡眠',
    '皮肤或黏膜火辣辣地疼',
    'ひりひりする／!痛(いた)む',
    '!日焼(ひや)けした!背中(せなか)がひりひりする。',
    '晒伤的后背火辣辣地疼。',
    '常见于晒伤、擦伤、辛辣刺激。',
  ),
  _OnomatopoeiaEntry(
    'がんがん',
    3,
    '拟情／拟音',
    '身体感受与睡眠',
    '头部强烈连续作痛；也可表示巨响',
    '!頭(あたま)ががんがんする',
    '!寝不足(ねぶそく)で!頭(あたま)ががんがんする。',
    '因为睡眠不足，头疼得厉害。',
    '主语是头时表示强烈头痛。',
  ),
  _OnomatopoeiaEntry(
    'むかむか',
    3,
    '拟情',
    '身体感受与睡眠',
    '恶心想吐；也可因生气而不舒服',
    '!胸(むね)がむかむかする',
    '!油(あぶら)っこい!物(もの)を!食(た)べて、!胸(むね)がむかむかする。',
    '吃了油腻食物后，胃里恶心。',
    '区分身体恶心和心理生气两种意义。',
  ),
  _OnomatopoeiaEntry(
    'くらくら',
    3,
    '拟情',
    '身体感受与睡眠',
    '眩晕，感觉周围旋转',
    '!頭(あたま)がくらくらする',
    '!急(きゅう)に!立(た)ち!上(あ)がったら、!頭(あたま)がくらくらした。',
    '突然站起来时感到头晕目眩。',
    '就医或身体状况听力中的高频描述。',
  ),
  _OnomatopoeiaEntry(
    'ぞくぞく',
    2,
    '拟情',
    '身体感受与睡眠',
    '因寒冷、发烧或恐惧而阵阵发冷',
    '!寒気(さむけ)がしてぞくぞくする',
    '!熱(ねつ)が!出(で)たのか、!背中(せなか)がぞくぞくする。',
    '可能发烧了，背后一阵阵发冷。',
    '也能表示兴奋，需根据身体或心理语境判断。',
  ),
  _OnomatopoeiaEntry(
    'ぐったり',
    3,
    '拟容',
    '身体感受与睡眠',
    '精疲力竭，身体完全没力气',
    'ぐったりする／!横(よこ)になる',
    '!暑(あつ)さで!犬(いぬ)がぐったりしている。',
    '狗热得无精打采。',
    '比普通「!疲(つか)れる」更强调全身无力。',
  ),
  _OnomatopoeiaEntry(
    'へとへと',
    3,
    '拟情',
    '身体感受与睡眠',
    '疲惫到几乎没有剩余体力',
    'へとへとになる',
    '!一日中(いちにちじゅう)!歩(ある)いてへとへとになった。',
    '走了一整天，累得筋疲力尽。',
    '常用「～てへとへとになる」说明原因。',
  ),
  _OnomatopoeiaEntry(
    'げっそり',
    2,
    '拟容',
    '身体感受与睡眠',
    '因病、疲劳等明显消瘦憔悴',
    'げっそりする／!痩(や)せる',
    '!入院生活(にゅういんせいかつ)で!彼(かれ)はげっそり!痩(や)せてしまった。',
    '住院期间他消瘦憔悴了许多。',
    '关注外观变化背后的身体原因。',
  ),
  _OnomatopoeiaEntry(
    'ぐっすり',
    4,
    '拟态',
    '身体感受与睡眠',
    '睡得很沉、很熟',
    'ぐっすり!眠(ねむ)る／!寝(ね)る',
    '!昨日(きのう)は!疲(つか)れていたので、ぐっすり!眠(ねむ)れた。',
    '昨天很累，所以睡得很香。',
    '固定搭配「ぐっすり!眠(ねむ)る」。',
  ),
  _OnomatopoeiaEntry(
    'うとうと',
    3,
    '拟态',
    '身体感受与睡眠',
    '半睡半醒地打瞌睡',
    'うとうとする',
    '!暖(あたた)かい!電車(でんしゃ)の!中(なか)でうとうとしてしまった。',
    '在温暖的电车里不知不觉打起了瞌睡。',
    '与深睡的「ぐっすり」对比。',
  ),
  _OnomatopoeiaEntry(
    'すやすや',
    4,
    '拟态',
    '身体感受与睡眠',
    '安静、舒适地熟睡',
    'すやすや!眠(ねむ)る',
    '!赤(あか)ちゃんがベッドですやすや!眠(ねむ)っている。',
    '婴儿正在床上安稳地睡着。',
    '常用于婴儿或安稳睡眠，语感温和。',
  ),
  _OnomatopoeiaEntry(
    'ぺこぺこ',
    4,
    '拟情／拟容',
    '身体感受与睡眠',
    '肚子非常饿；也可表示不断低头赔礼',
    'おなかがぺこぺこだ',
    '!朝(あさ)から!何(なに)も!食(た)べていないので、おなかがぺこぺこだ。',
    '从早上起什么也没吃，肚子饿极了。',
    '根据「おなか」或人物动作判断意义。',
  ),
  _OnomatopoeiaEntry(
    'ぼろぼろ',
    3,
    '拟态／拟容',
    '身体感受与睡眠',
    '身体、物品或精神状态破损不堪',
    'ぼろぼろになる',
    '!連日(れんじつ)の!残業(ざんぎょう)で!心(こころ)も!体(からだ)もぼろぼろだ。',
    '连续加班让身心都疲惫不堪。',
    '可从物理破损引申到身心状态。',
  ),

  _OnomatopoeiaEntry(
    'すらすら',
    4,
    '拟态',
    '说话、学习与做事方式',
    '说、读、写等顺畅，没有停顿',
    'すらすら!話(はな)す／!読(よ)む／!書(か)く',
    '!彼女(かのじょ)は!難(むずか)しい!文章(ぶんしょう)もすらすら!読(よ)める。',
    '她连难文章也能流畅地读。',
    '关注过程顺畅，不一定表示语言能力全面。',
  ),
  _OnomatopoeiaEntry(
    'ぺらぺら',
    4,
    '拟态',
    '说话、学习与做事方式',
    '外语说得流利；也可表示纸张单薄',
    '!外国語(がいこくご)がぺらぺらだ',
    '!兄(あに)は!中国語(ちゅうごくご)がぺらぺらだ。',
    '哥哥汉语说得很流利。',
    '根据名词区分语言流利和物体单薄。',
  ),
  _OnomatopoeiaEntry(
    'はきはき',
    3,
    '拟态',
    '说话、学习与做事方式',
    '说话清楚有精神，回答爽快',
    'はきはき!話(はな)す／!答(こた)える',
    '!面接(めんせつ)では!質問(しつもん)にはきはき!答(こた)えた。',
    '面试时清楚有力地回答了问题。',
    '不仅是发音清楚，还包含积极利落的态度。',
  ),
  _OnomatopoeiaEntry(
    'ぼそぼそ',
    3,
    '拟声／拟态',
    '说话、学习与做事方式',
    '声音小而含糊地说话',
    'ぼそぼそ!話(はな)す／つぶやく',
    '!彼(かれ)は!下(した)を!向(む)いてぼそぼそ!答(こた)えた。',
    '他低着头小声含糊地回答。',
    '常与不自信、消极态度联系。',
  ),
  _OnomatopoeiaEntry(
    'もごもご',
    2,
    '拟态',
    '说话、学习与做事方式',
    '嘴里含糊，说不清楚',
    'もごもご!言(い)う／!話(はな)す',
    '!言(い)いたいことがあるなら、もごもごしないではっきり!言(い)って。',
    '有话就别含含糊糊，清楚说出来。',
    '与「はっきり」形成表达方式对比。',
  ),
  _OnomatopoeiaEntry(
    'くどくど',
    2,
    '拟态',
    '说话、学习与做事方式',
    '同一内容反复冗长地说',
    'くどくど!言(い)う／!説明(せつめい)する',
    '!終(お)わったことをくどくど!言(い)わないでください。',
    '请不要对已经结束的事翻来覆去地说。',
    '含厌烦和负面评价。',
  ),
  _OnomatopoeiaEntry(
    'きっぱり',
    2,
    '拟态',
    '说话、学习与做事方式',
    '态度明确坚定，不留含糊余地',
    'きっぱり!断(ことわ)る／!言(い)う',
    '!無理(むり)な!依頼(いらい)をきっぱり!断(ことわ)った。',
    '明确拒绝了不合理的请求。',
    '常考与「!断(ことわ)る、!否定(ひてい)する」等动词搭配。',
  ),
  _OnomatopoeiaEntry(
    'しっかり',
    4,
    '拟态',
    '说话、学习与做事方式',
    '牢固可靠；认真充分地做某事',
    'しっかりする／!確認(かくにん)する',
    '!出発前(しゅっぱつまえ)に!持(も)ち!物(もの)をしっかり!確認(かくにん)してください。',
    '出发前请认真确认随身物品。',
    '意义广，需从人、物或行为判断。',
  ),
  _OnomatopoeiaEntry(
    'うっかり',
    4,
    '拟态',
    '说话、学习与做事方式',
    '因一时疏忽而无意做错或忘记',
    'うっかりする／!忘(わす)れる',
    'うっかり!電車(でんしゃ)の!中(なか)に!傘(かさ)を!忘(わす)れた。',
    '一不小心把伞忘在电车里了。',
    '常与非故意的失误、忘记搭配。',
  ),
  _OnomatopoeiaEntry(
    'こっそり',
    3,
    '拟态',
    '说话、学习与做事方式',
    '不让别人发现，悄悄地行动',
    'こっそり!見(み)る／!出(で)る',
    '!弟(おとうと)は!夜中(よなか)にこっそり!台所(だいどころ)へ!行(い)った。',
    '弟弟半夜悄悄去了厨房。',
    '动作隐秘是核心，未必包含恶意。',
  ),
  _OnomatopoeiaEntry(
    'じっくり',
    3,
    '拟态',
    '说话、学习与做事方式',
    '花足够时间认真、深入地进行',
    'じっくり!考(かんが)える／!煮(に)る',
    '!大切(たいせつ)な!問題(もんだい)なので、じっくり!考(かんが)えたい。',
    '因为是重要问题，我想认真慢慢考虑。',
    '强调时间充分和处理深入。',
  ),
  _OnomatopoeiaEntry(
    'てきぱき',
    3,
    '拟态',
    '说话、学习与做事方式',
    '动作有条理又迅速，效率高',
    'てきぱき!働(はたら)く／!指示(しじ)する',
    '!店員(てんいん)は!注文(ちゅうもん)を!聞(き)くと、てきぱき!動(うご)いた。',
    '店员听完点单后麻利地行动起来。',
    '通常是对工作方式的正面评价。',
  ),
  _OnomatopoeiaEntry(
    'しぶしぶ',
    1,
    '拟情／拟容',
    '说话、学习与做事方式',
    '虽然不情愿，仍勉强去做',
    'しぶしぶ!承知(しょうち)する／!従(したが)う',
    '!何度(なんど)も!頼(たの)まれて、!彼(かれ)はしぶしぶ!引(ひ)き!受(う)けた。',
    '被请求多次后，他勉强答应了。',
    '句中常有外部压力和不情愿的对比。',
  ),
  _OnomatopoeiaEntry(
    'うかうか',
    1,
    '拟情',
    '说话、学习与做事方式',
    '漫不经心、放松警惕',
    'うかうかする／していられない',
    '!競争(きょうそう)が!激(はげ)しくて、うかうかしていられない。',
    '竞争激烈，不能掉以轻心。',
    '常见固定形式「うかうかしていられない」。',
  ),
  _OnomatopoeiaEntry(
    'しどろもどろ',
    1,
    '拟容',
    '说话、学习与做事方式',
    '慌乱得前言不搭后语',
    'しどろもどろになる／!答(こた)える',
    '!突然(とつぜん)!問(と)い!詰(つ)められ、!彼(かれ)はしどろもどろになった。',
    '突然被追问，他回答得语无伦次。',
    '从回答混乱推断紧张或心虚。',
  ),
];

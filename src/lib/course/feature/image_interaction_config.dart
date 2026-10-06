import 'dart:convert';

class CourseImageBounds {
  const CourseImageBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x, y, width, height;

  factory CourseImageBounds.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('图片热点 bounds 必须是对象');
    double number(String key) {
      final item = value[key];
      if (item is! num || !item.isFinite)
        throw FormatException('图片热点 bounds.$key 必须是数字');
      return item.toDouble();
    }

    final bounds = CourseImageBounds(
      x: number('x'),
      y: number('y'),
      width: number('width'),
      height: number('height'),
    );
    if (bounds.x < 0 ||
        bounds.y < 0 ||
        bounds.width <= 0 ||
        bounds.height <= 0 ||
        bounds.x + bounds.width > 1 ||
        bounds.y + bounds.height > 1) {
      throw const FormatException('图片热点范围必须位于 0～1 画布内');
    }
    return bounds;
  }
}

class CourseImageHotspot {
  const CourseImageHotspot({
    required this.id,
    required this.label,
    required this.semanticLabel,
    required this.audioSource,
    required this.color,
    required this.bounds,
  });

  final String id, label, semanticLabel, audioSource, color;
  final CourseImageBounds bounds;

  factory CourseImageHotspot.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('图片热点必须是对象');
    String requiredText(String key, {int maximum = 100}) {
      final text = value[key]?.toString().trim() ?? '';
      if (text.isEmpty || text.length > maximum)
        throw FormatException('图片热点 $key 无效');
      return text;
    }

    final id = requiredText('id', maximum: 64);
    if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(id))
      throw const FormatException('图片热点 id 格式无效');
    final audioSource = requiredText('audio_src', maximum: 255);
    if (audioSource.contains('/') ||
        audioSource.contains('\\') ||
        audioSource.startsWith('.') ||
        !audioSource.toLowerCase().endsWith('.mp3')) {
      throw const FormatException('图片热点音频文件名无效');
    }
    final color = value['color']?.toString().trim() ?? '#3B82F6';
    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color))
      throw const FormatException('图片热点颜色无效');
    return CourseImageHotspot(
      id: id,
      label: requiredText('label'),
      semanticLabel:
          value['semantic_label']?.toString().trim().isNotEmpty == true
        ? value['semantic_label'].toString().trim()
        : requiredText('label'),
      audioSource: audioSource,
      color: color,
      bounds: CourseImageBounds.fromJson(value['bounds']),
    );
  }
}

class CourseImageInteractionConfig {
  const CourseImageInteractionConfig({required this.hotspots});

  final List<CourseImageHotspot> hotspots;

  static CourseImageInteractionConfig? parse(String source) {
    if (source.trim().isEmpty) return null;
    final value = jsonDecode(source);
    if (value is! Map) throw const FormatException('图片互动配置必须是对象');
    if (value['version'] != 1) throw const FormatException('图片互动配置版本不受支持');
    if (value['interactive'] != true) return null;
    final items = value['hotspots'];
    if (items is! List || items.isEmpty || items.length > 20) {
      throw const FormatException('图片热点数量必须为 1～20 个');
    }
    final hotspots = items
        .map(CourseImageHotspot.fromJson)
        .toList(growable: false);
    if (hotspots.map((item) => item.id).toSet().length != hotspots.length) {
      throw const FormatException('图片热点 id 不能重复');
    }
    return CourseImageInteractionConfig(hotspots: hotspots);
  }

  /// Parses optional interaction data without discarding an otherwise usable
  /// image. Invalid hotspots are isolated; an invalid top-level object falls
  /// back to a normal image.
  static CourseImageInteractionParseResult parseTolerant(String source) {
    final issues = <String>[];
    if (source.trim().isEmpty) {
      return const CourseImageInteractionParseResult(null, ['互动图片缺少配置']);
    }
    Object? value;
    try {
      value = jsonDecode(source);
    } on Object catch (error) {
      return CourseImageInteractionParseResult(null, [
        '互动图片配置不是有效 JSON：$error',
      ]);
    }
    if (value is! Map) {
      return const CourseImageInteractionParseResult(null, ['图片互动配置必须是对象']);
    }
    if (value['version'] != 1) {
      return const CourseImageInteractionParseResult(null, ['图片互动配置版本不受支持']);
    }
    if (value['interactive'] != true) {
      return const CourseImageInteractionParseResult(null, ['图片未启用互动配置']);
    }
    final items = value['hotspots'];
    if (items is! List || items.isEmpty || items.length > 20) {
      return const CourseImageInteractionParseResult(null, [
        '图片热点数量必须为 1～20 个',
      ]);
    }
    final hotspots = <CourseImageHotspot>[];
    final ids = <String>{};
    for (var index = 0; index < items.length; index++) {
      try {
        final hotspot = CourseImageHotspot.fromJson(items[index]);
        if (!ids.add(hotspot.id)) {
          issues.add('热点 ${index + 1} id 重复，已禁用');
          continue;
        }
        hotspots.add(hotspot);
      } on Object catch (error) {
        issues.add('热点 ${index + 1} 无效，已禁用：$error');
      }
    }
    if (hotspots.isEmpty) {
      issues.add('没有可用热点，已回退为普通图片');
      return CourseImageInteractionParseResult(null, issues);
    }
    return CourseImageInteractionParseResult(
      CourseImageInteractionConfig(hotspots: List.unmodifiable(hotspots)),
      List.unmodifiable(issues),
    );
  }
}

class CourseImageInteractionParseResult {
  const CourseImageInteractionParseResult(this.config, this.issues);
  final CourseImageInteractionConfig? config;
  final List<String> issues;
}

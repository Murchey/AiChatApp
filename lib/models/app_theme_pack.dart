import 'package:flutter/painting.dart';

String themeResourcePath(dynamic value) {
  if (value is! String ||
      value.isEmpty ||
      value.contains('\\') ||
      value.contains(':') ||
      value.startsWith('/') ||
      value.split('/').any((p) => p.isEmpty || p == '.' || p == '..')) {
    throw const FormatException('主题资源必须使用包内相对路径');
  }
  return value;
}

class ThemeImageAsset {
  final String file;
  final int width, height;
  const ThemeImageAsset(this.file, this.width, this.height);
  factory ThemeImageAsset.parse(Map map, [String key = 'file']) {
    final w = map['width'], h = map['height'];
    if (w is! int ||
        h is! int ||
        w < 1 ||
        h < 1 ||
        w > 8192 ||
        h > 8192 ||
        w * h > 16777216) {
      throw const FormatException('主题图片尺寸无效（最多 1600 万像素）');
    }
    return ThemeImageAsset(themeResourcePath(map[key]), w, h);
  }
}

class AppThemePack {
  final Map<String, dynamic> manifest;
  final String directory;
  final String id, name;
  final Map<String, (ThemeImageAsset, ThemeImageAsset)> navigation;
  final Map<String, ThemeImageAsset> headers;
  final ThemeImageAsset? bubble;
  ThemeImageAsset? bubbleLeading;
  double bubbleLeadingSize = 40;
  double bubbleLeadingGap = 8;
  final EdgeInsets stretchInsets;
  final Color textColor;
  final String? font, preview;
  AppThemePack._(
      this.manifest,
      this.directory,
      this.id,
      this.name,
      this.navigation,
      this.headers,
      this.bubble,
      this.stretchInsets,
      this.textColor,
      this.font,
      this.preview);
  String path(String relative) => '$directory/$relative';
  double navigationSize(String slot, double fallback) =>
      ((manifest['navigation'] as Map?)?[slot]?['size'] as num?)?.toDouble() ??
      fallback;
  String? loadedFontFamily;
  String get fontFamily => loadedFontFamily ?? 'AppTheme_$id';
  factory AppThemePack.parse(Map<String, dynamic> map, String directory) {
    final id = map['id'];
    final name = map['name'];
    if (id is! String ||
        !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$').hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty) {
      throw const FormatException('主题 id 或 name 无效');
    }
    final nav = <String, (ThemeImageAsset, ThemeImageAsset)>{};
    for (final e in (map['navigation'] as Map? ?? {}).entries) {
      if (!['chat', 'contacts', 'discover', 'profile'].contains(e.key)) {
        throw const FormatException('未知导航槽位');
      }
      final size = (e.value as Map)['size'];
      if (size != null &&
          (size is! num || !size.isFinite || size < 16 || size > 36)) {
        throw const FormatException('导航图片 size 应为 16–36 个逻辑像素');
      }
      nav[e.key as String] = (
        ThemeImageAsset.parse(e.value as Map, 'normal'),
        ThemeImageAsset.parse(e.value as Map, 'selected')
      );
    }
    final headers = <String, ThemeImageAsset>{};
    for (final e in (map['headers'] as Map? ?? {}).entries) {
      if (!['home', 'contacts'].contains(e.key)) {
        throw const FormatException('未知 header 槽位');
      }
      headers[e.key as String] = ThemeImageAsset.parse(e.value as Map);
    }
    final b = map['selfBubble'] as Map?;
    final bubble = b == null ? null : ThemeImageAsset.parse(b);
    var insets = EdgeInsets.zero;
    var color = const Color(0xFF202124);
    if (b != null) {
      final m = b['stretchInsets'] as Map;
      double edge(String key) {
        final n = m[key];
        if (n is! num || !n.isFinite || n < 0) {
          throw const FormatException('九宫格边距无效');
        }
        return n.toDouble();
      }

      insets = EdgeInsets.fromLTRB(
          edge('left'), edge('top'), edge('right'), edge('bottom'));
      if (insets.horizontal >= bubble!.width ||
          insets.vertical >= bubble.height) {
        throw const FormatException('九宫格中心区域不能为空');
      }
      final value = b['textColor'];
      if (value is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
        throw const FormatException('textColor 应为 #RRGGBB');
      }
      color = Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
    }
    final f = map['selfFont'] as Map?;
    final font = f == null ? null : themeResourcePath(f['file']);
    if (font != null && !font.toLowerCase().endsWith('.ttf')) {
      throw const FormatException('主题字体仅支持 TTF');
    }
    if (nav.isEmpty && headers.isEmpty && bubble == null && font == null) {
      throw const FormatException('主题至少需要一项可应用资源');
    }
    final pack = AppThemePack._(
        map,
        directory,
        id,
        name,
        nav,
        headers,
        bubble,
        insets,
        color,
        font,
        map['preview'] == null ? null : themeResourcePath(map['preview']));
    final leading = b?['leading'];
    if (leading != null) {
      if (leading is! Map) throw const FormatException('气泡左侧图片格式无效');
      pack.bubbleLeading = ThemeImageAsset.parse(leading);
      final size = leading['size'] ?? 40;
      final gap = leading['gap'] ?? 8;
      if (size is! num ||
          !size.isFinite ||
          size < 16 ||
          size > 96 ||
          gap is! num ||
          !gap.isFinite ||
          gap < 0 ||
          gap > 24) {
        throw const FormatException('气泡左侧图片 size 应为 16–96，gap 应为 0–24');
      }
      pack.bubbleLeadingSize = size.toDouble();
      pack.bubbleLeadingGap = gap.toDouble();
    }
    return pack;
  }
  Iterable<ThemeImageAsset> get images sync* {
    for (final pair in navigation.values) {
      yield pair.$1;
      yield pair.$2;
    }
    yield* headers.values;
    if (bubble != null) yield bubble!;
    if (bubbleLeading != null) yield bubbleLeading!;
  }
}

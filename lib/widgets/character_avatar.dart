import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/settings_provider.dart';

/// base64 头像解码缓存：同一个 base64 只解码一次，并复用同一个 [MemoryImage]。
/// 若每次 build 都新建 [MemoryImage]，图片缓存键会随之改变（Dart 的 List ==
/// 是引用比较），导致解码缓存失效、内存膨胀。
final Map<String, MemoryImage> _avatarImageCache = {};

MemoryImage _cachedAvatarImage(String base64) {
  return _avatarImageCache.putIfAbsent(
    base64,
    () {
      if (_avatarImageCache.length > 64) _avatarImageCache.clear();
      return MemoryImage(base64Decode(base64));
    },
  );
}

/// 角色头像：根据全局设置「角色头像框样式」渲染方形（默认，保留调用方圆角）
/// 或仿 QQ 圆形。未设置头像时显示占位图标。
class CharacterAvatar extends StatelessWidget {
  /// 头像 base64（空字符串表示未设置，显示占位图标）
  final String base64;

  /// 头像边长
  final double size;

  /// 未设置头像时的占位图标
  final IconData fallbackIcon;

  /// 占位图标大小
  final double? iconSize;

  /// 占位图标颜色
  final Color? iconColor;

  /// 方形模式下的圆角（默认 size*0.16）
  final BorderRadius? borderRadius;

  /// 未设置头像时的背景色（默认主题强调色半透明）
  final Color? backgroundColor;

  /// 额外描边（如角色空间页的白色描边）
  final Border? border;

  const CharacterAvatar({
    super.key,
    required this.base64,
    required this.size,
    this.fallbackIcon = CupertinoIcons.person_fill,
    this.iconSize,
    this.iconColor,
    this.borderRadius,
    this.backgroundColor,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final isCircle =
        context.watch<SettingsProvider>().avatarFrameStyle ==
        AvatarFrameStyle.circle;
    final hasImage = base64.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle
            ? null
            : (borderRadius ?? BorderRadius.circular(size * 0.16)),
        color: hasImage
            ? null
            : backgroundColor ??
                  context.accentColor.withValues(alpha: 0.15),
        border: border,
        image: hasImage
            ? DecorationImage(
                image: _cachedAvatarImage(base64),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: hasImage
          ? null
          : Icon(
              fallbackIcon,
              size: iconSize ?? size * 0.55,
              color: iconColor ?? context.accentColor,
            ),
    );
  }
}

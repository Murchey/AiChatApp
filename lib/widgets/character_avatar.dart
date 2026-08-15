import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/settings_provider.dart';

/// base64 头像字节缓存：同一个 base64 只解码一次并复用同一个 [Uint8List]，
/// Flutter 对相同字节引用的 [Image.memory] 会复用 codec，避免 GIF 反复解码。
/// 缓存条数有上限，超出时按插入顺序淘汰最旧的条目，防止内存无限增长。
final Map<String, Uint8List> _avatarBytesCache = {};
int _avatarBytesCacheSize = 0;
const int _maxAvatarBytesCache = 128;

void _evictOldestAvatarBytes() {
  if (_avatarBytesCache.isEmpty) return;
  final oldestKey = _avatarBytesCache.keys.first;
  _avatarBytesCache.remove(oldestKey);
  _avatarBytesCacheSize--;
}

Uint8List _cachedAvatarBytes(String base64) {
  var bytes = _avatarBytesCache[base64];
  if (bytes == null) {
    while (_avatarBytesCacheSize >= _maxAvatarBytesCache) {
      _evictOldestAvatarBytes();
    }
    bytes = base64Decode(base64);
    _avatarBytesCache[base64] = bytes;
    _avatarBytesCacheSize++;
  }
  return bytes;
}

/// 角色头像：根据全局设置「角色头像框样式」渲染方形（默认，保留调用方圆角）
/// 或仿 QQ 圆形。未设置头像时显示占位图标。支持 GIF 动画自动播放。
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
    final radius = isCircle ? null : (borderRadius ?? BorderRadius.circular(size * 0.16));
    
    // 裁剪器：圆形用 ClipOval，方形用 ClipRRect（统一为 Widget 函数签名，避免
    // ClipOval.new 这种无参构造 tear-off 与闭包类型不一致导致运行时类型错误）
    final Widget Function(Widget) clipper = isCircle
        ? (child) => ClipOval(child: child)
        : (child) => ClipRRect(borderRadius: radius!, child: child);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : radius,
        color: hasImage
            ? null
            : backgroundColor ??
                  context.accentColor.withValues(alpha: 0.15),
        border: border,
      ),
      alignment: Alignment.center,
      child: hasImage
          ? clipper(
              // 使用 _cachedAvatarBytes 复用已解码字节，使 Flutter codec 命中缓存、GIF 不重复解码
              Image.memory(
                _cachedAvatarBytes(base64),
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: size.toInt() * 2,
                cacheHeight: size.toInt() * 2,
              ),
            )
          : Icon(
              fallbackIcon,
              size: iconSize ?? size * 0.55,
              color: iconColor ?? context.accentColor,
            ),
    );
  }
}

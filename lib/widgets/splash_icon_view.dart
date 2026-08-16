import 'dart:io';
import 'package:flutter/cupertino.dart';
import '../config/theme.dart';

/// 开屏内容视图：设置了自定义开屏图标时铺满展示导入的图片，
/// 否则展示默认的 Logo 与名称。
class SplashIconView extends StatelessWidget {
  /// 自定义开屏图标本地路径（空字符串 = 使用默认内容）
  final String imagePath;

  const SplashIconView({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    final path = imagePath.trim();
    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(
        File(path),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        // 图片损坏等异常情况回退到默认内容
        errorBuilder: (_, __, ___) => _defaultContent(context),
      );
    }
    return _defaultContent(context);
  }

  /// 默认开屏内容：圆角 Logo + 应用名
  Widget _defaultContent(BuildContext context) {
    final dark = context.isDark;
    return ColoredBox(
      color: dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: dark ? CupertinoColors.white : context.accentColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: CupertinoColors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Icon(
                CupertinoIcons.chat_bubble_2_fill,
                size: 56,
                color: dark ? context.accentColor : CupertinoColors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'AiChat',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color:
                    dark ? CupertinoColors.white : const Color(0xFF000000),
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

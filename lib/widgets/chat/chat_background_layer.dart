import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';

/// 聊天页背景图层（持久化图片 + 高斯模糊）
class ChatBackgroundLayer extends StatelessWidget {
  final String imagePath;
  final double blur;

  const ChatBackgroundLayer({
    super.key,
    required this.imagePath,
    required this.blur,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Builder(
        builder: (ctx) {
          final bgSize = MediaQuery.of(ctx).size;
          final b = blur > 0 ? blur : 0.1;
          final decodeWidth =
              (bgSize.width * MediaQuery.devicePixelRatioOf(ctx)).ceil();
          return ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: b, sigmaY: b),
            child: Image.file(
              File(imagePath),
              fit: BoxFit.cover,
              width: bgSize.width,
              height: bgSize.height,
              cacheWidth: decodeWidth,
            ),
          );
        },
      ),
    );
  }
}

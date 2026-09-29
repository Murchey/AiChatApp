import 'dart:io';

import 'package:flutter/cupertino.dart';

class StickerPreviewDialog extends StatelessWidget {
  final String imagePath;
  final String? label;

  const StickerPreviewDialog({required this.imagePath, this.label});

  @override
  Widget build(BuildContext context) => CupertinoPopupSurface(
        isSurfacePainted: false,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            color: CupertinoColors.black.withValues(alpha: 0.88),
            padding: const EdgeInsets.all(20),
            child: SafeArea(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  InteractiveViewer(
                    child: Image.file(File(imagePath), fit: BoxFit.contain),
                  ),
                  if (label?.trim().isNotEmpty == true)
                    Positioned(
                      bottom: 12,
                      child: Text(label!,
                          style: const TextStyle(color: CupertinoColors.white)),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

import 'dart:convert';

import 'package:flutter/cupertino.dart';


class AvatarPreviewScreen extends StatefulWidget {
  final String base64;

  const AvatarPreviewScreen({required this.base64});

  @override
  State<AvatarPreviewScreen> createState() => AvatarPreviewScreenState();
}

class AvatarPreviewScreenState extends State<AvatarPreviewScreen> {
  final TransformationController _transform = TransformationController();
  Offset _doubleTapPos = Offset.zero;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// 双击：放大 2.5 倍（以点击处为中心），再次双击复位
  void _toggleZoom() {
    if (_transform.value.getMaxScaleOnAxis() > 1.05) {
      _transform.value = Matrix4.identity();
    } else {
      final p = _doubleTapPos;
      _transform.value = Matrix4.identity()
        ..translateByDouble(p.dx, p.dy, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1)
        ..translateByDouble(-p.dx, -p.dy, 0, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.of(context).size;
    return ColoredBox(
      color: CupertinoColors.black,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        onDoubleTapDown: (details) => _doubleTapPos = details.localPosition,
        onDoubleTap: _toggleZoom,
        child: InteractiveViewer(
          transformationController: _transform,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(200),
          minScale: 1,
          maxScale: 6,
          child: SizedBox(
            width: viewport.width,
            height: viewport.height,
            child: Center(
              child: Image.memory(
                base64Decode(widget.base64),
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

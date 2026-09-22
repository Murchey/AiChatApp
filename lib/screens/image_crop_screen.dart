import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../config/theme.dart';
import '../utils/app_toast.dart';

/// 图片缩放裁剪编辑页：图片以铺满方式展示在当前屏幕范围的取景区内，
/// 支持双指缩放与拖动调整取景，点「完成」后按所见即所得导出 JPEG。
///
/// - 默认（全屏）：开屏页 / 聊天背景等全屏铺满场景
/// - [squareCrop]：居中方形取景，用于角色/个人头像
///
/// 缩放/拖动使用自定义手势实现。导出文件写入系统临时目录，
/// 由调用方在使用完毕后删除。
class ImageCropScreen extends StatefulWidget {
  /// 待裁剪的源图片本地路径
  final String imagePath;

  /// 头像模式：居中方形取景并导出方形 JPEG
  final bool squareCrop;

  /// 导出图片最大边（头像模式默认 500）
  final int? maxOutputSide;

  final String title;

  const ImageCropScreen({
    super.key,
    required this.imagePath,
    this.squareCrop = false,
    this.maxOutputSide,
    this.title = '调整图片',
  });

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _saving = false;
  bool _loadFailed = false;

  // 源图尺寸（仅解码头部，不加载像素）
  int _imgW = 0;
  int _imgH = 0;
  bool _infoLoaded = false;

  // 取景变换：_offset 为缩放后子图左上角在视口内的位置
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  bool _inited = false;
  double _fitW = 0;
  double _fitH = 0;

  // 手势起始状态
  double _gestureScaleStart = 1.0;
  Offset _gestureOffsetStart = Offset.zero;
  Offset _focalStart = Offset.zero;

  static const double _minScale = 0.3;
  static const double _maxScale = 5.0;

  @override
  void initState() {
    super.initState();
    _loadImageInfo();
  }

  Future<void> _loadImageInfo() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width;
      final h = descriptor.height;
      descriptor.dispose();
      buffer.dispose();
      if (!mounted) return;
      setState(() {
        _imgW = w;
        _imgH = h;
        _infoLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureScaleStart = _scale;
    _gestureOffsetStart = _offset;
    _focalStart = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size viewport) {
    final newScale =
        (_gestureScaleStart * details.scale).clamp(_minScale, _maxScale);
    // 保持手指下的场景点在缩放前后位置不变
    final focalScene = (_focalStart - _gestureOffsetStart) / _gestureScaleStart;
    var newOffset = details.localFocalPoint - focalScene * newScale;
    final childW = _fitW * newScale;
    final childH = _fitH * newScale;
    newOffset = _clampOffset(
      newOffset,
      childW: childW,
      childH: childH,
      viewport: viewport,
    );
    setState(() {
      _scale = newScale;
      _offset = newOffset;
    });
  }

  /// 拖动范围：100% 等比缩放时也保留约 25% 视口的自由度，
  /// 便于把主体挪进取景框（头像方形 / 全屏取景通用）。
  Offset _clampOffset(
    Offset raw, {
    required double childW,
    required double childH,
    required Size viewport,
  }) {
    double clampAxis(double value, double child, double extent) {
      // 经典：图 ≥ 视口时贴边，不露出大片空白
      final tightMin = math.min(extent - child, 0.0);
      final tightMax = math.max(extent - child, 0.0);
      // 额外余量：图刚好铺满某一边时也能左右/上下挪动
      final slack = extent * 0.25;
      return value.clamp(tightMin - slack, tightMax + slack);
    }

    return Offset(
      clampAxis(raw.dx, childW, viewport.width),
      clampAxis(raw.dy, childH, viewport.height),
    );
  }

  Future<void> _confirm() async {
    if (_saving || _loadFailed || !_infoLoaded) return;
    setState(() => _saving = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('渲染节点不存在');
      // 确保导出帧已绘制完成（含最后一次缩放/拖动）
      await WidgetsBinding.instance.endOfFrame;
      const pixelRatio = 3.0;
      final captured = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData =
          await captured.toByteData(format: ui.ImageByteFormat.png);
      captured.dispose();
      final png = byteData?.buffer.asUint8List();
      if (png == null) throw Exception('图像编码失败');
      var decoded = img.decodeImage(png);
      if (decoded == null) throw Exception('图像解析失败');

      // 头像模式：仅导出居中方形区域
      if (widget.squareCrop) {
        final size = boundary.size;
        final side = math.min(size.width, size.height);
        final cropX = ((size.width - side) / 2 * pixelRatio).round();
        final cropY = ((size.height - side) / 2 * pixelRatio).round();
        final cropSide = (side * pixelRatio).round();
        decoded = img.copyCrop(
          decoded,
          x: cropX.clamp(0, decoded.width - 1),
          y: cropY.clamp(0, decoded.height - 1),
          width: cropSide.clamp(1, decoded.width - cropX),
          height: cropSide.clamp(1, decoded.height - cropY),
        );
        final maxSide = widget.maxOutputSide ?? 500;
        if (decoded.width > maxSide || decoded.height > maxSide) {
          decoded = img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? maxSide : null,
            height: decoded.height > decoded.width ? maxSide : null,
          );
        }
      }

      final jpg = img.encodeJpg(decoded, quality: 90);
      final dir = await getTemporaryDirectory();
      final out = File(
        '${dir.path}/crop_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await out.writeAsBytes(jpg);
      if (!mounted) return;
      Navigator.pop(context, out.path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast('裁剪失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 缩小后露出的空白区域按当前深浅色模式补色
    final bg = context.isDark ? CupertinoColors.black : CupertinoColors.white;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.title),
        trailing: _saving
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: CupertinoActivityIndicator(),
              )
            : CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                onPressed: (_loadFailed || !_infoLoaded) ? null : _confirm,
                child: Text(
                  '完成',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: (_loadFailed || !_infoLoaded)
                        ? context.textSecondaryColor
                        : context.accentColor,
                  ),
                ),
              ),
      ),
      child: Column(
        children: [
          // 取景区：图片铺满，双指缩放/拖动
          Expanded(
            child: Container(
              color: bg,
              child: RepaintBoundary(
                key: _boundaryKey,
                child: SizedBox.expand(child: _buildStage(bg)),
              ),
            ),
          ),
          // 操作提示栏
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: context.navBarColor,
            child: Text(
              widget.squareCrop
                  ? '双指缩放、拖动调整取景；点「完成」后应用方形头像'
                  : '双指缩放、拖动调整取景，完成后将按此画面展示',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStage(Color bg) {
    if (_loadFailed) {
      return const Center(
        child: Text(
          '无法加载该图片',
          style: TextStyle(color: CupertinoColors.white),
        ),
      );
    }
    if (!_infoLoaded || _imgW == 0 || _imgH == 0) {
      return const Center(child: CupertinoActivityIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        // 初始 1.0 倍：整图按 contain 铺入视口并居中
        final fitScale =
            math.min(viewport.width / _imgW, viewport.height / _imgH);
        _fitW = _imgW * fitScale;
        _fitH = _imgH * fitScale;
        if (!_inited) {
          _inited = true;
          _scale = 1.0;
          _offset = Offset(
            (viewport.width - _fitW) / 2,
            (viewport.height - _fitH) / 2,
          );
        }
        final side = math.min(viewport.width, viewport.height);
        final maskX = (viewport.width - side) / 2;
        final maskY = (viewport.height - side) / 2;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: _onScaleStart,
          onScaleUpdate: (d) => _onScaleUpdate(d, viewport),
          child: Stack(
            children: [
              ClipRect(
                child: Stack(
                  children: [
                    // 主题色补底
                    Positioned.fill(child: ColoredBox(color: bg)),
                    // 当前取景变换下的图片
                    Positioned(
                      left: _offset.dx,
                      top: _offset.dy,
                      width: _fitW * _scale,
                      height: _fitH * _scale,
                      child: Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.fill,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.squareCrop)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _SquareCropMaskPainter(
                        rect: Rect.fromLTWH(maskX, maskY, side, side),
                        maskColor: CupertinoColors.black.withValues(alpha: 0.45),
                        borderColor: CupertinoColors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 头像取景遮罩：方形内清晰，方形外压暗
class _SquareCropMaskPainter extends CustomPainter {
  final Rect rect;
  final Color maskColor;
  final Color borderColor;

  _SquareCropMaskPainter({
    required this.rect,
    required this.maskColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final mask = Paint()..color = maskColor;
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, mask);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = borderColor;
    canvas.drawRect(rect, border);
  }

  @override
  bool shouldRepaint(covariant _SquareCropMaskPainter oldDelegate) =>
      oldDelegate.rect != rect || oldDelegate.maskColor != maskColor;
}

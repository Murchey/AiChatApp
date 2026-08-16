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
/// 取景区比例与开屏页 / 聊天背景的实际展示比例一致（均为全屏铺满），
/// 因此裁剪结果即最终展示效果。
///
/// 缩放/拖动使用自定义手势实现：不依赖 InteractiveViewer（其内部会把缩放
/// 下限钳制在「子组件不小于视口」，无法缩到 1x 以下）。允许缩到 0.3x，
/// 缩小后露出的空白区域按当前深浅色模式补色。导出文件写入系统临时目录，
/// 由调用方在使用完毕后删除。
class ImageCropScreen extends StatefulWidget {
  /// 待裁剪的源图片本地路径
  final String imagePath;

  const ImageCropScreen({super.key, required this.imagePath});

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
    final focalScene =
        (_focalStart - _gestureOffsetStart) / _gestureScaleStart;
    var newOffset = details.localFocalPoint - focalScene * newScale;
    final childW = _fitW * newScale;
    final childH = _fitH * newScale;
    // 子图小于视口时保持完整可见且可拖动调整位置，大于视口时允许滑动浏览
    newOffset = Offset(
      newOffset.dx.clamp(
        math.min(viewport.width - childW, 0.0),
        math.max(viewport.width - childW, 0.0),
      ),
      newOffset.dy.clamp(
        math.min(viewport.height - childH, 0.0),
        math.max(viewport.height - childH, 0.0),
      ),
    );
    setState(() {
      _scale = newScale;
      _offset = newOffset;
    });
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
      final captured = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await captured.toByteData(format: ui.ImageByteFormat.png);
      captured.dispose();
      final png = byteData?.buffer.asUint8List();
      if (png == null) throw Exception('图像编码失败');
      final decoded = img.decodeImage(png);
      if (decoded == null) throw Exception('图像解析失败');
      // 压缩为 JPEG，减小开屏 / 背景图片体积
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
    final bg =
        context.isDark ? CupertinoColors.black : CupertinoColors.white;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('调整图片'),
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
          // 取景区：图片铺满，双指缩放/拖动；
          // 缩小到 1x 以下露出的空白区域按当前深浅色模式补色
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
              '双指缩放、拖动调整取景，完成后将按此画面展示',
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
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: _onScaleStart,
          onScaleUpdate: (d) => _onScaleUpdate(d, viewport),
          child: ClipRect(
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
        );
      },
    );
  }
}

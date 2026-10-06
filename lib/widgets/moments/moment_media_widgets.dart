import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:gal/gal.dart';

import '../../config/theme.dart';
import '../../utils/app_toast.dart';
import '../../utils/platform_support.dart';

Widget imagePlaceholder(BuildContext context) {
  return ColoredBox(
    color: context.momentBlockColor,
    child: const Center(
      child: Icon(
        CupertinoIcons.photo,
        size: 20,
        color: CupertinoColors.systemGrey,
      ),
    ),
  );
}

/// 评论输入栏：Overlay 悬浮在软键盘上方（底部随键盘上移），
/// 右侧圆形对号按钮确认发送，左侧下箭头收起键盘/关闭。
/// 输入栏上方不遮挡朋友圈内容，列表仍可滑动操作。
class CommentInputBar extends StatefulWidget {
  final String? initialText;
  final String? replyToName;
  final VoidCallback onClose;
  final ValueChanged<String> onSend;

  const CommentInputBar({
    required this.onClose,
    required this.onSend,
    this.initialText,
    this.replyToName,
  });

  @override
  State<CommentInputBar> createState() => CommentInputBarState();
}

class CommentInputBarState extends State<CommentInputBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    // 键盘弹出时 viewInsets.bottom 增大，输入栏随之悬浮到软键盘上方
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          6,
          8,
          12,
          8 + MediaQuery.of(context).padding.bottom,
        ),
        color: context.listBgColor,
        child: Row(
          children: [
            // 下箭头：收起键盘并关闭输入栏
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClose,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  CupertinoIcons.chevron_down,
                  size: 18,
                  color: context.textSecondaryColor,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: CupertinoTextField(
                controller: _controller,
                autofocus: true,
                maxLength: 100,
                placeholder: widget.initialText != null
                    ? '编辑评论'
                    : (widget.replyToName != null
                        ? '回复 ${widget.replyToName}'
                        : '说点什么...'),
                placeholderStyle: TextStyle(color: context.textSecondaryColor),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(width: 8),
            // 对号按钮：确认发送
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) {
                final canSend = value.text.trim().isNotEmpty;
                return GestureDetector(
                  onTap: canSend ? _send : null,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: canSend
                          ? context.accentColor
                          : context.separatorColor,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      CupertinoIcons.checkmark_alt,
                      size: 18,
                      color: CupertinoColors.white,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 朋友圈单图缩略图（微信风格）：
/// 普通竖图 3:4、横图按原比例；长图（高宽比 ≥ 2.2）加宽并顶部对齐，
/// 避免居中 cover 只露中间细缝。异步读取原图尺寸后计算展示尺寸，避免布局跳动。
class SingleImageThumb extends StatefulWidget {
  final String path;
  final VoidCallback onTap;

  const SingleImageThumb({required this.path, required this.onTap});

  @override
  State<SingleImageThumb> createState() => SingleImageThumbState();
}

class SingleImageThumbState extends State<SingleImageThumb> {
  /// 原图尺寸（优先命中缓存；未知时按默认 3:4 占位）
  Size? _imgSize;

  @override
  void initState() {
    super.initState();
    _loadSize();
  }

  @override
  void didUpdateWidget(covariant SingleImageThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path == widget.path) return;
    _imgSize = null;
    _loadSize();
  }

  Future<void> _loadSize() async {
    final size = await ImageMetadataCache.sizeFor(widget.path);
    if (mounted && size != null) setState(() => _imgSize = size);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // 卡片内容区可用宽度：屏宽 - 列表边距 16*2 - 卡片内边距 12*2 - 头像 34 - 间距 10
    final contentWidth = screenWidth - 32 - 24 - 34 - 10;
    final maxWidth = contentWidth * 0.6;
    const maxHeight = 220.0;

    double w;
    double h;
    var alignment = Alignment.center;
    var filterQuality = FilterQuality.medium;
    final img = _imgSize;
    if (img == null) {
      // 未知尺寸：按 3:4 默认比例占位
      w = maxHeight * 0.75;
      h = maxHeight;
    } else {
      final aspect = img.width / img.height;
      // 长图（截图/长漫等，高宽比 ≥ 2.2）：单独加宽加高，顶部对齐展示开头，
      // 避免 3:4 居中 cover 只露出中间一条细缝造成「比例失真」观感
      final isLongImage = img.height / img.width >= 2.2;
      if (isLongImage) {
        w = contentWidth * 0.72;
        h = (w * img.height / img.width).clamp(180.0, 280.0);
        alignment = Alignment.topCenter;
      } else if (aspect >= 1) {
        // 横图 / 方形：宽优先，高度按原比例，超出高度上限则按比例截断
        w = maxWidth;
        h = w / aspect;
        if (h > maxHeight) {
          h = maxHeight;
          w = h * aspect;
          if (w > maxWidth) w = maxWidth;
        }
      } else {
        // 普通竖图：3:4 缩略图（cover 裁剪，不展示完整图片）
        w = maxHeight * 0.75;
        h = maxHeight;
        if (w > maxWidth) {
          w = maxWidth;
          h = w * 4 / 3;
        }
        // 主体略偏上，减少人物/文字被裁到正中的问题
        alignment = const Alignment(0, -0.15);
      }
    }

    // 解码尺寸按 cover 可视区等比换算：同时写死 cacheWidth/Height 会让
    // Flutter 按盒子尺寸硬解码、忽略原图比例（长图被压成矮胖）。
    final (cacheW, cacheH) = coverDecodeSize(w, h, img, dpr);

    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: w,
          height: h,
          child: Image.file(
            File(widget.path),
            fit: BoxFit.cover,
            alignment: alignment,
            gaplessPlayback: true,
            cacheWidth: cacheW,
            cacheHeight: cacheH,
            filterQuality: filterQuality,
            errorBuilder: (_, __, ___) => imagePlaceholder(context),
          ),
        ),
      ),
    );
  }
}

/// 朋友圈图片全屏预览页：
/// - 黑底全屏，图片按屏幕 contain 适配
/// - 双击放大 / 缩小；双指缩放；`constrained: false` 允许图片放大超出视口后自由拖动查看
/// - 长按弹出【保存图片】到系统相册
class ImagePreviewPage extends StatefulWidget {
  final String path;

  const ImagePreviewPage({required this.path});

  @override
  State<ImagePreviewPage> createState() => ImagePreviewPageState();
}

class ImagePreviewPageState extends State<ImagePreviewPage> {
  final TransformationController _transform = TransformationController();

  /// 图片适配屏幕后的展示尺寸（加载前为 null，此时用全屏占位）
  Size? _fittedSize;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// 读取原图尺寸并按视口 contain 计算初始展示尺寸
  Future<void> _loadImageSize() async {
    final img = await ImageMetadataCache.sizeFor(widget.path) ??
        const Size(1, 1); // 解码失败时回退为全屏 contain
    if (!mounted) return;
    final vp = MediaQuery.of(context).size;
    final scale = math.min(vp.width / img.width, vp.height / img.height);
    setState(() {
      _fittedSize = Size(img.width * scale, img.height * scale);
    });
  }

  /// 双击位置（onDoubleTapDown 记录，onDoubleTap 时使用）
  Offset _doubleTapPos = Offset.zero;

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

  Future<void> _saveImage() async {
    if (!PlatformSupport.supportsGallerySave) {
      showAppToast('当前平台暂不支持保存到相册');
      return;
    }
    // gal 的 putImage 不会自行申请权限：Android 6–9（API 23–28）
    // 需要 WRITE_EXTERNAL_STORAGE 才能写入相册，先检查/申请权限再保存
    if (!await Gal.hasAccess()) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        if (mounted) showAppToast('未获得相册权限，无法保存图片');
        return;
      }
    }
    try {
      await Gal.putImage(widget.path);
      if (mounted) showAppToast('已保存到系统相册');
    } on GalException catch (e) {
      if (!mounted) return;
      showAppToast(
        switch (e.type) {
          GalExceptionType.accessDenied => '未获得相册权限，无法保存图片',
          GalExceptionType.notEnoughSpace => '存储空间不足，保存失败',
          GalExceptionType.notSupportedFormat => '图片格式不支持保存',
          GalExceptionType.unexpected => '保存失败，请重试',
        },
      );
    } catch (_) {
      if (mounted) showAppToast('保存失败，请重试');
    }
  }

  /// 长按图片：弹出操作菜单（保存图片）
  void _showSaveSheet() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('图片操作'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _saveImage();
            },
            child: const Text('保存图片'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.of(context).size;
    final fitted = _fittedSize;
    return ColoredBox(
      color: CupertinoColors.black,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 单击关闭；与双击共存时 Flutter 会等待双击判定，稍显延迟但可接受
        onTap: () => Navigator.of(context).pop(),
        onDoubleTapDown: (details) => _doubleTapPos = details.localPosition,
        onDoubleTap: _toggleZoom,
        onLongPress: _showSaveSheet,
        child: InteractiveViewer(
          transformationController: _transform,
          // 注意：constrained:false 时子组件锚定在视口左上角（不居中），
          // 因此子组件必须是整屏大小的盒子，图片在其内部居中，
          // 否则适配屏幕后的小图会偏移到屏幕顶部。
          constrained: false,
          boundaryMargin: const EdgeInsets.all(200),
          minScale: 1,
          maxScale: 6,
          child: SizedBox(
            width: viewport.width,
            height: viewport.height,
            child: fitted == null
                ? const Center(child: CupertinoActivityIndicator())
                : Center(
                    child: SizedBox(
                      width: fitted.width,
                      height: fitted.height,
                      child: Image.file(
                        File(widget.path),
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Shared, bounded image metadata cache for moment thumbnails and previews.
/// Concurrent requests for the same path share one Future, preventing a fast
/// list scroll followed by a preview tap from reading the file twice.
class ImageMetadataCache {
  ImageMetadataCache._();

  static const _maxEntries = 512;
  static final _sizes = <String, Size>{};
  static final _failed = <String>{};
  static final _pending = <String, Future<Size?>>{};

  static Future<Size?> sizeFor(String path) {
    final cached = _sizes[path];
    if (cached != null) return Future<Size?>.value(cached);
    if (_failed.contains(path)) return Future<Size?>.value(null);
    return _pending[path] ??= _readSize(path).then((size) {
      _pending.remove(path);
      if (size == null) {
        if (_failed.length >= _maxEntries) _failed.remove(_failed.first);
        _failed.add(path);
      } else {
        if (_sizes.length >= _maxEntries) _sizes.remove(_sizes.keys.first);
        _sizes[path] = size;
      }
      return size;
    });
  }

  static Future<Size?> _readSize(String path) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      // Header metadata is read asynchronously; Image.file below still
      // performs the bounded thumbnail decode.
      final bytes = await File(path).readAsBytes();
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      return Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
    } catch (_) {
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

(int, int?) coverDecodeSize(double boxW, double boxH, Size? image, double dpr) {
  if (image == null || image.width <= 0 || image.height <= 0) {
    return ((boxW * dpr).round(), null);
  }
  final scale = math.max(boxW / image.width, boxH / image.height);
  return (
    (image.width * scale * dpr).round(),
    (image.height * scale * dpr).round(),
  );
}

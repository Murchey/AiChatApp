import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../config/theme.dart';

/// 气泡颜色设置行：标题 + 颜色圆点预览 + 右箭头
class BubbleColorRow extends StatelessWidget {
  final String title;
  final Color color;
  final VoidCallback onTap;

  const BubbleColorRow({
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: context.textPrimaryColor,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: context.separatorColor,
                width: 1,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            CupertinoIcons.chevron_right,
            size: 16,
            color: context.textSecondaryColor,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class PresetColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const PresetColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: selected
              ? Border.all(
                  color: context.accentColor,
                  width: 3,
                )
              : null,
        ),
        child: selected
            ? const Icon(
                CupertinoIcons.check_mark,
                size: 20,
                color: CupertinoColors.white,
              )
            : null,
      ),
    );
  }
}

/// 自定义调色盘：颜色网格 + HEX 输入 + HSV 滑块
class CustomColorPicker extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onChanged;

  const CustomColorPicker({
    required this.initialColor,
    required this.onChanged,
  });

  @override
  State<CustomColorPicker> createState() => CustomColorPickerState();
}

class CustomColorPickerState extends State<CustomColorPicker> {
  late HSVColor _hsv;
  late TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
    _hexController =
        TextEditingController(text: _colorToHex(widget.initialColor));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase().padLeft(6, '0')}';
  }

  Color? _hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) {
      try {
        return Color(int.parse('FF$hex', radix: 16));
      } catch (_) {
        return null;
      }
    } else if (hex.length == 8) {
      try {
        return Color(int.parse(hex, radix: 16));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  void update({double? hue, double? saturation, double? value}) {
    setState(() {
      _hsv = HSVColor.fromAHSV(
        1,
        hue ?? _hsv.hue,
        saturation ?? _hsv.saturation,
        value ?? _hsv.value,
      );
    });
    final newColor = _hsv.toColor();
    _hexController.text = _colorToHex(newColor);
    widget.onChanged(newColor);
  }

  void updateFromColor(Color color) {
    setState(() {
      _hsv = HSVColor.fromColor(color);
    });
    _hexController.text = _colorToHex(color);
    widget.onChanged(color);
  }

  @override
  Widget build(BuildContext context) {
    final current = _hsv.toColor();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HSV 取色盘：拖动选择色相与饱和度
          Center(
            child: GestureDetector(
              onPanUpdate: (details) {
                final dx = details.localPosition.dx - 110;
                final dy = details.localPosition.dy - 110;
                final r = math.sqrt(dx * dx + dy * dy);
                if (r > 110) return;
                final hue = (math.atan2(dy, dx) * 180 / math.pi + 360) % 360;
                final sat = (r / 110).clamp(0.0, 1.0);
                update(hue: hue, saturation: sat);
              },
              child: CustomPaint(
                size: const Size(220, 220),
                painter: ColorWheelPainter(
                  hue: _hsv.hue,
                  saturation: _hsv.saturation,
                  value: _hsv.value,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 亮度滑块
          buildSlider(
            label: '亮度',
            value: _hsv.value,
            activeColor:
                HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, 1).toColor(),
            onChanged: (v) => update(value: v),
          ),
          const SizedBox(height: 12),
          // 预览 + HEX 输入
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: current,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.separatorColor),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CupertinoTextField(
                  controller: _hexController,
                  placeholder: '#000000',
                  style: TextStyle(
                    fontSize: 14,
                    color: context.textPrimaryColor,
                  ),
                  decoration: BoxDecoration(
                    color: context.fieldBgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onSubmitted: (value) {
                    final color = _hexToColor(value);
                    if (color != null) {
                      updateFromColor(color);
                    } else {
                      _hexController.text = _colorToHex(current);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 快捷色板
          buildQuickColors(),
        ],
      ),
    );
  }

  Widget buildQuickColors() {
    const colors = [
      Color(0xFFF44336),
      Color(0xFFE91E63),
      Color(0xFF9C27B0),
      Color(0xFF673AB7),
      Color(0xFF3F51B5),
      Color(0xFF2196F3),
      Color(0xFF03A9F4),
      Color(0xFF00BCD4),
      Color(0xFF009688),
      Color(0xFF4CAF50),
      Color(0xFF8BC34A),
      Color(0xFFCDDC39),
      Color(0xFFFFEB3B),
      Color(0xFFFFC107),
      Color(0xFFFF9800),
      Color(0xFFFF5722),
      Color(0xFF795548),
      Color(0xFF9E9E9E),
      Color(0xFF607D8B),
      Color(0xFF000000),
      Color(0xFFFFFFFF),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: colors.map((color) {
        final isSelected = color.toARGB32() == _hsv.toColor().toARGB32();
        return GestureDetector(
          onTap: () => updateFromColor(color),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color:
                    isSelected ? context.accentColor : context.separatorColor,
                width: isSelected ? 2.5 : 1,
              ),
            ),
            child: isSelected
                ? Icon(
                    CupertinoIcons.check_mark,
                    size: 12,
                    color: color.computeLuminance() > 0.5
                        ? CupertinoColors.black
                        : CupertinoColors.white,
                  )
                : null,
          ),
        );
      }).toList(),
    );
  }

  Widget buildSlider({
    required String label,
    required double value,
    required Color activeColor,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: context.textSecondaryColor,
            ),
          ),
        ),
        Expanded(
          child: CupertinoSlider(
            value: value.clamp(0.0, 1.0),
            activeColor: activeColor,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// HSV 取色盘画笔：外圈色相环，内部从白到纯色再到黑色的饱和度/亮度渐变。
class ColorWheelPainter extends CustomPainter {
  final double hue;
  final double saturation;
  final double value;

  ColorWheelPainter({
    required this.hue,
    required this.saturation,
    required this.value,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 绘制 HSV 色环（hue）
    const segments = 360;
    for (var i = 0; i < segments; i++) {
      final startAngle = i * 2 * math.pi / segments;
      const sweepAngle = 2 * math.pi / segments + 0.01;
      final color = HSVColor.fromAHSV(1, i.toDouble(), 1, 1).toColor();
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 28
        ..color = color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 14),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }

    // 绘制内部饱和度渐变（从中心白色到边缘纯色）
    const innerSegments = 64;
    for (var i = 0; i < innerSegments; i++) {
      final r = radius - 28;
      final startAngle = i * 2 * math.pi / innerSegments;
      const sweepAngle = 2 * math.pi / innerSegments + 0.01;
      for (var j = 0; j < 20; j++) {
        final innerR = r * j / 20;
        final outerR = r * (j + 1) / 20;
        final sat = j / 20.0;
        final color = HSVColor.fromAHSV(1, hue, sat, value).toColor();
        final paint = Paint()
          ..style = PaintingStyle.fill
          ..color = color;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: outerR),
          startAngle,
          sweepAngle,
          true,
          paint,
        );
        // 清除内圈重叠部分（用更大半径的 arc 覆盖）
        if (j > 0) {
          final clearPaint = Paint()
            ..style = PaintingStyle.fill
            ..color =
                HSVColor.fromAHSV(1, hue, (j - 1) / 20.0, value).toColor();
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: innerR),
            startAngle,
            sweepAngle,
            true,
            clearPaint,
          );
        }
      }
    }

    // 绘制选择指示点
    final markerR = radius - 28;
    final angle = hue * math.pi / 180;
    final dist = saturation * markerR;
    final markerCenter = Offset(
      center.dx + dist * math.cos(angle),
      center.dy + dist * math.sin(angle),
    );
    canvas.drawCircle(
      markerCenter,
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = CupertinoColors.white,
    );
    canvas.drawCircle(
      markerCenter,
      5,
      Paint()
        ..style = PaintingStyle.fill
        ..color = HSVColor.fromAHSV(1, hue, saturation, value).toColor(),
    );
  }

  @override
  bool shouldRepaint(ColorWheelPainter oldDelegate) =>
      oldDelegate.hue != hue ||
      oldDelegate.saturation != saturation ||
      oldDelegate.value != value;
}

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _showCustomPicker = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('设置')),
      child: ListView(
        children: [
          const SizedBox(height: 12),
          // 明暗模式
          CupertinoListSection.insetGrouped(
            header: const Text('外观'),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: CupertinoSegmentedControl<AppThemeMode>(
                  groupValue: settings.themeMode,
                  onValueChanged: (value) {
                    settings.setThemeMode(value);
                  },
                  children: const {
                    AppThemeMode.system: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Text('跟随系统'),
                    ),
                    AppThemeMode.light: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Text('浅色'),
                    ),
                    AppThemeMode.dark: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Text('深色'),
                    ),
                  },
                ),
              ),
            ],
          ),
          // 主题色
          CupertinoListSection.insetGrouped(
            header: const Text('主题色'),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final color in AppColors.presetColors)
                      _PresetColorDot(
                        color: color,
                        selected: color.toARGB32() ==
                            settings.accentColor.toARGB32(),
                        onTap: () => settings.setAccentColor(color),
                      ),
                  ],
                ),
              ),
              CupertinoListTile(
                title: const Text('自定义颜色'),
                trailing: Icon(
                  _showCustomPicker
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 16,
                  color: context.textSecondaryColor,
                ),
                onTap: () {
                  setState(() {
                    _showCustomPicker = !_showCustomPicker;
                  });
                },
              ),
              if (_showCustomPicker)
                _CustomColorPicker(
                  initialColor: settings.accentColor,
                  onChanged: (color) => settings.setAccentColor(color),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _PresetColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _PresetColorDot({
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
                  color: context.textSecondaryColor,
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

/// 自定义调色盘：H/S/V 三滑块 + 实时预览
class _CustomColorPicker extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onChanged;

  const _CustomColorPicker({
    required this.initialColor,
    required this.onChanged,
  });

  @override
  State<_CustomColorPicker> createState() => _CustomColorPickerState();
}

class _CustomColorPickerState extends State<_CustomColorPicker> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
  }

  void _update({double? hue, double? saturation, double? value}) {
    setState(() {
      _hsv = HSVColor.fromAHSV(
        1,
        hue ?? _hsv.hue,
        saturation ?? _hsv.saturation,
        value ?? _hsv.value,
      );
    });
    widget.onChanged(_hsv.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final current = _hsv.toColor();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 预览 + 当前色值
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
              Text(
                '#${current.toARGB32().toRadixString(16).substring(2).toUpperCase().padLeft(6, '0')}',
                style: TextStyle(
                  fontSize: 14,
                  color: context.textSecondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildSlider(
            label: '色相',
            value: _hsv.hue / 360,
            onChanged: (v) => _update(hue: v * 360),
          ),
          _buildSlider(
            label: '饱和度',
            value: _hsv.saturation,
            onChanged: (v) => _update(saturation: v),
          ),
          _buildSlider(
            label: '亮度',
            value: _hsv.value,
            onChanged: (v) => _update(value: v),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
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
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

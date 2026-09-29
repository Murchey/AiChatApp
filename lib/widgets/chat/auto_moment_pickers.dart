import 'package:flutter/cupertino.dart';

import '../../config/theme.dart';
import '../../providers/auto_moment_provider.dart';
import '../../providers/proactive_greeting_provider.dart';

/// 「发送频率」可折叠区块（drawer 形式）：
/// 平时只显示一行摘要，点击标题行伸出滚轮，修改后再点标题行收回。
class AutoMomentPickerSection extends StatefulWidget {
  final int initialPeriodHours;
  final int initialCount;
  final ValueChanged<int> onPeriodChanged;
  final ValueChanged<int> onCountChanged;

  const AutoMomentPickerSection({
    super.key,
    required this.initialPeriodHours,
    required this.initialCount,
    required this.onPeriodChanged,
    required this.onCountChanged,
  });

  @override
  State<AutoMomentPickerSection> createState() =>
      AutoMomentPickerSectionState();
}

class AutoMomentPickerSectionState extends State<AutoMomentPickerSection> {
  bool _expanded = false;

  int _periodIndex(int hours) {
    final idx = AutoMomentProvider.periodOptions.indexOf(hours);
    return idx < 0 ? 3 : idx; // 默认 3 天（index 3）
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final label = AutoMomentProvider
        .periodLabels[_periodIndex(widget.initialPeriodHours)];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 标题行（父节点）：点击展开 / 收回滚轮
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: Container(
            color: context.listBgColor,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.clock,
                  size: 20,
                  color: context.textPrimaryColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '发送频率',
                        style: TextStyle(
                          fontSize: 16,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '每 $label 发 ${widget.initialCount} 条',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _expanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 16,
                  color: context.textSecondaryColor,
                ),
              ],
            ),
          ),
        ),
        // 展开内容：滚轮（AnimatedSize 平滑伸缩）
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _expanded
              ? AutoMomentPicker(
                  initialPeriodHours: widget.initialPeriodHours,
                  initialCount: widget.initialCount,
                  onPeriodChanged: widget.onPeriodChanged,
                  onCountChanged: widget.onCountChanged,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class AutoMomentPicker extends StatefulWidget {
  final int initialPeriodHours;
  final int initialCount;
  final ValueChanged<int> onPeriodChanged;
  final ValueChanged<int> onCountChanged;

  const AutoMomentPicker({
    required this.initialPeriodHours,
    required this.initialCount,
    required this.onPeriodChanged,
    required this.onCountChanged,
  });

  @override
  State<AutoMomentPicker> createState() => AutoMomentPickerState();
}

class AutoMomentPickerState extends State<AutoMomentPicker> {
  late FixedExtentScrollController _periodController;
  late FixedExtentScrollController _countController;

  @override
  void initState() {
    super.initState();
    _periodController = FixedExtentScrollController(
      initialItem: _periodIndex(widget.initialPeriodHours),
    );
    _countController = FixedExtentScrollController(
      initialItem: widget.initialCount - 1,
    );
  }

  @override
  void dispose() {
    _periodController.dispose();
    _countController.dispose();
    super.dispose();
  }

  int _periodIndex(int hours) {
    final idx = AutoMomentProvider.periodOptions.indexOf(hours);
    return idx < 0 ? 3 : idx; // 默认 3 天（index 3）
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: Row(
        children: [
          Expanded(
            child: CupertinoPicker(
              scrollController: _periodController,
              itemExtent: 32,
              onSelectedItemChanged: (i) =>
                  widget.onPeriodChanged(AutoMomentProvider.periodOptions[i]),
              children: AutoMomentProvider.periodLabels
                  .map((l) => Center(
                        child: Text(
                          l,
                          style: TextStyle(
                            fontSize: 15,
                            color: context.textPrimaryColor,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          Text(
            '每',
            style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
          ),
          Expanded(
            child: CupertinoPicker(
              scrollController: _countController,
              itemExtent: 32,
              onSelectedItemChanged: (i) => widget.onCountChanged(i + 1),
              children: [
                for (var n = AutoMomentProvider.minCount;
                    n <= AutoMomentProvider.maxCount;
                    n++)
                  Center(
                    child: Text(
                      '$n',
                      style: TextStyle(
                        fontSize: 15,
                        color: context.textPrimaryColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '条',
            style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
          ),
        ],
      ),
    );
  }
}

/// 主动问候频率选择器：类似朋友圈的 drawer 滚轮，选择空闲时长
class ProactiveGreetingPickerSection extends StatefulWidget {
  final int initialIdleHours;
  final ValueChanged<int> onChanged;

  const ProactiveGreetingPickerSection({
    super.key,
    required this.initialIdleHours,
    required this.onChanged,
  });

  @override
  State<ProactiveGreetingPickerSection> createState() =>
      ProactiveGreetingPickerSectionState();
}

class ProactiveGreetingPickerSectionState
    extends State<ProactiveGreetingPickerSection> {
  bool _expanded = false;
  late FixedExtentScrollController _controller;

  int _idleIndex(int hours) {
    final idx = ProactiveGreetingProvider.idleOptions.indexOf(hours);
    return idx < 0 ? 3 : idx; // 默认 3 天
  }

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(
      initialItem: _idleIndex(widget.initialIdleHours),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = ProactiveGreetingProvider
        .idleLabels[_idleIndex(widget.initialIdleHours)];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            color: context.listBgColor,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.clock,
                  size: 20,
                  color: context.textPrimaryColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '触发频率',
                        style: TextStyle(
                          fontSize: 16,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _expanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 16,
                  color: context.textSecondaryColor,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _expanded
              ? SizedBox(
                  height: 160,
                  child: CupertinoPicker(
                    scrollController: _controller,
                    itemExtent: 32,
                    onSelectedItemChanged: (i) => widget
                        .onChanged(ProactiveGreetingProvider.idleOptions[i]),
                    children: ProactiveGreetingProvider.idleLabels
                        .map((l) => Center(
                              child: Text(
                                l,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: context.textPrimaryColor,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}


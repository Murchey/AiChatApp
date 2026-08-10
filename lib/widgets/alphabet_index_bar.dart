import 'package:flutter/cupertino.dart';
import '../config/theme.dart';

/// 通讯录右侧字母索引栏（A-Z + #），支持点击与长按滑动
class AlphabetIndexBar extends StatelessWidget {
  final Set<String> availableLetters;
  final ValueChanged<String> onLetterChanged;
  final VoidCallback onDragEnd;

  const AlphabetIndexBar({
    super.key,
    required this.availableLetters,
    required this.onLetterChanged,
    required this.onDragEnd,
  });

  static final _letters = ['#', ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')];
  static const double _itemHeight = 18;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 计算居中时字母列表的起始 Y 坐标
        final totalHeight = _letters.length * _itemHeight;
        final topOffset = (constraints.maxHeight - totalHeight) / 2;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            _handle(details.localPosition.dy, topOffset);
          },
          onVerticalDragStart: (details) {
            _handle(details.localPosition.dy, topOffset);
          },
          onVerticalDragUpdate: (details) {
            _handle(details.localPosition.dy, topOffset);
          },
          onVerticalDragEnd: (_) {
            onDragEnd();
          },
          child: Container(
            width: 32,
            color: CupertinoColors.transparent,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _letters.map((letter) {
                final isAvailable = availableLetters.contains(letter);
                return Container(
                  height: _itemHeight,
                  width: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isAvailable
                        ? context.accentColor.withValues(alpha: 0.12)
                        : null,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isAvailable
                          ? context.accentColor
                          : context.textSecondaryColor.withValues(alpha: 0.35),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _handle(double localY, double topOffset) {
    final index = ((localY - topOffset) / _itemHeight).floor();
    if (index >= 0 && index < _letters.length) {
      // 所有字母都触发，无数据的字母由上层就近滚动
      onLetterChanged(_letters[index]);
    }
  }
}

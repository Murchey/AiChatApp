import 'package:flutter/cupertino.dart';
import '../config/theme.dart';

/// 通讯录右侧字母索引栏（A-Z + #）。
///
/// 用 [Listener] 收原始指针事件，不进手势竞技场，避免与外层 PageView
/// 的横向拖拽、列表纵向滚动抢事件导致「只有从顶部开始滑才灵敏」。
/// 字母高度按可用高度均分铺满，任意位置按下都与字母 1:1 对应。
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
  // 字母过矮时的保底高度；正常屏幕会被可用高度均分值覆盖
  static const double _minItemHeight = 14;
  // 侧边命中条宽度：略宽于字母，手指在条附近也能滑到
  static const double _hitWidth = 44;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = _letters.length;
        final maxH = constraints.maxHeight;
        // 均分铺满侧边条；高度异常时退回保底值并整体居中
        final double itemHeight;
        final bool fillHeight =
            maxH.isFinite && maxH > count * _minItemHeight;
        itemHeight = fillHeight ? maxH / count : _minItemHeight;

        void handle(Offset local) {
          var index = (local.dy / itemHeight).floor();
          if (index < 0) index = 0;
          if (index >= count) index = count - 1;
          onLetterChanged(_letters[index]);
        }

        final letterColumn = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final letter in _letters)
              SizedBox(
                height: itemHeight,
                child: _LetterCell(
                  letter: letter,
                  isAvailable: availableLetters.contains(letter),
                ),
              ),
          ],
        );

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => handle(e.localPosition),
          onPointerMove: (e) => handle(e.localPosition),
          onPointerUp: (_) => onDragEnd(),
          onPointerCancel: (_) => onDragEnd(),
          child: SizedBox(
            width: _hitWidth,
            child: fillHeight
                ? letterColumn
                : Center(child: letterColumn),
          ),
        );
      },
    );
  }
}

class _LetterCell extends StatelessWidget {
  final String letter;
  final bool isAvailable;

  const _LetterCell({required this.letter, required this.isAvailable});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isAvailable
            ? context.accentColor.withValues(alpha: 0.12)
            : null,
        borderRadius: BorderRadius.circular(3),
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
  }
}

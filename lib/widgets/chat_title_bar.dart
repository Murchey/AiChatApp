import 'package:flutter/cupertino.dart';
import '../config/theme.dart';
import '../providers/settings_provider.dart';
import '../services/prompt_builder.dart';

/// 会话顶部标题栏（随 UI 样式变化）。
///
/// 经典样式：居中显示会话名称；
/// zmd 终末地样式：名称靠左，名称下方以小字展示副标题。
///
/// 私聊：同行显示在线状态（绿点=活跃时段内 / 红点=非活跃时段），
/// 副标题为角色个性签名（最多展示前 15 个字，超出省略号）。
/// 群聊：群名称 + 群简介副标题（空则不显示）；回复中名称右侧显示
/// 黄色呼吸灯点 + 输入状态文字（如「输入中（n/m）」），完成后消失。
class ChatTitleBar extends StatelessWidget {
  final String name;
  final String signature;
  final String activeStart;
  final String activeEnd;

  /// 是否为群聊会话（群聊不显示在线状态点，副标题为群简介）
  final bool isGroup;

  /// 群聊简介（副标题，空则不显示）
  final String groupIntro;

  /// 群聊输入状态文字（如「输入中（n/m）」）；非空时名称右侧显示黄色呼吸灯点 + 该文字
  final String? inputStatus;

  const ChatTitleBar({
    super.key,
    required this.name,
    this.signature = '',
    this.activeStart = '',
    this.activeEnd = '',
    this.isGroup = false,
    this.groupIntro = '',
    this.inputStatus,
  });

  /// 个性签名：最多展示前 15 个字，超出用省略号
  static String truncateSignature(String signature) {
    final s = signature.trim();
    if (s.length <= 15) return s;
    return '${s.substring(0, 15)}…';
  }

  @override
  Widget build(BuildContext context) {
    if (context.uiStyle != UiStyle.zmd) {
      return Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final active =
        PromptBuilder.inActivePeriod(DateTime.now(), activeStart, activeEnd);
    // 副标题：群聊取群简介（完整展示，超长省略），私聊取个性签名（前 15 字）
    final subtitle = (isGroup ? groupIntro : signature).trim();
    final subtitleText =
        isGroup ? subtitle : truncateSignature(subtitle);
    return Column(
      mainAxisSize: MainAxisSize.min,
      // 终末地样式：名称与状态同行靠左排列，副标题小字位于下方
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // 显式使用主文字色，保证预览区与导航栏在深浅色模式下均可见
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimaryColor,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // 输入状态（黄点呼吸灯）优先于在线状态点；
            // 群聊无输入状态时无状态点，私聊显示活跃状态点（绿=活跃 / 红=非活跃）
            if (inputStatus != null)
              _BreathingInputStatus(label: inputStatus!)
            else if (isGroup)
              const SizedBox.shrink()
            else
              _ActiveStatusDot(active: active),
          ],
        ),
        if (subtitleText.isNotEmpty) ...[
          const SizedBox(height: 1),
          Text(
            subtitleText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: context.textSecondaryColor,
            ),
          ),
        ],
      ],
    );
  }
}

/// 私聊活跃状态点：绿点=活跃时段内，红点=非活跃时段，右侧带「在线/离线」小字
class _ActiveStatusDot extends StatelessWidget {
  final bool active;

  const _ActiveStatusDot({required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF2BB673) : const Color(0xFFFF5252),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          active ? '在线' : '离线',
          style: TextStyle(
            fontSize: 11,
            color: context.textSecondaryColor,
          ),
        ),
      ],
    );
  }
}

/// 群聊输入状态：黄色小圆点 + 输入状态文字，整体带微微呼吸灯效
class _BreathingInputStatus extends StatefulWidget {
  final String label;

  const _BreathingInputStatus({required this.label});

  @override
  State<_BreathingInputStatus> createState() => _BreathingInputStatusState();
}

class _BreathingInputStatusState extends State<_BreathingInputStatus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    // 呼吸灯效：透明度在 0.45 ~ 1.0 之间往返，缓慢柔和
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 黄色小圆点（终末地主题金）
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFFD8BF00),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 11,
              color: context.textSecondaryColor,
            ),
          ),
        ],
      ),
    );
  }
}

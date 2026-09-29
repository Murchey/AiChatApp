import 'package:flutter/cupertino.dart';

import '../../config/theme.dart';
import '../../widgets/character_avatar.dart';

/// 会话详情顶部角色卡
class ChatDetailCharacterCard extends StatelessWidget {
  final String avatar;
  final String displayName;
  final String signature;
  final String region;
  final VoidCallback onTapCard;
  final VoidCallback onTapAvatar;

  const ChatDetailCharacterCard({
    super.key,
    required this.avatar,
    required this.displayName,
    this.signature = '',
    this.region = '',
    required this.onTapCard,
    required this.onTapAvatar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTapCard,
        child: Row(
          children: [
            GestureDetector(
              onTap: onTapAvatar,
              child: Stack(
                children: [
                  CharacterAvatar(
                    base64: avatar,
                    size: 72,
                    borderRadius: BorderRadius.circular(12),
                    iconSize: 36,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: context.accentColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: context.listBgColor,
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        CupertinoIcons.camera_fill,
                        size: 10,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  if (signature.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      signature,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                  if (region.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.location,
                          size: 13,
                          color: context.textSecondaryColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          region,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: context.textSecondaryColor,
            ),
          ],
        ),
      ),
    );
  }
}

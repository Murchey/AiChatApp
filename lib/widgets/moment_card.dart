import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import '../models/character.dart';
import '../models/moment.dart';

/// 头像 base64 缓存：同一 base64 复用同一 MemoryImage，避免 ImageCache 永不命中导致闪动
final Map<String, MemoryImage> _momentAvatarCache = {};

MemoryImage _cachedAvatar(String base64) {
  return _momentAvatarCache.putIfAbsent(base64, () {
    if (_momentAvatarCache.length > 64) _momentAvatarCache.clear();
    return MemoryImage(base64Decode(base64));
  });
}

/// 朋友圈卡片：小头像 + 昵称、正文、图片（最多 9 张，3 列网格）、
/// 点赞/评论、时间。深色朋友圈风格，用于角色空间页与朋友圈页。
class MomentCard extends StatelessWidget {
  final Character character;
  final Moment moment;

  const MomentCard({
    super.key,
    required this.character,
    required this.moment,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF202024),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _avatar(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  character.displayName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.white,
                  ),
                ),
                if (moment.content.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    moment.content,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: CupertinoColors.white,
                    ),
                  ),
                ],
                if (moment.images.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _images(context),
                ],
                if (moment.likes.isNotEmpty || moment.comments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _interactions(),
                ],
                const SizedBox(height: 6),
                Text(
                  _formatTime(moment.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: CupertinoColors.systemGrey.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 小头像：已设置用图片，未设置用默认用户图标
  Widget _avatar() {
    if (character.avatar.isNotEmpty) {
      return Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          image: DecorationImage(
            image: _cachedAvatar(character.avatar),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: const Icon(
        CupertinoIcons.person_fill,
        size: 20,
        color: CupertinoColors.white,
      ),
    );
  }

  /// 图片：最多 9 张，1 张大图、多张 3 列网格；缺失时只显示文字占位。
  /// 点击图片全屏预览。
  Widget _images(BuildContext context) {
    final shown = moment.images.where((p) => File(p).existsSync()).take(9).toList();
    if (shown.isEmpty) {
      return Text(
        '图片加载失败',
        style: TextStyle(
          fontSize: 12,
          color: CupertinoColors.systemGrey.withValues(alpha: 0.7),
        ),
      );
    }
    if (shown.length == 1) {
      return GestureDetector(
        onTap: () => _previewImage(context, shown.first),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: double.infinity,
            height: 150,
            child: Image(
              image: FileImage(File(shown.first)),
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
        ),
      );
    }
    // 多图：3 列网格，单格按卡片内可用宽度均分
    final screenWidth = MediaQuery.of(context).size.width;
    final cell = (screenWidth - 32 - 24 - 34 - 10 - 8) / 3;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: shown.map((p) {
        return GestureDetector(
          onTap: () => _previewImage(context, p),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: cell,
              height: cell,
              child: Image(
                image: FileImage(File(p)),
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 点赞 + 评论区：浅底块内先点赞昵称，再逐条评论（昵称蓝色）
  Widget _interactions() {
    final hasLikes = moment.likes.isNotEmpty;
    final hasComments = moment.comments.isNotEmpty;
    if (!hasLikes && !hasComments) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF18181A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasLikes) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  CupertinoIcons.heart_fill,
                  size: 13,
                  color: Color(0xFFFA5151),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    moment.likes.join('、'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF8FB8E8),
                    ),
                  ),
                ),
              ],
            ),
            if (hasComments) const SizedBox(height: 6),
          ],
          if (hasComments)
            ...moment.comments.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${c.sender}：',
                        style: const TextStyle(color: Color(0xFF8FB8E8)),
                      ),
                      TextSpan(text: c.content),
                    ],
                  ),
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: CupertinoColors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 全屏预览朋友圈图片（点击任意位置关闭）
  void _previewImage(BuildContext context, String path) {
    if (!File(path).existsSync()) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: CupertinoColors.black.withValues(alpha: 0.9),
        barrierDismissible: true,
        pageBuilder: (_, __, ___) => GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: InteractiveViewer(
              maxScale: 4,
              child: Image.file(File(path)),
            ),
          ),
        ),
      ),
    );
  }

  /// 时间显示：今天/昨天显示时分，同一年省略年份
  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final d = time.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    String two(int n) => n.toString().padLeft(2, '0');
    final hm = '${two(d.hour)}:${two(d.minute)}';
    final diff = today.difference(day).inDays;
    if (diff == 0) return '今天 $hm';
    if (diff == 1) return '昨天 $hm';
    if (d.year == now.year) return '${two(d.month)}-${two(d.day)} $hm';
    return '${d.year}-${two(d.month)}-${two(d.day)} $hm';
  }
}

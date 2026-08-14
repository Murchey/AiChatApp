import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/character_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/moment_notification_provider.dart';
import '../services/storage_manager_service.dart';
import '../services/workshop_service.dart';
import '../utils/app_toast.dart';

/// 管理占用空间页：扫描应用自身占用（用户数据 + 软件缓存），
/// 按分类展示体积，供用户选择删除。
///
/// 从「我 → 设置 → 存储空间 → 管理占用空间」进入。
/// 进入时扫描一次；删除某项后重新扫描并提示释放的体积。
class StorageManageScreen extends StatefulWidget {
  const StorageManageScreen({super.key});

  @override
  State<StorageManageScreen> createState() => _StorageManageScreenState();
}

class _StorageManageScreenState extends State<StorageManageScreen> {
  List<StorageItem> _items = [];
  bool _loading = true;

  int get _totalBytes => _items.fold(0, (sum, i) => sum + i.sizeBytes);

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _loading = true);
    List<StorageItem> items = [];
    try {
      items = await StorageManagerService.scan();
    } catch (e, st) {
      debugPrint('[StorageManage] scan failed: $e\n$st');
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  /// 文件体积展示：B / KB / MB / GB
  static String formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  String _confirmMessage(StorageItem item) {
    switch (item.id) {
      case 'chat':
        return '将删除全部聊天记录（含导入的图片和文件），删除后不可恢复。确定继续吗？';
      case 'character':
        return '将删除自定义角色、朋友圈动态与图片（含头像/背景），恢复为内置默认角色。确定继续吗？';
      case 'notification':
        return '将删除全部朋友圈消息通知（未读提醒随之消失）。确定继续吗？';
      case 'profile':
        return '将清除用户资料中的头像、签名、地区与性别，昵称和账号保留。确定继续吗？';
      case 'download_cache':
        return '将删除创意工坊下载后残留的角色资源包 zip 与临时文件，不影响已导入的角色数据和朋友圈图片。确定继续吗？';
      case 'temp':
        return '将删除系统临时目录中的缓存文件，不影响已保存的数据。确定继续吗？';
      default:
        return '确定删除该分类的内容吗？删除后不可恢复。';
    }
  }

  /// 点击删除项：二次确认 → 删除 → 重新扫描 → 提示释放体积
  Future<void> _delete(StorageItem item) async {
    if (item.id == 'other' || item.id == 'settings') {
      showAppToast('该分类仅展示占用，不支持删除');
      return;
    }
    if (!item.deletable) {
      showAppToast('没有可清理的内容');
      return;
    }
    // 提前捕获 provider，避免异步等待后再用 context 读取
    final chatProvider = context.read<ChatProvider>();
    final characterProvider = context.read<CharacterProvider>();
    final notificationProvider = context.read<MomentNotificationProvider>();
    final authProvider = context.read<AuthProvider>();

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('删除「${item.title}」'),
        content: Text(
          _confirmMessage(item),
          textAlign: TextAlign.left,
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final before = item.sizeBytes;
    switch (item.id) {
      case 'chat':
        await chatProvider.clearAllData();
        await StorageManagerService.clearChatFiles();
        break;
      case 'character':
        await characterProvider.resetAllData();
        await StorageManagerService.clearCharacterFiles();
        break;
      case 'notification':
        await notificationProvider.clearAll();
        break;
      case 'profile':
        await authProvider.clearProfileData();
        break;
      case 'download_cache':
        await WorkshopService.clearDownloadCache();
        await StorageManagerService.clearUpdateApks();
        break;
      case 'temp':
        await StorageManagerService.clearTempFiles();
        break;
    }
    await _scan();
    if (!mounted) return;
    final current = _items
        .where((i) => i.id == item.id)
        .fold<int>(0, (sum, i) => sum + i.sizeBytes);
    final freed = before - current;
    showAppToast(freed > 0 ? '已释放 ${formatBytes(freed)}' : '没有可清理的内容');
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('管理占用空间'),
      ),
      child: Container(
        color: context.scaffoldColor,
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                children: [
                  const SizedBox(height: 12),
                  // 总览
                  CupertinoListSection.insetGrouped(
                    backgroundColor: context.scaffoldColor,
                    decoration: BoxDecoration(
                      color: context.listBgColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    header: const Text('总览'),
                    children: [
                      CupertinoListTile(
                        title: const Text('应用占用空间'),
                        subtitle: Text(
                          '用户数据与软件缓存合计',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondaryColor,
                          ),
                        ),
                        trailing: Text(
                          formatBytes(_totalBytes),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: context.accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 用户数据
                  _buildSection(
                    header: '用户数据',
                    items: _items.where((i) => i.isUserData).toList(),
                  ),
                  // 软件缓存
                  _buildSection(
                    header: '软件缓存',
                    items: _items.where((i) => !i.isUserData).toList(),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _buildSection({required String header, required List<StorageItem> items}) {
    if (items.isEmpty) return const SizedBox.shrink();
    return CupertinoListSection.insetGrouped(
      backgroundColor: context.scaffoldColor,
      decoration: BoxDecoration(
        color: context.listBgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      header: Text(header),
      children: [
        for (final item in items)
          CupertinoListTile(
            title: Text(item.title),
            subtitle: Text(
              item.subtitle,
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatBytes(item.sizeBytes),
                  style: TextStyle(
                    fontSize: 14,
                    color: item.deletable
                        ? context.textSecondaryColor
                        : context.textSecondaryColor.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  CupertinoIcons.trash,
                  size: 18,
                  color: item.deletable
                      ? CupertinoColors.systemRed
                      : context.textSecondaryColor.withValues(alpha: 0.4),
                ),
              ],
            ),
            onTap: () => _delete(item),
          ),
      ],
    );
  }
}

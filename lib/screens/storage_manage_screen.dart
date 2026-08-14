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
      case 'other':
        return '将删除可安全清理的残留文件（如导出包、临时文件）；无法确认安全性的未分类目录会保留。确定继续吗？';
      default:
        return '确定删除该分类的内容吗？删除后不可恢复。';
    }
  }

  /// 点击删除项：二次确认 → 删除 → 重新扫描 → 提示释放体积
  Future<void> _delete(StorageItem item) async {
    if (item.id == 'settings') {
      showAppToast('该分类仅展示占用，不支持删除');
      return;
    }
    if (!item.deletable) {
      showAppToast('没有可清理的内容');
      return;
    }
    // 其他应用文件：先展示未分类目录明细供用户确认
    if (item.id == 'other') {
      await _deleteOther(item);
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
    if (freed > 0) {
      showAppToast(
        current > 0
            ? '已释放 ${formatBytes(freed)}，其余内容无法安全删除已保留'
            : '已释放 ${formatBytes(freed)}',
      );
    } else {
      showAppToast(current > 0 ? '没有可安全删除的内容' : '没有可清理的内容');
    }
  }

  /// 删除「其他应用文件」：由程序自动分析文件内容/类型确立安全边界，
  /// 只删确认安全的残留（图片/压缩包/临时文件），
  /// 含数据文件的目录自动保留，用户仅需一次确认。
  Future<void> _deleteOther(StorageItem item) async {
    final plan = await StorageManagerService.planOtherCleanup();
    if (!mounted) return;
    if (plan.deletableBytes <= 0) {
      showAppToast(
        plan.retainedBytes > 0
            ? '没有可安全删除的内容（其余均为数据文件，已保留）'
            : '没有可清理的内容',
      );
      return;
    }
    final before = item.sizeBytes;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除「其他应用文件」'),
        content: Text(
          '将删除已识别为安全的残留内容：'
          '${plan.deletableCount} 项（图片、压缩包、临时文件等），'
          '共 ${formatBytes(plan.deletableBytes)}。'
          '${plan.retainedDirs > 0 ? '另有 ${plan.retainedDirs} 个含数据文件的目录（共 ${formatBytes(plan.retainedBytes)}）将保留：${plan.retainedNames.take(3).join('、')}${plan.retainedNames.length > 3 ? ' 等' : ''}。' : ''}'
          '确定继续吗？',
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

    await StorageManagerService.clearOtherFiles();
    await _scan();
    if (!mounted) return;
    final current = _items
        .where((i) => i.id == item.id)
        .fold<int>(0, (sum, i) => sum + i.sizeBytes);
    final released = before - current;
    if (released > 0) {
      showAppToast(
        current > 0
            ? '已释放 ${formatBytes(released)}，其余数据文件已保留'
            : '已释放 ${formatBytes(released)}',
      );
    } else {
      showAppToast(current > 0 ? '没有可安全删除的内容' : '没有可清理的内容');
    }
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
            // CupertinoListTile 默认把 subtitle 限制为 2 行（折叠省略号），
            // 显式放宽行数，让分类说明完整展示。
            subtitle: Text(
              item.subtitle,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
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

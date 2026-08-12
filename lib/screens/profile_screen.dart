import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/dev_log_service.dart';
import '../services/update_service.dart';
import '../widgets/update_dialogs.dart';
import 'api_settings_screen.dart';
import 'character_manage_screen.dart';
import 'moments_manage_screen.dart';
import 'profile_edit_screen.dart';
import 'settings_screen.dart';
import 'workshop_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _appVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = info.version);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('我'),
      ),
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          final user = auth.user;
          final settings = context.watch<SettingsProvider>();
          return ListView(
            children: [
              // 资料卡（微信个人页样式：方形头像靠左）
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => const ProfileEditScreen(),
                    ),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.listBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _buildSquareAvatar(context, user),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.nickname ?? '未登录',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: context.textPrimaryColor,
                              ),
                            ),
                            if (user != null &&
                                user.signature.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                user.signature,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.textSecondaryColor,
                                ),
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
              ),
              // 角色管理
              CupertinoListSection.insetGrouped(
                backgroundColor: context.scaffoldColor,
                decoration: BoxDecoration(
                  color: context.listBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                children: [
                  CupertinoListTile(
                    leading: Icon(
                      CupertinoIcons.person_2_fill,
                      color: context.accentColor,
                    ),
                    title: const Text('管理当前角色'),
                    subtitle: Text(
                      '添加 / 删除 / 导出角色包',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    trailing: Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: context.textSecondaryColor,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) => const CharacterManageScreen(),
                        ),
                      );
                    },
                  ),
                  CupertinoListTile(
                    leading: Icon(
                      CupertinoIcons.photo,
                      color: context.accentColor,
                    ),
                    title: const Text('管理当前朋友圈'),
                    subtitle: Text(
                      '导入 / 管理朋友圈数据',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    trailing: Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: context.textSecondaryColor,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) => const MomentsManageScreen(),
                        ),
                      );
                    },
                  ),
                  CupertinoListTile(
                    leading: Icon(
                      CupertinoIcons.hammer_fill,
                      color: context.accentColor,
                    ),
                    title: const Text('创意工坊'),
                    subtitle: Text(
                      '从仓库下载导入角色包 / 游戏包',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    trailing: Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: context.textSecondaryColor,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) => const WorkshopScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              // 设置列表
              CupertinoListSection.insetGrouped(
                backgroundColor: context.scaffoldColor,
                decoration: BoxDecoration(
                  color: context.listBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                children: [
                  CupertinoListTile(
                    leading: Icon(
                      CupertinoIcons.settings,
                      color: context.accentColor,
                    ),
                    title: const Text('设置'),
                    trailing: Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: context.textSecondaryColor,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                  CupertinoListTile(
                    leading: Icon(
                      CupertinoIcons.lock,
                      color: context.accentColor,
                    ),
                    title: const Text('API 设置'),
                    trailing: Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: context.textSecondaryColor,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) => const ApiSettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              // 关于
              CupertinoListSection.insetGrouped(
                backgroundColor: context.scaffoldColor,
                decoration: BoxDecoration(
                  color: context.listBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                children: [
                  CupertinoListTile(
                    leading: Icon(
                      CupertinoIcons.info_circle,
                      color: context.accentColor,
                    ),
                    title: const Text('软件版本'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'V$_appVersion',
                          style: TextStyle(
                            fontSize: 15,
                            color: context.textSecondaryColor,
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
                    onTap: () => _checkUpdate(context),
                  ),
                  CupertinoListTile(
                    leading: Icon(
                      CupertinoIcons.link,
                      color: context.accentColor,
                    ),
                    title: const Text('项目仓库'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'GitHub:Murchey/AiChat',
                          style: TextStyle(
                            fontSize: 14,
                            color: context.textSecondaryColor,
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
                    onTap: () => _openUrl(kGitHubRepoUrl),
                  ),
                  CupertinoListTile(
                    leading: Icon(
                      CupertinoIcons.person_2,
                      color: context.accentColor,
                    ),
                    title: const Text('角色卡项目地址'),
                    subtitle: Text(
                      "GitHub:Murchey/AiChatCharacterCommunity",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    trailing: Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: context.textSecondaryColor,
                    ),
                    onTap: () => _openUrl(kCharacterCommunityUrl),
                  ),
                ],
              ),
              // 开发者模式：底部实时显示软件通知与朋友圈 AI 互动日志
              if (settings.developerMode) _buildDevLogPanel(context),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  /// 开发者模式下的日志文本框：实时展示软件通知与朋友圈 AI 互动日志
  Widget _buildDevLogPanel(BuildContext context) {
    return ListenableBuilder(
      listenable: DevLogService.instance,
      builder: (context, _) {
        final lines = DevLogService.instance.lines;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          decoration: BoxDecoration(
            color: context.listBgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '开发者日志',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimaryColor,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: DevLogService.instance.clear,
                      child: Text(
                        '清空',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 260,
                width: double.infinity,
                color: const Color(0xFF0D1117),
                child: lines.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          '暂无日志',
                          style: TextStyle(fontSize: 12, color: Color(0xFF8B949E)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: lines.length,
                        itemBuilder: (context, i) => Text(
                          lines[i],
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            color: Color(0xFFC9D1D9),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTip(BuildContext context, String message) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('提示'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildSquareAvatar(BuildContext context, User? user) {
    final hasAvatar = user != null && user.avatar.isNotEmpty;
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0x00000000),
        image: hasAvatar
            ? DecorationImage(
                image: MemoryImage(base64Decode(user.avatar)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: hasAvatar
          ? null
          : Text(
              user != null && user.nickname.isNotEmpty ? user.nickname[0] : '?',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: context.accentColor,
              ),
            ),
    );
  }

  /// 调用系统默认浏览器打开链接
  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !mounted) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _showTip(context, '无法打开链接');
  }

  /// 检查更新：先展示检查中弹窗，再根据结果弹出对应提示
  Future<void> _checkUpdate(BuildContext context) async {
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CupertinoAlertDialog(
        title: Text('检查更新'),
        content: Padding(
          padding: EdgeInsets.only(top: 16),
          child: CupertinoActivityIndicator(radius: 14),
        ),
      ),
    );

    UpdateInfo? info;
    final settings = context.read<SettingsProvider>();
    try {
      info = await UpdateService.checkForUpdate(proxyUrl: settings.updateProxyUrl);
    } catch (_) {}

    if (!context.mounted) return;
    // 关闭"检查更新"弹窗
    Navigator.of(context, rootNavigator: true).pop();

    if (info == null) {
      _showTip(context, '当前已是最新版本 V$_appVersion');
      return;
    }
    showUpdateAvailableDialog(context, info, proxyUrl: settings.updateProxyUrl);
  }
}

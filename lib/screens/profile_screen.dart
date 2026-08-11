import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/update_service.dart';
import '../utils/character_pack_picker.dart';
import '../widgets/update_dialogs.dart';
import 'api_settings_screen.dart';
import 'character_import_screen.dart';
import 'character_manage_screen.dart';
import 'profile_edit_screen.dart';
import 'settings_screen.dart';

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
                      CupertinoIcons.archivebox,
                      color: context.accentColor,
                    ),
                    title: const Text('导入角色包'),
                    trailing: Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: context.textSecondaryColor,
                    ),
                    onTap: () => _importCharacterPack(context),
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
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  /// 选择 zip 角色包并进入勾选导入页
  Future<void> _importCharacterPack(BuildContext context) async {
    try {
      final result = await pickAndParseCharacterPack();
      if (result == null || !context.mounted) return;
      if (result.entries.isEmpty) {
        _showTip(context, '该 zip 中没有找到角色包（需包含 Profile.json 的角色文件夹）');
        return;
      }
      await Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (_) => CharacterImportScreen(
            entries: result.entries,
            zipName: result.name,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) _showTip(context, '导入失败：$e');
    }
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

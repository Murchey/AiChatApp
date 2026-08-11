import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/user.dart';
import '../providers/api_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/character_pack_picker.dart';
import 'api_settings_screen.dart';
import 'character_import_screen.dart';
import 'character_manage_screen.dart';
import 'profile_edit_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('我'),
      ),
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          final user = auth.user;
          final api = context.watch<ApiProvider>();
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
                    subtitle: Text(
                      '从 zip 文件导入角色',
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
                    subtitle: Text(
                      '深色模式与主题色',
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
                    subtitle: Text(
                      api.models.isEmpty
                          ? '未配置模型'
                          : '已配置 ${api.models.length} 个模型',
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
                          builder: (_) => const ApiSettingsScreen(),
                        ),
                      );
                    },
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
}

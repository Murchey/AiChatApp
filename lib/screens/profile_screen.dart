import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import 'profile_edit_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _editApiKey(BuildContext context, AuthProvider auth) {
    final controller = TextEditingController(text: auth.apiKey);
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('设置 API Key'),
        content: CupertinoTextField(
          controller: controller,
          placeholder: '输入你的 API Key',
          autofocus: true,
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              await auth.setApiKey(controller.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
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
                            const SizedBox(height: 4),
                            Text(
                              'ID: ${user?.id ?? '--'}',
                              style: TextStyle(
                                fontSize: 13,
                                color: context.textSecondaryColor,
                              ),
                            ),
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
              // 设置列表
              CupertinoListSection.insetGrouped(
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
                    title: const Text('设置 API Key'),
                    subtitle: Text(
                      auth.apiKey.isEmpty
                          ? '未设置'
                          : '已设置 (${auth.apiKey.length} 字符)',
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
                    onTap: () => _editApiKey(context, auth),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // 退出登录
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CupertinoButton(
                  color: CupertinoColors.systemRed,
                  borderRadius: BorderRadius.circular(12),
                  child: const Text(
                    '退出登录',
                    style: TextStyle(
                      color: CupertinoColors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () {
                    showCupertinoDialog(
                      context: context,
                      builder: (ctx) => CupertinoAlertDialog(
                        title: const Text('确认退出？'),
                        content: const Text('退出后需要重新设置昵称和 API Key'),
                        actions: [
                          CupertinoDialogAction(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('取消'),
                          ),
                          CupertinoDialogAction(
                            isDestructiveAction: true,
                            onPressed: () async {
                              await auth.logout();
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                                Navigator.pushNamedAndRemoveUntil(
                                  context,
                                  AppRoutes.splash,
                                  (route) => false,
                                );
                              }
                            },
                            child: const Text('退出'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
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

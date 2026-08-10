import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';

/// 用户资料卡编辑页（微信"个人信息"样式）
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final TextEditingController _nicknameController = TextEditingController();
  String? _newAvatarBase64; // 新选择的头像（未保存）

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _nicknameController.text = auth.user?.nickname ?? '';
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 500,
      maxHeight: 500,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _newAvatarBase64 = base64Encode(bytes);
    });
  }

  Future<void> _save() async {
    final auth = context.read<AuthProvider>();
    final nickname = _nicknameController.text.trim();
    if (nickname.isNotEmpty) {
      await auth.updateNickname(nickname);
    }
    if (_newAvatarBase64 != null) {
      await auth.updateAvatar(_newAvatarBase64!);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final avatarBase64 = _newAvatarBase64 ??
        (user != null && user.avatar.isNotEmpty ? user.avatar : null);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('个人信息'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _save,
          child: Text(
            '保存',
            style: TextStyle(
              color: context.accentColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      child: ListView(
        children: [
          const SizedBox(height: 12),
          // 头像（方形）
          CupertinoListSection.insetGrouped(
            children: [
              CupertinoListTile(
                title: const Text('头像'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSquareAvatar(avatarBase64, user?.nickname ?? '?'),
                    const SizedBox(width: 8),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: context.textSecondaryColor,
                    ),
                  ],
                ),
                onTap: _pickAvatar,
              ),
              CupertinoListTile(
                title: const Text('昵称'),
                trailing: SizedBox(
                  width: 180,
                  child: CupertinoTextField(
                    controller: _nicknameController,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 16,
                      color: context.textPrimaryColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // 微信号（ID）
          CupertinoListSection.insetGrouped(
            children: [
              CupertinoListTile(
                title: const Text('ID'),
                trailing: Text(
                  user?.id ?? '--',
                  style: TextStyle(
                    fontSize: 16,
                    color: context.textSecondaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSquareAvatar(String? avatarBase64, String fallback) {
    if (avatarBase64 != null && avatarBase64.isNotEmpty) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: context.accentColor.withValues(alpha: 0.15),
          image: DecorationImage(
            image: MemoryImage(base64Decode(avatarBase64)),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: context.accentColor.withValues(alpha: 0.15),
      ),
      alignment: Alignment.center,
      child: Text(
        fallback.isNotEmpty ? fallback[0] : '?',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: context.accentColor,
        ),
      ),
    );
  }
}

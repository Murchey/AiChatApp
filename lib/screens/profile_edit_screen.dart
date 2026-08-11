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
  static const List<String> _genderOptions = ['男', '女', '保密'];

  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _regionController = TextEditingController();
  final TextEditingController _signatureController = TextEditingController();
  String? _newAvatarBase64; // 新选择的头像（未保存）
  String? _gender; // 性别（未保存）

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    _nicknameController.text = user?.nickname ?? '';
    _regionController.text = user?.region ?? '';
    _signatureController.text = user?.signature ?? '';
    _gender = user?.gender ?? '';
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _regionController.dispose();
    _signatureController.dispose();
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

  /// 性别选择（底部弹层，微信样式）
  Future<void> _pickGender() async {
    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('选择性别'),
        actions: _genderOptions
            .map(
              (option) => CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(ctx, option),
                child: Text(
                  option,
                  style: TextStyle(
                    color: option == _gender
                        ? context.accentColor
                        : context.textPrimaryColor,
                  ),
                ),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _gender = selected;
      });
    }
  }

  /// 单行文本编辑弹窗（地区定位）
  Future<void> _editSingleLine({
    required String title,
    required String initial,
    required String hint,
    required void Function(String value) onSave,
  }) async {
    final controller = TextEditingController(text: initial);
    await showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: controller,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            placeholder: hint,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              onSave(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 多行文本编辑弹窗（个性签名）
  Future<void> _editMultiline({
    required String title,
    required String initial,
    required String hint,
    required void Function(String value) onSave,
  }) async {
    final controller = TextEditingController(text: initial);
    await showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: controller,
            maxLines: 4,
            minLines: 2,
            padding: const EdgeInsets.all(10),
            placeholder: hint,
            maxLength: 100,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              onSave(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final auth = context.read<AuthProvider>();
    await auth.updateProfile(
      nickname: _nicknameController.text,
      avatar: _newAvatarBase64,
      region: _regionController.text,
      signature: _signatureController.text,
      gender: _gender,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final avatarBase64 = _newAvatarBase64 ??
        (user != null && user.avatar.isNotEmpty ? user.avatar : null);
    final gender = _gender ?? '';

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
          // 头像 + 昵称
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
                trailing: Expanded(
                  child: CupertinoTextField(
                    controller: _nicknameController,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 16,
                      color: context.textPrimaryColor,
                    ),
                    decoration: null,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          // 性别 / 地区定位 / 个性签名
          CupertinoListSection.insetGrouped(
            children: [
              CupertinoListTile(
                title: const Text('性别'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      gender.isEmpty ? '未设置' : gender,
                      style: TextStyle(
                        fontSize: 16,
                        color: gender.isEmpty
                            ? context.textSecondaryColor.withValues(alpha: 0.6)
                            : context.textPrimaryColor,
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
                onTap: _pickGender,
              ),
              CupertinoListTile(
                title: const Text('地区定位'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        _regionController.text.isEmpty
                            ? '未设置'
                            : _regionController.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          color: _regionController.text.isEmpty
                              ? context.textSecondaryColor
                                  .withValues(alpha: 0.6)
                              : context.textPrimaryColor,
                        ),
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
                onTap: () => _editSingleLine(
                  title: '地区定位',
                  initial: _regionController.text,
                  hint: '例如：中国 · 上海',
                  onSave: (v) => setState(() => _regionController.text = v),
                ),
              ),
              CupertinoListTile(
                title: const Text('个性签名'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: Text(
                        _signatureController.text.isEmpty
                            ? '未设置'
                            : _signatureController.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          color: _signatureController.text.isEmpty
                              ? context.textSecondaryColor
                                  .withValues(alpha: 0.6)
                              : context.textPrimaryColor,
                        ),
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
                onTap: () => _editMultiline(
                  title: '个性签名',
                  initial: _signatureController.text,
                  hint: '一句话介绍自己',
                  onSave: (v) =>
                      setState(() => _signatureController.text = v),
                ),
              ),
            ],
          ),
          // 提示：资料会随对话一同发送给 AI
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(
              '以上个人信息会组成上下文随消息一同发送给 AI，帮助角色更了解你',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: context.textSecondaryColor,
              ),
            ),
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

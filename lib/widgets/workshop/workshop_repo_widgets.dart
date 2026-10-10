import '../secret_field.dart';
import 'package:flutter/cupertino.dart';

import '../../config/theme.dart';
import '../../models/workshop_repository.dart';
import '../../services/cos_auth.dart';
import '../../services/update_service.dart' show kProxySources;
import '../../services/workshop_service.dart';

/// 仓库可用 tag 标记
class TagChip extends StatelessWidget {
  final String text;
  final Color color;

  const TagChip({
    required this.text,
    this.color = const Color(0xFF34C759),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style:
            TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 添加 / 编辑仓库弹窗：来源类型 + 路径 +（Git）代理 /（COS）访问密钥
class AddRepoDialog extends StatefulWidget {
  final String title;
  final String? initialPath;
  final String? initialProxyUrl;
  final String initialType;
  final CosAuth initialCosAuth;

  const AddRepoDialog({
    this.title = '添加仓库',
    this.initialPath,
    this.initialProxyUrl,
    this.initialType = 'git',
    this.initialCosAuth = const CosAuth(),
  });

  @override
  State<AddRepoDialog> createState() => AddRepoDialogState();
}

class AddRepoDialogState extends State<AddRepoDialog> {
  late final TextEditingController _pathController;
  late final TextEditingController _akController;
  late final TextEditingController _skController;
  late String _proxyUrl; // 当前代理选择（空 = 不使用代理）
  late String _customProxy; // 用户输入的自定义代理
  late String _type; // 'git' | 'cos'
  late bool _useCosAuth;
  String? _hint;

  @override
  void initState() {
    super.initState();
    final initProxy = widget.initialProxyUrl ?? '';
    _pathController = TextEditingController(text: widget.initialPath ?? '');
    _akController =
        TextEditingController(text: widget.initialCosAuth.accessKeyId);
    _skController =
        TextEditingController(text: widget.initialCosAuth.secretAccessKey);
    _proxyUrl = initProxy;
    _type = widget.initialType == WorkshopRepoType.cos.name
        ? WorkshopRepoType.cos.name
        : WorkshopRepoType.git.name;
    _useCosAuth = widget.initialCosAuth.enabled;
    // 初始代理为自定义时，回填自定义输入框内容
    _customProxy = initProxy.isNotEmpty && !kProxySources.contains(initProxy)
        ? initProxy
        : '';
  }

  @override
  void dispose() {
    _pathController.dispose();
    _akController.dispose();
    _skController.dispose();
    super.dispose();
  }

  bool get _isCos => _type == WorkshopRepoType.cos.name;

  /// 输入完整 URL 时自动切换来源类型（粘贴 COS / GitHub / Gitee 链接）
  void _onPathChanged(String value) {
    if (_hint != null) setState(() => _hint = null);
    final s = value.trim();
    if (!s.contains('://')) return;
    final detected = WorkshopService.detectRepoType(s);
    if (detected.name != _type) {
      setState(() => _type = detected.name);
    }
  }

  String get _proxyLabel {
    if (_proxyUrl.isEmpty) return '不使用代理';
    final idx = kProxySources.indexOf(_proxyUrl);
    if (idx >= 0) return '代理 ${idx + 1}';
    return '自定义';
  }

  /// 弹出下载代理选择（底部弹层）：不使用代理 / 内置代理 / 自定义
  void _pickProxy() {
    final isCustom = _proxyUrl.isNotEmpty && !kProxySources.contains(_proxyUrl);
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('选择下载代理'),
        message: const Text('用于加速 GitHub 仓库资产下载，Gitee 仓库无需代理'),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction: _proxyUrl.isEmpty,
            onPressed: () {
              setState(() => _proxyUrl = '');
              Navigator.pop(ctx);
            },
            child: const Text('不使用代理'),
          ),
          for (var i = 0; i < kProxySources.length; i++)
            CupertinoActionSheetAction(
              isDefaultAction: _proxyUrl == kProxySources[i],
              onPressed: () {
                setState(() => _proxyUrl = kProxySources[i]);
                Navigator.pop(ctx);
              },
              child: Text('代理 ${i + 1}'),
            ),
          CupertinoActionSheetAction(
            isDefaultAction: isCustom,
            onPressed: () {
              Navigator.pop(ctx);
              _showCustomProxyDialog();
            },
            child: const Text('自定义'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  /// 自定义代理源输入弹窗
  void _showCustomProxyDialog() {
    final controller = TextEditingController(text: _customProxy);
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('自定义代理源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Text(
              '请输入代理源 URL 前缀',
              style: TextStyle(
                fontSize: 13,
                color: ctx.isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: controller,
              placeholder: 'https://example.com/',
              autofocus: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                setState(() {
                  _customProxy = url;
                  _proxyUrl = url;
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      setState(() => _hint = _isCos ? '请输入 BASE_URL' : '请输入仓库路径');
      return;
    }
    if (_isCos) {
      if (!path.toLowerCase().startsWith('https://')) {
        setState(() => _hint = 'COS 来源必须使用 https:// 完整 BASE_URL');
        return;
      }
      if (!WorkshopService.looksLikeCosUrl(path)) {
        setState(() => _hint = '该 URL 看起来是 GitHub / Gitee，请切换到 Git 来源');
        return;
      }
      if (_useCosAuth) {
        final ak = _akController.text.trim();
        final sk = _skController.text.trim();
        if (ak.isEmpty || sk.isEmpty) {
          setState(() => _hint = '启用访问密钥时，请填写 AccessKey ID 与 Secret');
          return;
        }
      }
    } else {
      // Git 类型：若填了完整 URL 且像 COS，提示类型不匹配
      if (path.contains('://') && WorkshopService.looksLikeCosUrl(path)) {
        setState(() => _hint = '该 URL 看起来是对象储存，请切换到「对象储存」来源');
        return;
      }
    }
    Navigator.pop(
      context,
      (
        path: path,
        proxyUrl: _proxyUrl,
        type: _type,
        cosAuth: CosAuth(
          enabled: _isCos && _useCosAuth,
          accessKeyId: _isCos && _useCosAuth ? _akController.text.trim() : '',
          secretAccessKey:
              _isCos && _useCosAuth ? _skController.text.trim() : '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.55,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // 来源类型
              Text(
                '来源类型',
                textAlign: TextAlign.start,
                style: TextStyle(
                  fontSize: 13,
                  color: context.textSecondaryColor,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: CupertinoSegmentedControl<String>(
                  children: {
                    WorkshopRepoType.git.name: const Text('Git'),
                    WorkshopRepoType.cos.name: const Text('对象储存'),
                  },
                  groupValue: _type,
                  onValueChanged: (v) => setState(() {
                    _type = v;
                    _hint = null;
                  }),
                ),
              ),
              const SizedBox(height: 10),
              if (_isCos) ...[
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    '填写对象储存 BASE_URL。目录约定：\n'
                    'Characters/*.zip — 角色\n'
                    'Games/*.zip — 朋友圈\n'
                    'Stickers/*.zip — 表情包\n'
                    'Note/*.md — 更新通知',
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: context.textPrimaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // 私有读：访问密钥
                SizedBox(
                  width: double.infinity,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '使用访问密钥（私有读）',
                          style: TextStyle(
                            fontSize: 15,
                            color: context.textPrimaryColor,
                          ),
                        ),
                      ),
                      CupertinoSwitch(
                        value: _useCosAuth,
                        onChanged: (v) => setState(() => _useCosAuth = v),
                      ),
                    ],
                  ),
                ),
                if (_useCosAuth) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      '桶为私有读时填写。密钥仅保存在本机，用于 List/Get 签名。',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SecretField(
                      controller: _akController,
                      builder: (revealed) => CupertinoTextField(
                        controller: _akController,
                        placeholder: 'AccessKey ID',
                        obscureText: !revealed,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        onChanged: (_) {
                          if (_hint != null) setState(() => _hint = null);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SecretField(
                        controller: _skController,
                        enabled: true,
                        builder: (revealed) => CupertinoTextField(
                              controller: _skController,
                              placeholder: 'SecretAccessKey',
                              obscureText: true && !revealed,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              onChanged: (_) {
                                if (_hint != null) setState(() => _hint = null);
                              },
                            )),
                  ),
                ],
                const SizedBox(height: 10),
              ] else ...[
                // 下载代理选项（仅 Git）
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _pickProxy,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Text(
                            '下载代理',
                            style: TextStyle(
                              fontSize: 15,
                              color: context.textPrimaryColor,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _proxyLabel,
                            style: TextStyle(
                              fontSize: 13,
                              color: context.textSecondaryColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            CupertinoIcons.chevron_down,
                            size: 14,
                            color: context.textSecondaryColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              // 仓库路径 / BASE_URL
              SizedBox(
                width: double.infinity,
                child: CupertinoTextField(
                  controller: _pathController,
                  autofocus: true,
                  placeholder: _isCos
                      ? 'https://bucket.example.com/aichat'
                      : 'owner/repo 或仓库 URL',
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  onChanged: _onPathChanged,
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: Text(
                  _hint ??
                      (_isCos
                          ? '例如：https://bucket.cos.ap-xxx.myqcloud.com/aichat'
                          : '例如：Murchey/AiChatCharacterCommunity'),
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize: 12,
                    color: _hint != null
                        ? CupertinoColors.systemRed
                        : context.textSecondaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

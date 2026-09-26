import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../providers/api_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/auto_moment_provider.dart';
import '../providers/character_provider.dart';
import '../providers/chat_background_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/group_chat_provider.dart';
import '../providers/memory_point_provider.dart';
import '../providers/moment_notification_provider.dart';
import '../providers/proactive_greeting_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sticker_provider.dart';
import '../providers/token_usage_provider.dart';
import '../providers/workshop_provider.dart';
import '../services/backup_service.dart';
import '../utils/app_toast.dart';
import '../utils/file_picker_helper.dart';

/// 数据备份页：本地备份 + 导出 / 导入 + 恢复。
///
/// 从「设置 → 存储 → 数据备份」进入，对齐 inkqilin-ledger 本地备份能力：
/// 立即备份（可选密码加密）、导入备份文件、导出到系统文件、
/// 从备份恢复、从安全副本恢复。
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  List<File> _backups = [];
  bool _loading = true;
  bool _working = false;
  String? _status;
  bool _statusIsError = false;
  String? _lastBackupInfo;
  bool _hasSafety = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final backups = await BackupService.listLocalBackups();
      final safety = await BackupService.hasSafetyCopy();
      if (!mounted) return;
      setState(() {
        _backups = backups;
        _hasSafety = safety;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _setStatus('加载备份列表失败：$e', isError: true);
    }
  }

  void _setStatus(String message, {bool isError = false}) {
    setState(() {
      _status = message;
      _statusIsError = isError;
    });
  }

  void _clearStatus() {
    setState(() => _status = null);
  }

  String _formatTime(File f) {
    final t = f.lastModifiedSync();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  // ─── 立即备份 ───────────────────────────────────────────────

  Future<void> _onBackupNow() async {
    final password = await _askPassword(
      title: '本地备份',
      message: '打包全部聊天、角色、设置与用户文件保存到应用私有目录。\n'
          '卸载应用会丢失，重要备份请再「导出」到文件。\n'
          '可设置密码加密备份包（留空则不加密）。',
      requireConfirm: true,
    );
    if (password == null) return; // 取消
    setState(() => _working = true);
    _clearStatus();
    try {
      final file = await BackupService.createLocalBackup(
        password: password.isEmpty ? null : password,
      );
      if (!mounted) return;
      setState(() {
        _lastBackupInfo =
            '上次备份：${_formatTime(file)} · ${BackupService.formatSize(file.lengthSync())}'
            '${password.isEmpty ? '' : ' · 已加密'}';
        _working = false;
      });
      await _refresh();
      _setStatus('本地备份成功：${file.path.split(RegExp(r'[/\\]')).last}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      _setStatus('备份失败：$e', isError: true);
    }
  }

  // ─── 导出到系统文件 ─────────────────────────────────────────

  Future<void> _onExport(File file) async {
    setState(() => _working = true);
    _clearStatus();
    try {
      final name = file.path.split(RegExp(r'[/\\]')).last;
      final saved = await FilePickerHelper.saveFileFromPath(
        suggestedName: name,
        sourcePath: file.path,
        mimeType: 'application/zip',
      );
      if (!mounted) return;
      setState(() => _working = false);
      if (saved == null) return;
      _setStatus('已导出到所选位置：$saved');
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      _setStatus('导出失败：$e', isError: true);
    }
  }

  // ─── 从文件导入 ─────────────────────────────────────────────

  Future<void> _onImport() async {
    final picked = await FilePickerHelper.pickFile();
    if (picked == null || !mounted) return;
    setState(() => _working = true);
    _clearStatus();
    try {
      final file = await BackupService.importBackupFromPath(
        picked.path,
        displayName: picked.name,
      );
      if (!mounted) return;
      setState(() => _working = false);
      await _refresh();
      _setStatus(
        '已导入：${file.path.split(RegExp(r'[/\\]')).last}，可在列表中恢复',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      _setStatus('导入失败：$e', isError: true);
    }
  }

  // ─── 恢复 ───────────────────────────────────────────────────

  Future<void> _onRestore(File file) async {
    final name = file.path.split(RegExp(r'[/\\]')).last;
    final encrypted = BackupService.isLocalBackupEncrypted(file);
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('恢复将覆盖当前数据'),
        content: Text(
          '将使用备份「$name」替换本地全部聊天、角色、设置与用户文件。\n\n'
          '恢复完成后需要重新打开应用以加载新数据。',
          textAlign: TextAlign.left,
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('我明白，继续'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    String? password;
    if (encrypted) {
      password = await _askPassword(
        title: '输入备份密码',
        message: '此备份已加密，请输入备份密码。',
        requireConfirm: false,
      );
      if (password == null) return;
      if (password.isEmpty) {
        _setStatus('请输入备份密码', isError: true);
        return;
      }
    } else {
      password = await _askPassword(
        title: '输入备份密码',
        message: '若为加密备份请填写密码；未加密可留空。',
        requireConfirm: false,
      );
      if (password == null) return;
    }

    setState(() => _working = true);
    _clearStatus();
    try {
      await BackupService.restoreLocalBackup(
        file,
        password: password.isEmpty ? null : password,
      );
      await _reloadAllProviders();
      if (!mounted) return;
      setState(() => _working = false);
      await _refresh();
      if (!mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('恢复完成'),
          content: const Text(
            '数据与设置已从备份恢复。\n\n'
            '建议关闭应用后重新打开，以确保全部界面加载新数据。',
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      _setStatus('恢复失败：$e', isError: true);
    }
  }

  Future<void> _onRestoreSafety() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('从安全副本恢复'),
        content: const Text(
          '将用最近一次「恢复操作前」自动保存的设置快照覆盖当前设置。\n\n'
          '仅当你确认当前设置异常时使用。文件数据不会回滚。',
          textAlign: TextAlign.left,
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('覆盖设置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    _clearStatus();
    try {
      await BackupService.restoreFromSafetyCopy();
      await _reloadAllProviders();
      if (!mounted) return;
      setState(() => _working = false);
      _setStatus('已从安全副本恢复设置');
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      _setStatus('安全副本恢复失败：$e', isError: true);
    }
  }

  Future<void> _onDelete(File file) async {
    final name = file.path.split(RegExp(r'[/\\]')).last;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除本地备份'),
        content: Text('确定删除 $name？此操作不可撤销。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    final ok = await BackupService.deleteLocalBackup(file);
    if (!mounted) return;
    setState(() => _working = false);
    await _refresh();
    _setStatus(ok ? '已彻底删除本地备份' : '本地备份删除失败，请重试', isError: !ok);
  }

  Future<void> _onShowFileInfo() async {
    final text = await BackupService.describeLocalBackupFiles();
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('本机备份相关文件'),
        content: Text(text, textAlign: TextAlign.left),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 返回密码；取消返回 null。[requireConfirm] 时要求两次输入一致。
  Future<String?> _askPassword({
    required String title,
    required String message,
    required bool requireConfirm,
  }) {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    return showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message, textAlign: TextAlign.left),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: controller,
              placeholder: '备份密码（可留空）',
              obscureText: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            if (requireConfirm) ...[
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: confirmController,
                placeholder: '确认密码',
                obscureText: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ],
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
              final pwd = controller.text;
              if (requireConfirm && pwd != confirmController.text) {
                showAppToast('两次输入的密码不一致');
                return;
              }
              Navigator.pop(ctx, pwd);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 恢复后刷新各 Provider，让界面立即显示新数据。
  Future<void> _reloadAllProviders() async {
    final settings = context.read<SettingsProvider>();
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    final character = context.read<CharacterProvider>();
    final group = context.read<GroupChatProvider>();
    final api = context.read<ApiProvider>();
    final chatSettings = context.read<ChatSettingsProvider>();
    final notification = context.read<MomentNotificationProvider>();
    final memory = context.read<MemoryPointProvider>();
    final autoMoment = context.read<AutoMomentProvider>();
    final proactive = context.read<ProactiveGreetingProvider>();
    final workshop = context.read<WorkshopProvider>();
    final sticker = context.read<StickerProvider>();
    final chatBg = context.read<ChatBackgroundProvider>();

    await settings.init();
    await auth.init();
    await chat.init();
    await character.loadCharacters();
    await group.init();
    await api.init();
    await chatSettings.init();
    await notification.init();
    await memory.reload();
    await autoMoment.init();
    await proactive.init();
    await workshop.init();
    await sticker.init();
    await TokenUsageProvider.instance.reload();
    chatBg.clearCache();
  }

  // ─── UI ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('数据备份'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              '打包应用内全部聊天、角色、表情包、设置与用户文件。'
              '备份保存在应用私有目录，卸载会丢失；重要备份请「导出」到系统文件。',
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
                height: 1.5,
              ),
            ),
            if (_lastBackupInfo != null) ...[
              const SizedBox(height: 8),
              Text(
                _lastBackupInfo!,
                style: TextStyle(
                  fontSize: 12,
                  color: context.accentColor,
                ),
              ),
            ],
            if (_working) ...[
              const SizedBox(height: 12),
              const CupertinoActivityIndicator(),
              const SizedBox(height: 8),
              Text(
                '处理中…',
                style: TextStyle(
                  fontSize: 12,
                  color: context.textSecondaryColor,
                ),
              ),
            ],
            if (_status != null) ...[
              const SizedBox(height: 10),
              Text(
                _status!,
                style: TextStyle(
                  fontSize: 12,
                  color: _statusIsError
                      ? CupertinoColors.destructiveRed
                      : context.accentColor,
                ),
              ),
            ],
            const SizedBox(height: 16),
            _section(
              title: '操作',
              children: [
                _actionTile(
                  icon: CupertinoIcons.archivebox_fill,
                  title: '立即备份',
                  subtitle: '生成本地备份，可选密码加密',
                  onTap: _working ? null : _onBackupNow,
                ),
                _actionTile(
                  icon: CupertinoIcons.square_arrow_down_fill,
                  title: '导入备份文件',
                  subtitle: '从系统文件选择 zip / 加密备份包',
                  onTap: _working ? null : _onImport,
                ),
                _actionTile(
                  icon: CupertinoIcons.info_circle_fill,
                  title: '文件信息',
                  subtitle: '查看本机备份与安全副本',
                  onTap: _onShowFileInfo,
                ),
                _actionTile(
                  icon: CupertinoIcons.shield_lefthalf_fill,
                  title: '从安全副本恢复设置',
                  subtitle: '仅恢复设置快照；无副本时不可用',
                  enabled: _hasSafety && !_working,
                  onTap: _onRestoreSafety,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _section(
              title: '本地备份列表',
              children: [
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: CupertinoActivityIndicator(),
                  )
                else if (_backups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      '暂无本地备份，点击「立即备份」创建',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  )
                else
                  for (final file in _backups)
                    _backupTile(file),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: context.textSecondaryColor,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.listBgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    bool enabled = true,
  }) {
    final muted = !enabled || onTap == null;
    return CupertinoListTile(
      leading: Icon(
        icon,
        color: muted ? context.textSecondaryColor : context.accentColor,
      ),
      title: Text(title),
      subtitle: Text(
        subtitle,
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
      onTap: muted ? null : onTap,
    );
  }

  Widget _backupTile(File file) {
    final name = file.path.split(RegExp(r'[/\\]')).last;
    final encrypted = BackupService.isLocalBackupEncrypted(file);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    color: context.textPrimaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (encrypted)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '加密',
                    style: TextStyle(
                      fontSize: 10,
                      color: context.accentColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatTime(file)} · ${BackupService.formatSize(file.lengthSync())}',
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _miniButton(
                label: '恢复',
                destructive: true,
                onTap: _working ? null : () => _onRestore(file),
              ),
              _miniButton(
                label: '导出',
                onTap: _working ? null : () => _onExport(file),
              ),
              _miniButton(
                label: '删除',
                destructive: true,
                onTap: _working ? null : () => _onDelete(file),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniButton({
    required String label,
    required VoidCallback? onTap,
    bool destructive = false,
  }) {
    final color = destructive
        ? CupertinoColors.destructiveRed
        : context.accentColor;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      minimumSize: const Size(0, 32),
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      onPressed: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

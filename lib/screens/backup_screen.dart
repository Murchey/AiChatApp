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
import '../services/backup_schedule_service.dart';
import '../services/backup_service.dart';
import '../services/cloud_backup_service.dart';
import '../utils/app_toast.dart';
import '../utils/file_picker_helper.dart';

/// 数据备份页：本地备份 + 云端备份（腾讯云 COS / 阿里云 OSS）。
///
/// 从「设置 → 存储 → 数据备份」进入，对齐 inkqilin-ledger：
/// 立即备份（可选密码加密）、导入/导出、恢复、安全副本；
/// 云端支持上传、列表、下载恢复、删除与对象储存配置。
/// 本地 / 云端定时备份策略分开配置。
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  int _tab = 0; // 0=本地 1=云端

  // 本地
  List<File> _backups = [];
  String? _lastLocalInfo;
  bool _hasSafety = false;
  BackupScheduleConfig _localSchedule = const BackupScheduleConfig();
  DateTime? _lastLocalAuto;

  // 云端
  CloudBackupConfig _cloudConfig = const CloudBackupConfig();
  List<CloudBackupItem> _cloudBackups = [];
  String? _lastCloudInfo;
  bool _loadingCloud = false;
  BackupScheduleConfig _cloudSchedule = const BackupScheduleConfig();
  DateTime? _lastCloudAuto;

  bool _loading = true;
  bool _working = false;
  String? _status;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() => _loading = true);
    try {
      final backups = await BackupService.listLocalBackups();
      final safety = await BackupService.hasSafetyCopy();
      final config = await CloudBackupService.loadConfig();
      final localSchedule = await BackupScheduleService.loadLocal();
      final cloudSchedule = await BackupScheduleService.loadCloud();
      final lastLocalAuto = await BackupScheduleService.lastLocalRun();
      final lastCloudAuto = await BackupScheduleService.lastCloudRun();
      if (!mounted) return;
      setState(() {
        _backups = backups;
        _hasSafety = safety;
        _cloudConfig = config;
        _localSchedule = localSchedule;
        _cloudSchedule = cloudSchedule;
        _lastLocalAuto = lastLocalAuto;
        _lastCloudAuto = lastCloudAuto;
        _loading = false;
      });
      if (config.isConfigured) {
        await _refreshCloud(silent: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _setStatus('加载备份失败：$e', isError: true);
    }
  }

  Future<void> _refreshCloud({bool silent = false}) async {
    if (!_cloudConfig.isConfigured) {
      setState(() => _cloudBackups = []);
      return;
    }
    if (!silent) setState(() => _loadingCloud = true);
    try {
      final items = await CloudBackupService.listBackups(_cloudConfig);
      if (!mounted) return;
      setState(() {
        _cloudBackups = items;
        _loadingCloud = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingCloud = false);
      if (!silent) _setStatus('加载云端列表失败：$e', isError: true);
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

  String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  String _fileTime(File f) => _formatTime(f.lastModifiedSync());

  // ─── 立即备份（本地 / 云端共用密码弹窗） ─────────────────────

  Future<void> _onBackupNow({required bool cloud}) async {
    final title = cloud ? '云端备份' : '本地备份';
    final message = cloud
        ? '打包全部数据并上传到对象储存。\n'
            '可设置密码加密备份包（留空则不加密）。'
        : '打包全部聊天、角色、设置与用户文件保存到应用私有目录。\n'
            '卸载应用会丢失，重要备份请再「导出」到文件。\n'
            '可设置密码加密备份包（留空则不加密）。';
    final password = await _askPassword(
      title: title,
      message: message,
      requireConfirm: true,
    );
    if (password == null) return;
    setState(() => _working = true);
    _clearStatus();
    try {
      final encryptedTag = password.isEmpty ? '' : ' · 已加密';
      if (cloud) {
        final item = await CloudBackupService.uploadBackup(
          _cloudConfig,
          password: password.isEmpty ? null : password,
        );
        if (!mounted) return;
        setState(() {
          _lastCloudInfo =
              '上次云备份：${_formatTime(DateTime.now())} · ${BackupService.formatSize(item.size)}$encryptedTag';
          _working = false;
        });
        await _refreshCloud();
        _setStatus('云备份成功：${item.fileName}');
      } else {
        final file = await BackupService.createLocalBackup(
          password: password.isEmpty ? null : password,
        );
        if (!mounted) return;
        setState(() {
          _lastLocalInfo =
              '上次备份：${_fileTime(file)} · ${BackupService.formatSize(file.lengthSync())}$encryptedTag';
          _working = false;
        });
        await _refreshAll();
        _setStatus(
          '本地备份成功：${file.path.split(RegExp(r'[/\\]')).last}',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      _setStatus('备份失败：$e', isError: true);
    }
  }

  // ─── 本地：导出 / 导入 ──────────────────────────────────────

  Future<void> _onExportLocal(File file) async {
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

  Future<void> _onImportLocal() async {
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
      await _refreshAll();
      _setStatus(
        '已导入：${file.path.split(RegExp(r'[/\\]')).last}，可在列表中恢复',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      _setStatus('导入失败：$e', isError: true);
    }
  }

  // ─── 恢复（本地 / 云端） ────────────────────────────────────

  Future<void> _confirmAndRestore({
    required String label,
    required Future<void> Function(String? password) restore,
    required bool looksEncrypted,
  }) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('恢复将覆盖当前数据'),
        content: Text(
          '将使用备份「$label」替换本地全部聊天、角色、设置与用户文件。\n\n'
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

    final password = await _askPassword(
      title: '输入备份密码',
      message: looksEncrypted
          ? '此备份已加密，请输入备份密码。'
          : '若为加密备份请填写密码；未加密可留空。',
      requireConfirm: false,
    );
    if (password == null) return;
    if (looksEncrypted && password.isEmpty) {
      _setStatus('请输入备份密码', isError: true);
      return;
    }

    setState(() => _working = true);
    _clearStatus();
    try {
      await restore(password.isEmpty ? null : password);
      await _reloadAllProviders();
      if (!mounted) return;
      setState(() => _working = false);
      await _refreshAll();
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

  Future<void> _onRestoreLocal(File file) async {
    final name = file.path.split(RegExp(r'[/\\]')).last;
    final encrypted = BackupService.isLocalBackupEncrypted(file);
    await _confirmAndRestore(
      label: name,
      looksEncrypted: encrypted,
      restore: (pwd) => BackupService.restoreLocalBackup(
        file,
        password: pwd,
      ),
    );
  }

  Future<void> _onRestoreCloud(CloudBackupItem item) async {
    final encrypted = item.fileName.contains('_enc') ||
        item.key.toLowerCase().endsWith('.aibackup');
    await _confirmAndRestore(
      label: item.fileName,
      looksEncrypted: encrypted,
      restore: (pwd) => CloudBackupService.downloadAndRestore(
        _cloudConfig,
        item.key,
        password: pwd,
      ),
    );
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

  // ─── 删除 ───────────────────────────────────────────────────

  Future<void> _onDeleteLocal(File file) async {
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
    await _refreshAll();
    _setStatus(ok ? '已彻底删除本地备份' : '本地备份删除失败，请重试', isError: !ok);
  }

  Future<void> _onDeleteCloud(CloudBackupItem item) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除云端备份'),
        content: Text('确定删除 ${item.fileName}？此操作不可撤销。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
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
    setState(() => _working = true);
    _clearStatus();
    try {
      await CloudBackupService.deleteBackup(_cloudConfig, item.key);
      if (!mounted) return;
      setState(() => _working = false);
      await _refreshCloud();
      _setStatus('已删除云端备份');
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      _setStatus('删除失败：$e', isError: true);
    }
  }

  // ─── 其它 ───────────────────────────────────────────────────

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

  Future<void> _onOpenCloudSettings() async {
    final saved = await showCupertinoDialog<CloudBackupConfig>(
      context: context,
      builder: (ctx) => _CloudSettingsDialog(initial: _cloudConfig),
    );
    if (saved == null || !mounted) return;
    setState(() => _working = true);
    try {
      await CloudBackupService.saveConfig(saved);
      if (!mounted) return;
      setState(() {
        _cloudConfig = saved;
        _working = false;
      });
      _setStatus('对象储存配置已保存');
      if (saved.isConfigured) await _refreshCloud();
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      _setStatus('保存配置失败：$e', isError: true);
    }
  }

  // ─── 定时备份 ───────────────────────────────────────────────

  Future<void> _onEditSchedule({required bool cloud}) async {
    final current = cloud ? _cloudSchedule : _localSchedule;
    final saved = await showCupertinoDialog<BackupScheduleConfig>(
      context: context,
      builder: (ctx) => _SchedulePickerDialog(
        title: cloud ? '云端定时备份' : '本地定时备份',
        initial: current,
      ),
    );
    if (saved == null || !mounted) return;
    setState(() => _working = true);
    try {
      if (cloud) {
        await BackupScheduleService.saveCloud(saved);
      } else {
        await BackupScheduleService.saveLocal(saved);
      }
      if (!mounted) return;
      setState(() {
        if (cloud) {
          _cloudSchedule = saved;
        } else {
          _localSchedule = saved;
        }
        _working = false;
      });
      _setStatus(
        '${cloud ? '云端' : '本地'}定时备份已设为：${saved.describe()}',
      );
      // 刚开启时若已到期，立即补一次，方便验证
      if (saved.enabled) {
        final messages = await BackupScheduleService.checkAndRunNow(
          local: !cloud,
          cloud: cloud,
        );
        if (!mounted) return;
        if (messages.isNotEmpty) {
          _setStatus(messages.join('；'));
        }
        await _refreshAll();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      _setStatus('保存定时备份失败：$e', isError: true);
    }
  }

  Widget _scheduleTile({
    required bool cloud,
  }) {
    final config = cloud ? _cloudSchedule : _localSchedule;
    final last = cloud ? _lastCloudAuto : _lastLocalAuto;
    final lastText = last == null ? '尚未自动备份' : '上次自动：${_formatTime(last)}';
    final extras = [
      if (config.deletePrevious) '覆盖上次自动备份',
      if (config.encryptEnabled) '自动加密',
    ];
    final extrasText = extras.isEmpty ? '' : ' · ${extras.join(' · ')}';
    final subtitle = config.enabled
        ? '${config.describe()}$extrasText · $lastText'
        : '已关闭 · $lastText';
    return _actionTile(
      icon: CupertinoIcons.clock_fill,
      title: cloud ? '云端定时备份' : '本地定时备份',
      subtitle: subtitle,
      enabled: !_working,
      onTap: () => _onEditSchedule(cloud: cloud),
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
      navigationBar: CupertinoNavigationBar(
        middle: const Text('数据备份'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _onOpenCloudSettings,
          child: const Icon(CupertinoIcons.gear, size: 22),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: CupertinoSegmentedControl<int>(
                groupValue: _tab,
                children: const {
                  0: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    child: Text('本地备份'),
                  ),
                  1: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    child: Text('云端备份'),
                  ),
                },
                onValueChanged: (v) => setState(() => _tab = v),
              ),
            ),
            if (_working) ...[
              const SizedBox(height: 12),
              const CupertinoActivityIndicator(),
            ],
            if (_status != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  _status!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _statusIsError
                        ? CupertinoColors.destructiveRed
                        : context.accentColor,
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CupertinoActivityIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [
                        if (_tab == 0) _buildLocalTab() else _buildCloudTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
        if (_lastLocalInfo != null) ...[
          const SizedBox(height: 8),
          Text(
            _lastLocalInfo!,
            style: TextStyle(fontSize: 12, color: context.accentColor),
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
              onTap: _working ? null : () => _onBackupNow(cloud: false),
            ),
            _actionTile(
              icon: CupertinoIcons.square_arrow_down_fill,
              title: '导入备份文件',
              subtitle: '从系统文件选择 zip / 加密备份包',
              onTap: _working ? null : _onImportLocal,
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
            _scheduleTile(cloud: false),
          ],
        ),
        const SizedBox(height: 16),
        _section(
          title: '本地备份列表',
          children: [
            if (_backups.isEmpty)
              _emptyHint('暂无本地备份，点击「立即备份」创建')
            else
              for (final file in _backups) _localBackupTile(file),
          ],
        ),
      ],
    );
  }

  Widget _buildCloudTab() {
    final configured = _cloudConfig.isConfigured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          configured
              ? '${_cloudConfig.vendorLabel} · ${_cloudConfig.host}\n'
                  '对象前缀：${_cloudConfig.normalizedPrefix}'
              : '未配置对象储存（点右上角齿轮填写密钥与存储桶 URL）。\n'
                  '支持腾讯云 COS 与阿里云 OSS 私有读写。',
          style: TextStyle(
            fontSize: 12,
            color: context.textSecondaryColor,
            height: 1.5,
          ),
        ),
        if (_lastCloudInfo != null) ...[
          const SizedBox(height: 8),
          Text(
            _lastCloudInfo!,
            style: TextStyle(fontSize: 12, color: context.accentColor),
          ),
        ],
        const SizedBox(height: 16),
        _section(
          title: '操作',
          children: [
            _actionTile(
              icon: CupertinoIcons.cloud_upload_fill,
              title: '立即云备份',
              subtitle: '打包并上传到对象储存',
              enabled: configured && !_working,
              onTap: () => _onBackupNow(cloud: true),
            ),
            _actionTile(
              icon: CupertinoIcons.arrow_clockwise,
              title: '刷新云端列表',
              subtitle: configured ? '重新拉取云端备份' : '配置后可刷新',
              enabled: configured && !_working,
              onTap: () => _refreshCloud(),
            ),
            _actionTile(
              icon: CupertinoIcons.gear_alt_fill,
              title: '对象储存设置',
              subtitle: 'SecretId / SecretKey / 存储桶 URL',
              onTap: _onOpenCloudSettings,
            ),
            _scheduleTile(cloud: true),
          ],
        ),
        const SizedBox(height: 16),
        _section(
          title: '云端备份列表',
          children: [
            if (!configured)
              _emptyHint('尚未配置对象储存，请点右上角齿轮设置')
            else if (_loadingCloud)
              const Padding(
                padding: EdgeInsets.all(20),
                child: CupertinoActivityIndicator(),
              )
            else if (_cloudBackups.isEmpty)
              _emptyHint('还没有云备份，点「立即云备份」创建第一份')
            else
              for (final item in _cloudBackups) _cloudBackupTile(item),
          ],
        ),
      ],
    );
  }

  Widget _emptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: context.textSecondaryColor,
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

  Widget _localBackupTile(File file) {
    final name = file.path.split(RegExp(r'[/\\]')).last;
    final encrypted = BackupService.isLocalBackupEncrypted(file);
    return _backupTileBody(
      title: name,
      meta: '${_fileTime(file)} · ${BackupService.formatSize(file.lengthSync())}',
      encrypted: encrypted,
      actions: [
        _miniButton(
          label: '恢复',
          destructive: true,
          onTap: _working ? null : () => _onRestoreLocal(file),
        ),
        _miniButton(
          label: '导出',
          onTap: _working ? null : () => _onExportLocal(file),
        ),
        _miniButton(
          label: '删除',
          destructive: true,
          onTap: _working ? null : () => _onDeleteLocal(file),
        ),
      ],
    );
  }

  Widget _cloudBackupTile(CloudBackupItem item) {
    final encrypted = item.fileName.contains('_enc') ||
        item.key.toLowerCase().endsWith('.aibackup');
    final time = item.lastModified.length >= 19
        ? item.lastModified.substring(0, 19).replaceFirst('T', ' ')
        : item.lastModified;
    return _backupTileBody(
      title: item.fileName,
      meta: '${BackupService.formatSize(item.size)} · $time',
      encrypted: encrypted,
      actions: [
        _miniButton(
          label: '恢复',
          destructive: true,
          onTap: _working ? null : () => _onRestoreCloud(item),
        ),
        _miniButton(
          label: '删除',
          destructive: true,
          onTap: _working ? null : () => _onDeleteCloud(item),
        ),
      ],
    );
  }

  Widget _backupTileBody({
    required String title,
    required String meta,
    required bool encrypted,
    required List<Widget> actions,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
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
            meta,
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
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

/// 对象储存配置弹窗（腾讯云 COS / 阿里云 OSS）
class _CloudSettingsDialog extends StatefulWidget {
  final CloudBackupConfig initial;

  const _CloudSettingsDialog({required this.initial});

  @override
  State<_CloudSettingsDialog> createState() => _CloudSettingsDialogState();
}

class _CloudSettingsDialogState extends State<_CloudSettingsDialog> {
  late final TextEditingController _secretId;
  late final TextEditingController _secretKey;
  late final TextEditingController _bucketUrl;
  late final TextEditingController _prefix;

  @override
  void initState() {
    super.initState();
    _secretId = TextEditingController(text: widget.initial.secretId);
    _secretKey = TextEditingController(text: widget.initial.secretKey);
    _bucketUrl = TextEditingController(text: widget.initial.bucketUrl);
    _prefix = TextEditingController(text: widget.initial.prefix);
  }

  @override
  void dispose() {
    _secretId.dispose();
    _secretKey.dispose();
    _bucketUrl.dispose();
    _prefix.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: const Text('对象储存设置'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '私有读写需要访问密钥。密钥仅保存在本机，请使用子账号并仅授权该存储桶。\n'
            '支持腾讯云 COS 与阿里云 OSS。',
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 12),
          CupertinoTextField(
            controller: _secretId,
            placeholder: 'SecretId / AccessKey ID',
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          const SizedBox(height: 8),
          CupertinoTextField(
            controller: _secretKey,
            placeholder: 'SecretKey / AccessKey Secret',
            obscureText: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          const SizedBox(height: 8),
          CupertinoTextField(
            controller: _bucketUrl,
            placeholder: 'https://xxx-1250000000.cos.ap-guangzhou.myqcloud.com',
            keyboardType: TextInputType.url,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          const SizedBox(height: 8),
          CupertinoTextField(
            controller: _prefix,
            placeholder: '对象前缀（默认 backups/v1）',
            keyboardType: TextInputType.url,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          const SizedBox(height: 8),
          Text(
            '存储桶 URL 可从控制台复制默认访问域名；对象前缀用于隔离备份目录。',
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 11,
              color: context.textSecondaryColor,
            ),
          ),
        ],
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () {
            final url =
                CloudBackupService.normalizeBucketUrl(_bucketUrl.text);
            Navigator.pop(
              context,
              CloudBackupConfig(
                secretId: _secretId.text.trim(),
                secretKey: _secretKey.text.trim(),
                bucketUrl: url,
                prefix: _prefix.text.trim(),
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 定时备份策略弹窗：触发方式 / 每周日 / 每月日 / 覆盖上次自动备份 / 预设密码
class _SchedulePickerDialog extends StatefulWidget {
  final String title;
  final BackupScheduleConfig initial;

  const _SchedulePickerDialog({
    required this.title,
    required this.initial,
  });

  @override
  State<_SchedulePickerDialog> createState() => _SchedulePickerDialogState();
}

class _SchedulePickerDialogState extends State<_SchedulePickerDialog> {
  late BackupScheduleMode _mode;
  late int _weeklyDay;
  late int _monthlyDay;
  late bool _deletePrevious;
  late final TextEditingController _password;

  @override
  void initState() {
    super.initState();
    _mode = widget.initial.mode;
    _weeklyDay = widget.initial.weeklyDay;
    _monthlyDay = widget.initial.monthlyDay;
    _deletePrevious = widget.initial.deletePrevious;
    _password = TextEditingController(text: widget.initial.password);
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '定时在打开 APP 时触发。自动备份文件名以 aichat_auto 开头，与手动备份区分。',
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 12),
          _label('触发方式'),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: context.listBgColor.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                for (final m in [
                  BackupScheduleMode.onAppOpen,
                  BackupScheduleMode.daily,
                  BackupScheduleMode.weekly,
                  BackupScheduleMode.monthly,
                  BackupScheduleMode.disabled,
                ])
                  CupertinoListTile(
                    title: Text(
                      m == BackupScheduleMode.onAppOpen
                          ? '打开 APP 时备份'
                          : '${m.displayName}${m == BackupScheduleMode.disabled ? '' : '备份'}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: _mode == m
                        ? Icon(
                            CupertinoIcons.checkmark_alt,
                            size: 18,
                            color: context.accentColor,
                          )
                        : null,
                    onTap: () => setState(() => _mode = m),
                  ),
              ],
            ),
          ),
          if (_mode == BackupScheduleMode.weekly) ...[
            const SizedBox(height: 10),
            _label('每周'),
            const SizedBox(height: 6),
            CupertinoSlidingSegmentedControl<int>(
              groupValue: _weeklyDay,
              children: {
                for (var d = 1; d <= 7; d++)
                  d: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Text(
                      weekdayName(d).substring(1),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              },
              onValueChanged: (v) {
                if (v != null) setState(() => _weeklyDay = v);
              },
            ),
          ],
          if (_mode == BackupScheduleMode.monthly) ...[
            const SizedBox(height: 10),
            _label('每月日期（1–31，超出当月天数按月末）'),
            const SizedBox(height: 6),
            SizedBox(
              height: 120,
              child: CupertinoPicker(
                itemExtent: 32,
                scrollController: FixedExtentScrollController(
                  initialItem: (_monthlyDay - 1).clamp(0, 30),
                ),
                onSelectedItemChanged: (i) => _monthlyDay = i + 1,
                children: [
                  for (var d = 1; d <= 31; d++)
                    Center(
                      child: Text(
                        '$d 日',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '自动备份时删除上次的自动备份',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textPrimaryColor,
                  ),
                ),
              ),
              CupertinoSwitch(
                value: _deletePrevious,
                onChanged: (v) => setState(() => _deletePrevious = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _label('自动备份密码（可留空 = 不加密）'),
          const SizedBox(height: 6),
          CupertinoTextField(
            controller: _password,
            placeholder: '预设加密密码',
            obscureText: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          const SizedBox(height: 6),
          Text(
            '密码仅保存在本机；忘记密码将无法恢复加密的自动备份。手动备份仍可另行设置密码。',
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 11,
              color: context.textSecondaryColor,
            ),
          ),
        ],
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () {
            Navigator.pop(
              context,
              BackupScheduleConfig(
                mode: _mode,
                weeklyDay: _weeklyDay,
                monthlyDay: _monthlyDay,
                deletePrevious: _deletePrevious,
                password: _password.text,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      textAlign: TextAlign.left,
      style: TextStyle(
        fontSize: 12,
        color: context.textSecondaryColor,
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/sync_provider.dart';
import '../widgets/settings/settings_ui.dart';
import '../utils/app_toast.dart';

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});
  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  String? _initialError;
  final _joinController = TextEditingController();
  final _keyPasswordController = TextEditingController();
  final _keyBundleController = TextEditingController();
  @override
  void dispose() {
    _joinController.dispose();
    _keyPasswordController.dispose();
    _keyBundleController.dispose();
    super.dispose();
  }

  Future<void> _exportKey(SyncProvider sync) async {
    _keyPasswordController.clear();
    final ok = await showCupertinoDialog<bool>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
              title: const Text('导出同步密钥'),
              content: CupertinoTextField(
                  controller: _keyPasswordController,
                  obscureText: true,
                  placeholder: '至少8位密码'),
              actions: [
                CupertinoDialogAction(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                CupertinoDialogAction(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('复制'))
              ],
            ));
    if (ok == true && mounted) {
      try {
        await Clipboard.setData(
            ClipboardData(text: sync.exportKey(_keyPasswordController.text)));
        showAppToast('已复制加密密钥包，请通过安全渠道传给另一台设备');
      } catch (error) {
        showAppToast(error.toString());
      }
    }
  }

  Future<void> _importKey(SyncProvider sync) async {
    _keyPasswordController.clear();
    final ok = await showCupertinoDialog<bool>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
              title: const Text('导入同步密钥'),
              content: Column(children: [
                CupertinoTextField(
                    controller: _keyBundleController,
                    maxLines: 4,
                    placeholder: '粘贴加密密钥包'),
                CupertinoTextField(
                    controller: _keyPasswordController,
                    obscureText: true,
                    placeholder: '导出密码')
              ]),
              actions: [
                CupertinoDialogAction(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                CupertinoDialogAction(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('导入'))
              ],
            ));
    if (ok == true)
      await sync.importKey(
          _keyBundleController.text, _keyPasswordController.text);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await context.read<SyncProvider>().init();
      } catch (_) {
        if (mounted) setState(() => _initialError = '同步安全存储或本地数据库不可用');
      }
    });
  }

  Future<void> _confirmRestore(SyncProvider sync) async {
    final accepted = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
              title: const Text('恢复云端设置？'),
              content: const Text('仅替换主题模式和底部导航样式，其他设置保持不变。'),
              actions: [
                CupertinoDialogAction(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                CupertinoDialogAction(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('恢复'))
              ],
            ));
    if (accepted == true) await sync.restore();
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    return CupertinoPageScaffold(
      backgroundColor: context.scaffoldColor,
      navigationBar: settingsNavigationBar(context, '设置同步（试点）'),
      child: ListView(
        key: const PageStorageKey('sync-settings'),
        padding: settingsPageContentPadding(context),
        children: [
          SettingsSection(
              title: '非敏感设置',
              footer: const Text(
                  '默认关闭。只同步主题模式和底部导航样式。密钥保存在本机安全存储，服务端只保存密文。目前为设备私有同步试点，不支持跨设备共享。'),
              children: [
                SettingsRow(
                    icon: CupertinoIcons.lock_shield,
                    title: const Text('开启设置同步'),
                    trailing: CupertinoSwitch(
                        value: sync.enabled,
                        onChanged: sync.busy || _initialError != null
                            ? null
                            : sync.setEnabled)),
                SettingsRow(
                    icon: CupertinoIcons.cloud_upload,
                    title: const Text('上传当前设置'),
                    subtitle: const Text('本地修改先记录，断网后可再次上传重试'),
                    onTap: sync.busy || !sync.enabled ? null : sync.upload),
                SettingsRow(
                    icon: CupertinoIcons.cloud_download,
                    title: const Text('恢复云端设置'),
                    onTap: sync.busy || !sync.enabled
                        ? null
                        : () => _confirmRestore(sync)),
              ]),
          SettingsSection(
              title: '同步空间',
              footer:
                  const Text('创建空间后可在其他设备使用一次性加入码加入。服务端只保存加密对象，空间成员无法读取明文。'),
              children: [
                SettingsRow(
                    icon: CupertinoIcons.lock,
                    title: Text(sync.spaceId == null ? '设备私有空间' : '共享空间'),
                    subtitle: Text(sync.spaceId ?? '仅当前设备可见')),
                if (sync.lastJoinCode != null)
                  SettingsRow(
                      icon: CupertinoIcons.share,
                      title: const Text('本次加入码'),
                      subtitle: Text(sync.lastJoinCode!),
                      trailing: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => showCupertinoDialog<void>(
                              context: context,
                              builder: (_) => CupertinoAlertDialog(
                                      title: const Text('加入码'),
                                      content: Text(sync.lastJoinCode!),
                                      actions: [
                                        CupertinoDialogAction(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('知道了'))
                                      ])),
                          child: const Icon(CupertinoIcons.info, size: 18))),
                SettingsRow(
                    icon: CupertinoIcons.add_circled,
                    title: const Text('创建共享空间'),
                    onTap:
                        sync.busy || !sync.enabled ? null : sync.createSpace),
                SettingsRow(
                    icon: CupertinoIcons.person_add,
                    title: const Text('使用加入码'),
                    subtitle: CupertinoTextField(
                        controller: _joinController,
                        placeholder: 'SYN-…',
                        onSubmitted: (_) =>
                            sync.joinSpace(_joinController.text))),
                SettingsRow(
                    icon: CupertinoIcons.lock_open,
                    title: const Text('切回设备私有空间'),
                    onTap: sync.busy || sync.spaceId == null
                        ? null
                        : sync.selectPrivateSpace),
                SettingsRow(
                    icon: CupertinoIcons.arrow_up_doc,
                    title: const Text('导出加密同步密钥'),
                    subtitle: const Text('密钥只在本机生成，服务端永不保存'),
                    onTap: sync.busy || !sync.enabled
                        ? null
                        : () => _exportKey(sync)),
                SettingsRow(
                    icon: CupertinoIcons.arrow_down_doc,
                    title: const Text('导入加密同步密钥'),
                    subtitle: const Text('只从可信设备或安全渠道粘贴'),
                    onTap: sync.busy ? null : () => _importKey(sync)),
              ]),
          if (sync.error != null || _initialError != null)
            SettingsSection(title: '同步状态', children: [
              SettingsRow(
                  icon: CupertinoIcons.exclamationmark_circle,
                  title: Text(_initialError ?? sync.error!)),
              SettingsRow(
                  title: const Text('冲突时保留本机设置'),
                  subtitle: const Text('读取当前云端版本后重新上传本机设置'),
                  onTap: sync.busy || !sync.enabled ? null : sync.keepLocal),
            ]),
          if (sync.busy) const Center(child: CupertinoActivityIndicator()),
        ],
      ),
    );
  }
}

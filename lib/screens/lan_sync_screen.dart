import 'dart:io';

import 'package:flutter/cupertino.dart';

import '../config/theme.dart';
import '../services/backup_service.dart';
import '../services/desktop_sync_server.dart';
import '../services/lan_sync_service.dart';
import '../utils/file_picker_helper.dart';
import '../utils/platform_support.dart';

/// 局域网同步页：手机 → 电脑（AiChat 桌面版）。
///
/// 输入电脑 IP:端口 与配对码，可发送本地备份或当前全量数据。
/// 兼容手机热点：双方在同一局域网即可。
class LanSyncScreen extends StatefulWidget {
  const LanSyncScreen({super.key});

  @override
  State<LanSyncScreen> createState() => _LanSyncScreenState();
}

class _LanSyncScreenState extends State<LanSyncScreen> {
  final _endpointCtrl = TextEditingController();
  final _pairCtrl = TextEditingController();
  bool _working = false;
  double _progress = 0;
  String _stage = '';
  String? _status;
  bool _statusIsError = false;
  Map<String, dynamic>? _serverStatus;

  // 电脑端接收服务
  bool _recvRunning = false;
  String _recvPair = '------';
  String _recvEndpoint = '';
  bool _autoRestore = false;

  @override
  void initState() {
    super.initState();
    _endpointCtrl.text = '';
    _pairCtrl.text = '';
    if (PlatformSupport.isDesktop) {
      _initReceiveServer();
    }
  }

  Future<void> _initReceiveServer() async {
    await desktopSyncServer.ensurePairCode();
    if (!mounted) return;
    setState(() {
      _recvPair = desktopSyncServer.pairCode;
      _recvRunning = desktopSyncServer.isRunning;
    });
    await _refreshEndpoint();
  }

  Future<void> _refreshEndpoint() async {
    final text = await desktopSyncServer.describeEndpoint();
    if (!mounted) return;
    setState(() => _recvEndpoint = text);
  }

  Future<void> _toggleReceiveServer() async {
    setState(() => _working = true);
    try {
      if (desktopSyncServer.isRunning) {
        await desktopSyncServer.stop();
        setState(() => _recvRunning = false);
        _setStatus('电脑端接收服务已停止');
      } else {
        desktopSyncServer.autoRestoreLast = _autoRestore;
        await desktopSyncServer.start();
        await _refreshEndpoint();
        setState(() {
          _recvRunning = true;
          _recvPair = desktopSyncServer.pairCode;
        });
        _setStatus('电脑端接收服务已启动，请在手机填写连接信息');
      }
    } catch (e) {
      _setStatus('启动接收服务失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _pairCtrl.dispose();
    super.dispose();
  }

  void _setStatus(String msg, {bool error = false}) {
    setState(() {
      _status = msg;
      _statusIsError = error;
    });
  }

  void _onProgress(double p, String stage) {
    if (!mounted) return;
    setState(() {
      _progress = p.clamp(0, 1);
      if (stage.isNotEmpty) _stage = stage;
    });
  }

  ({String host, int port})? _parseTarget() {
    final parsed = LanSyncService.parseEndpoint(_endpointCtrl.text);
    if (parsed == null) {
      _setStatus('请填写「IP:端口」，例如 192.168.43.10:8765', error: true);
      return null;
    }
    return parsed;
  }

  Future<void> _testConnection() async {
    final target = _parseTarget();
    if (target == null) return;
    setState(() {
      _working = true;
      _progress = 0.2;
      _stage = '连接电脑端…';
      _status = null;
    });
    try {
      final status = await LanSyncService.fetchStatus(
        host: target.host,
        port: target.port,
      );
      if (!mounted) return;
      setState(() {
        _serverStatus = status;
        _working = false;
        _progress = 0;
        _stage = '';
      });
      final pair = status['pairCode']?.toString() ?? '';
      _setStatus('已连接桌面服务 · 配对码 $pair · 端口 ${status['port']}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _progress = 0;
        _stage = '';
      });
      _setStatus('连接失败：$e', error: true);
    }
  }

  Future<void> _sendSelectedBackup() async {
    final target = _parseTarget();
    if (target == null) return;
    if (_pairCtrl.text.trim().isEmpty) {
      _setStatus('请输入电脑端显示的配对码', error: true);
      return;
    }
    final picked = await FilePickerHelper.pickFile();
    if (picked == null || !mounted) return;
    setState(() {
      _working = true;
      _progress = 0.05;
      _stage = '准备发送';
      _status = null;
    });
    try {
      await LanSyncService.sendBackupFile(
        host: target.host,
        port: target.port,
        pairCode: _pairCtrl.text,
        file: File(picked.path),
        kind: 'file',
        onProgress: _onProgress,
      );
      if (!mounted) return;
      setState(() {
        _working = false;
        _progress = 1;
        _stage = '完成';
      });
      _setStatus('已发送备份文件到电脑：${picked.name}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _progress = 0;
        _stage = '';
      });
      _setStatus('发送失败：$e', error: true);
    }
  }

  Future<void> _sendLocalBackups() async {
    final target = _parseTarget();
    if (target == null) return;
    if (_pairCtrl.text.trim().isEmpty) {
      _setStatus('请输入电脑端显示的配对码', error: true);
      return;
    }
    setState(() {
      _working = true;
      _progress = 0.05;
      _stage = '读取本地备份';
      _status = null;
    });
    try {
      final backups = await BackupService.listLocalBackups();
      if (backups.isEmpty) {
        setState(() {
          _working = false;
          _progress = 0;
          _stage = '';
        });
        _setStatus('本地还没有备份，可先「立即备份」或使用「发送当前数据」', error: true);
        return;
      }
      for (var i = 0; i < backups.length; i++) {
        final file = backups[i];
        _onProgress(
          0.1 + 0.85 * (i / backups.length),
          '发送 ${i + 1}/${backups.length}：${file.path.split(RegExp(r'[/\\]')).last}',
        );
        await LanSyncService.sendBackupFile(
          host: target.host,
          port: target.port,
          pairCode: _pairCtrl.text,
          file: file,
          kind: 'local',
        );
      }
      if (!mounted) return;
      setState(() {
        _working = false;
        _progress = 1;
        _stage = '完成';
      });
      _setStatus('已发送 ${backups.length} 份本地备份到电脑');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _progress = 0;
        _stage = '';
      });
      _setStatus('发送失败：$e', error: true);
    }
  }

  Future<void> _sendCurrentData() async {
    final target = _parseTarget();
    if (target == null) return;
    if (_pairCtrl.text.trim().isEmpty) {
      _setStatus('请输入电脑端显示的配对码', error: true);
      return;
    }
    setState(() {
      _working = true;
      _progress = 0.02;
      _stage = '打包当前数据';
      _status = null;
    });
    try {
      await LanSyncService.exportAndSend(
        host: target.host,
        port: target.port,
        pairCode: _pairCtrl.text,
        onProgress: _onProgress,
      );
      if (!mounted) return;
      setState(() {
        _working = false;
        _progress = 1;
        _stage = '完成';
      });
      _setStatus('当前数据已同步到电脑');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _progress = 0;
        _stage = '';
      });
      _setStatus('同步失败：$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('局域网同步'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (PlatformSupport.isDesktop) ...[
              Text(
                '电脑端接收服务：启动后，手机「局域网同步」填入下方信息即可传数据。',
                style: TextStyle(
                  fontSize: 13,
                  color: context.textSecondaryColor,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 16),
              _section(
                title: '本机接收服务',
                children: [
                  _infoRow('状态', _recvRunning ? '运行中' : '未启动'),
                  _divider(),
                  _infoRow('连接信息', _recvEndpoint.isEmpty ? '—' : _recvEndpoint),
                  _divider(),
                  _infoRow('配对码', _recvPair),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '收到备份后自动恢复到本机',
                            style: TextStyle(
                              fontSize: 13,
                              color: context.textPrimaryColor,
                            ),
                          ),
                        ),
                        CupertinoSwitch(
                          value: _autoRestore,
                          onChanged: (v) => setState(() {
                            _autoRestore = v;
                            desktopSyncServer.autoRestoreLast = v;
                          }),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: CupertinoButton.filled(
                      onPressed: _working ? null : _toggleReceiveServer,
                      child: Text(_recvRunning ? '停止接收服务' : '启动接收服务'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            Text(
              '把手机数据同步到电脑版 AiChat。\n'
              '电脑运行 desktop_server.py 或启动本页接收服务后，填写 IP:端口 与配对码。\n'
              '手机热点下：电脑连接该热点后，填写电脑的局域网 IP。',
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondaryColor,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 20),
            _section(
              title: '电脑连接信息',
              children: [
                _field(
                  controller: _endpointCtrl,
                  placeholder: 'IP:端口  例如 192.168.43.10:8765',
                  keyboardType: TextInputType.url,
                ),
                _divider(),
                _field(
                  controller: _pairCtrl,
                  placeholder: '配对码（电脑端显示的 6 位数字）',
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
            const SizedBox(height: 12),
            CupertinoButton.filled(
              onPressed: _working ? null : _testConnection,
              child: const Text('测试连接'),
            ),
            if (_serverStatus != null) ...[
              const SizedBox(height: 12),
              _section(
                title: '电脑端状态',
                children: [
                  _infoRow('服务地址', '${_serverStatus!['listen'] ?? '—'}'),
                  _divider(),
                  _infoRow('本机建议 IP', '${_serverStatus!['host'] ?? '—'}'),
                  _divider(),
                  _infoRow('配对码', '${_serverStatus!['pairCode'] ?? '—'}'),
                  _divider(),
                  _infoRow(
                    '已收备份',
                    '${(_serverStatus!['files'] as List?)?.length ?? 0} 份',
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            if (_working) ...[
              _progressWidget(),
              const SizedBox(height: 16),
            ],
            if (_status != null) ...[
              Text(
                _status!,
                style: TextStyle(
                  fontSize: 12,
                  color: _statusIsError
                      ? CupertinoColors.destructiveRed
                      : context.accentColor,
                ),
              ),
              const SizedBox(height: 12),
            ],
            _section(
              title: '同步内容',
              children: [
                _action(
                  icon: CupertinoIcons.cube_box_fill,
                  title: '发送当前数据',
                  subtitle: '打包全部数据（不含密钥）并立刻传到电脑',
                  onTap: _working ? null : _sendCurrentData,
                ),
                _action(
                  icon: CupertinoIcons.archivebox_fill,
                  title: '发送本地备份列表',
                  subtitle: '把应用内已有的本地备份逐个传到电脑',
                  onTap: _working ? null : _sendLocalBackups,
                ),
                _action(
                  icon: CupertinoIcons.doc_fill,
                  title: '选择备份文件发送',
                  subtitle: '从系统文件中选择 zip 备份发送',
                  onTap: _working ? null : _sendSelectedBackup,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '提示：电脑端浏览器打开 http://IP:端口 可查看桌面版与接收列表。'
              '传输仅在局域网内进行，不经过公网服务器。',
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressWidget() {
    final percent = (_progress * 100).clamp(0, 100).toStringAsFixed(0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _stage.isEmpty ? '同步中…' : _stage,
                style: TextStyle(
                  fontSize: 12,
                  color: context.textSecondaryColor,
                ),
              ),
            ),
            Text(
              '$percent%',
              style: TextStyle(
                fontSize: 12,
                color: context.accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Container(color: context.separatorColor),
                FractionallySizedBox(
                  widthFactor: _progress.clamp(0, 1),
                  child: Container(color: context.accentColor),
                ),
              ],
            ),
          ),
        ),
      ],
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

  Widget _field({
    required TextEditingController controller,
    required String placeholder,
    TextInputType? keyboardType,
  }) {
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      keyboardType: keyboardType,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondaryColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return CupertinoListTile(
      leading: Icon(icon, color: context.textSecondaryColor),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
      ),
      trailing: Icon(
        CupertinoIcons.chevron_right,
        size: 16,
        color: context.textSecondaryColor,
      ),
      onTap: onTap,
    );
  }

  Widget _divider() {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: context.separatorColor,
    );
  }
}

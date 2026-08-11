import 'package:flutter/cupertino.dart';
import '../config/theme.dart';
import '../services/update_service.dart';

/// 更新下载源：Gitee 优先（国内直连），GitHub 备用（可走代理加速）
enum UpdateSource { gitee, github }

/// 发现新版本提示弹窗：展示版本号、更新说明与"下载源"选项卡，
/// 点击「立即更新」进入下载安装流程
void showUpdateAvailableDialog(
  BuildContext context,
  UpdateInfo info, {
  required String proxyUrl,
}) {
  showCupertinoDialog(
    context: context,
    builder: (ctx) => _UpdateAvailableDialog(info: info, proxyUrl: proxyUrl),
  );
}

class _UpdateAvailableDialog extends StatefulWidget {
  final UpdateInfo info;
  final String proxyUrl;

  const _UpdateAvailableDialog({required this.info, required this.proxyUrl});

  @override
  State<_UpdateAvailableDialog> createState() => _UpdateAvailableDialogState();
}

class _UpdateAvailableDialogState extends State<_UpdateAvailableDialog> {
  late UpdateSource _source;

  UpdateInfo get _info => widget.info;
  bool get _giteeAvailable => _info.giteeDownloadUrl.isNotEmpty;
  bool get _githubAvailable => _info.githubDownloadUrl.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // 默认优先 Gitee，Gitee 不可用时回退 GitHub
    _source = _giteeAvailable ? UpdateSource.gitee : UpdateSource.github;
  }

  @override
  Widget build(BuildContext context) {
    final both = _giteeAvailable && _githubAvailable;
    return CupertinoAlertDialog(
      title: Text('发现新版本 V${_info.latestVersion}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Text(
                _info.releaseNotes.isEmpty
                    ? '有新版本可用，立即更新体验吧'
                    : _info.releaseNotes,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '下载源',
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 6),
          if (both)
            CupertinoSlidingSegmentedControl<UpdateSource>(
              groupValue: _source,
              onValueChanged: (v) {
                if (v != null) setState(() => _source = v);
              },
              children: const {
                UpdateSource.gitee: Text('Gitee（推荐）'),
                UpdateSource.github: Text('GitHub'),
              },
            )
          else
            Text(
              _giteeAvailable ? 'Gitee（推荐）' : 'GitHub',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.textPrimaryColor,
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
            Navigator.pop(context);
            showCupertinoDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => _DownloadDialog(
                info: _info,
                source: _source,
                proxyUrl: widget.proxyUrl,
              ),
            );
          },
          child: const Text('立即更新'),
        ),
      ],
    );
  }
}

/// 下载更新弹窗：实时显示下载进度，完成后自动启动安装。
/// 按"下载源"选择对应直链，GitHub 源可叠加代理前缀加速。
class _DownloadDialog extends StatefulWidget {
  final UpdateInfo info;
  final UpdateSource source;
  final String proxyUrl;

  const _DownloadDialog({
    required this.info,
    required this.source,
    required this.proxyUrl,
  });

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  double _progress = 0;
  bool _failed = false;

  String get _sourceLabel =>
      widget.source == UpdateSource.gitee ? 'Gitee' : 'GitHub';

  String get _downloadUrl => widget.source == UpdateSource.gitee
      ? widget.info.giteeDownloadUrl
      : widget.info.githubDownloadUrl;

  /// GitHub 源才叠加代理前缀，Gitee 源直接下载
  String get _proxyForSource =>
      widget.source == UpdateSource.gitee ? '' : widget.proxyUrl;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final info = widget.info;
    String? path;
    try {
      path = await UpdateService.downloadApk(
        downloadUrl: _downloadUrl,
        version: info.latestVersion,
        proxyUrl: _proxyForSource,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
    } catch (_) {}

    if (!mounted) return;
    if (path == null) {
      setState(() => _failed = true);
      return;
    }
    // 下载完成：关闭弹窗并启动系统安装
    Navigator.of(context).pop();
    await UpdateService.installApk(path);
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_progress * 100).round();
    return CupertinoAlertDialog(
      title: Text(
        _failed
            ? '下载失败'
            : '正在从 $_sourceLabel 下载 V${widget.info.latestVersion}',
      ),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: _failed
            ? const Text('下载失败，请检查网络或切换下载源后重试')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.separatorColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _progress,
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.accentColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$percent%',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        if (_failed)
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
      ],
    );
  }
}

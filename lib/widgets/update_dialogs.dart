import 'package:flutter/cupertino.dart';
import '../config/theme.dart';
import '../services/update_service.dart';

/// 发现新版本提示弹窗：展示版本号与更新说明，
/// 点击「立即更新」进入下载安装流程（支持代理前缀）
void showUpdateAvailableDialog(
  BuildContext context,
  UpdateInfo info, {
  required String proxyUrl,
}) {
  showCupertinoDialog(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text('发现新版本 V${info.latestVersion}'),
      content: SingleChildScrollView(
        child: Text(
          info.releaseNotes.isEmpty ? '有新版本可用，立即更新体验吧' : info.releaseNotes,
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () {
            Navigator.pop(ctx);
            showCupertinoDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => _DownloadDialog(info: info, proxyUrl: proxyUrl),
            );
          },
          child: const Text('立即更新'),
        ),
      ],
    ),
  );
}

/// 下载更新弹窗：实时显示下载进度，完成后自动启动安装
class _DownloadDialog extends StatefulWidget {
  final UpdateInfo info;
  final String proxyUrl;

  const _DownloadDialog({required this.info, required this.proxyUrl});

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  double _progress = 0;
  bool _failed = false;

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
        downloadUrl: info.downloadUrl,
        version: info.latestVersion,
        proxyUrl: widget.proxyUrl,
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
        _failed ? '下载失败' : '正在下载 V${widget.info.latestVersion}',
      ),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: _failed
            ? const Text('下载失败，请检查网络后重试')
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

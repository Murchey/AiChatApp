import 'package:flutter/cupertino.dart';

import '../../config/theme.dart';
import '../../models/workshop_asset.dart';
import '../../services/cos_auth.dart';
import '../../services/workshop_service.dart';

/// 资产 zip 展示项（携带所属仓库信息）
class ZipItem {
  final WorkshopAsset asset;
  final String repoName;
  final String repoId;

  ZipItem({
    required this.asset,
    required this.repoName,
    required this.repoId,
  });

  String get key => '$repoId|${asset.tag}|${asset.name}';
}

/// 下载 zip 进度弹窗：完成后自动关闭并返回本地路径，失败返回 null
class DownloadZipDialog extends StatefulWidget {
  final String name;
  final String downloadUrl;
  final String proxyUrl;

  const DownloadZipDialog({
    required this.name,
    required this.downloadUrl,
    required this.proxyUrl,
  });

  @override
  State<DownloadZipDialog> createState() => DownloadZipDialogState();
}

class DownloadZipDialogState extends State<DownloadZipDialog> {
  double _progress = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final path = await WorkshopService.downloadZip(
      downloadUrl: widget.downloadUrl,
      proxyUrl: widget.proxyUrl,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    if (path == null) {
      setState(() => _failed = true);
      return;
    }
    Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_progress * 100).round();
    return CupertinoAlertDialog(
      title: Text(_failed ? '下载失败' : '正在下载'),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: _failed
            ? const Text('下载失败，请检查网络或代理设置后重试')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 8),
                  Text(
                    '下载完成后将自动进入导入流程',
                    textAlign: TextAlign.center,
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

/// 批量下载 zip 进度弹窗：下载所有 zip 后自动关闭，返回 item.key -> 本地路径 的映射
class BatchDownloadDialog extends StatefulWidget {
  final List<ZipItem> items;
  final String Function(ZipItem item) getProxyUrl;
  final CosAuth? Function(ZipItem item)? getCosAuth;

  const BatchDownloadDialog({
    required this.items,
    required this.getProxyUrl,
    this.getCosAuth,
  });

  @override
  State<BatchDownloadDialog> createState() => BatchDownloadDialogState();
}

class BatchDownloadDialogState extends State<BatchDownloadDialog> {
  int _currentIndex = 0;
  double _currentProgress = 0;
  bool _failed = false;
  final Map<String, String> _results = {};

  @override
  void initState() {
    super.initState();
    _startBatchDownload();
  }

  Future<void> _startBatchDownload() async {
    for (var i = 0; i < widget.items.length; i++) {
      if (!mounted) return;
      setState(() {
        _currentIndex = i;
        _currentProgress = 0;
      });

      final item = widget.items[i];
      final proxyUrl = widget.getProxyUrl(item);
      final auth = widget.getCosAuth?.call(item);
      final path = await WorkshopService.downloadZip(
        downloadUrl: item.asset.downloadUrl,
        proxyUrl: proxyUrl,
        auth: auth,
        onProgress: (p) {
          if (mounted) setState(() => _currentProgress = p);
        },
      );

      if (!mounted) return;
      if (path == null) {
        setState(() {
          _failed = true;
        });
        // 等待用户确认后继续或取消
        final shouldContinue = await showCupertinoDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('下载失败'),
            content: Text(
              '「${item.asset.displayName}」下载失败，请检查网络、密钥权限或稍后重试',
              textAlign: TextAlign.center,
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('取消全部'),
                onPressed: () => Navigator.pop(ctx, false),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('跳过继续'),
              ),
            ],
          ),
        );
        if (shouldContinue != true) {
          // 用户选择取消全部，返回已有结果
          if (mounted) {
            Navigator.pop(context, _results.isNotEmpty ? _results : null);
          }
          return;
        }
        // 跳过当前失败的，继续下载下一个
        setState(() => _failed = false);
        continue;
      }

      _results[item.key] = path;
    }

    // 全部下载完成
    if (mounted) Navigator.pop(context, _results);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    final currentName = _currentIndex < total
        ? widget.items[_currentIndex].asset.displayName
        : '';
    final percent = (_currentProgress * 100).round();

    return CupertinoAlertDialog(
      title: Text(_failed ? '下载失败' : '正在批量下载'),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 整体进度提示
            Text(
              '正在下载 (${_currentIndex + 1}/$total)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 8),
            // 当前文件名
            Text(
              currentName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 12),
            // 进度条
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: context.separatorColor,
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _currentProgress,
                child: Container(
                  decoration: BoxDecoration(
                    color: context.accentColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 百分比
            Text(
              '$percent%',
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 8),
            // 提示文字
            Text(
              '全部下载完成后将逐个确认导入',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
              ),
            ),
          ],
        ),
      ),
      actions: const [], // 下载过程中不允许取消（已在失败时提供选项）
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/settings_provider.dart';
import '../utils/app_toast.dart';
import '../utils/file_picker_helper.dart';
import '../utils/file_utils.dart';
import '../widgets/splash_icon_view.dart';
import 'image_crop_screen.dart';

/// 开屏图标设置页：预览当前开屏内容，
/// 支持导入本地图片替换默认图标，或恢复默认（同时删除已导入的缓存图片）。
class SplashIconScreen extends StatelessWidget {
  const SplashIconScreen({super.key});

  Future<void> _pickImage(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final picked = await FilePickerHelper.pickFile();
    if (picked == null || picked.path.isEmpty) return;
    if (!context.mounted) return;
    // 进入编辑页缩放裁剪，选择实际展示效果
    final cropped = await Navigator.push<String>(
      context,
      CupertinoPageRoute(
        builder: (_) => ImageCropScreen(imagePath: picked.path),
      ),
    );
    if (cropped == null || !context.mounted) return;
    try {
      await settings.setSplashIcon(cropped);
      if (context.mounted) showAppToast('开屏图标已更新');
    } catch (e) {
      if (context.mounted) showAppToast('设置开屏图标失败：$e');
    } finally {
      deleteFileQuietly(cropped);
    }
  }

  Future<void> _reset(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('恢复默认开屏图标'),
        content: const Text('将删除已导入的图片，并恢复默认开屏内容'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复默认'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await settings.resetSplashIcon();
    if (context.mounted) showAppToast('已恢复默认开屏图标');
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final hasIcon = settings.hasSplashIcon;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('开屏图标'),
        automaticallyImplyLeading: true,
        previousPageTitle: '设置',
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            // 预览区：手机屏幕比例的启动页预览
            Padding(
              padding: const EdgeInsets.fromLTRB(48, 0, 48, 20),
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SplashIconView(imagePath: settings.splashIconPath),
                ),
              ),
            ),
            CupertinoListSection.insetGrouped(
              backgroundColor: context.scaffoldColor,
              decoration: BoxDecoration(
                color: context.listBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              children: [
                CupertinoListTile(
                  leading: Icon(
                    CupertinoIcons.photo,
                    color: context.accentColor,
                  ),
                  title: const Text('选择图片'),
                  subtitle: Text(
                    '从相册 / 文件中选择一张图片作为开屏图标',
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
                  onTap: () => _pickImage(context, settings),
                ),
                if (hasIcon) ...[
                  Container(
                    height: 0.5,
                    margin: const EdgeInsets.only(left: 16),
                    color: context.separatorColor,
                  ),
                  CupertinoListTile(
                    leading: Icon(
                      CupertinoIcons.arrow_counterclockwise,
                      color: context.textSecondaryColor,
                    ),
                    title: const Text('恢复默认'),
                    subtitle: Text(
                      '删除已导入的图片，恢复默认开屏内容',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    onTap: () => _reset(context, settings),
                  ),
                ],
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
              child: Text(
                '设置自定义开屏图标后，启动页将只展示该图片；'
                '恢复默认或更换图标时会自动清理已导入的缓存图片',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: context.textSecondaryColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

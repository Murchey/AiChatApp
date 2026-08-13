import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/moment.dart';
import '../models/visibility_group.dart';
import '../providers/api_provider.dart';
import '../providers/character_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_settings_provider.dart';
import '../providers/moment_notification_provider.dart';
import '../screens/moment_visibility_screen.dart';
import '../services/dev_log_service.dart';
import '../services/moment_ai_service.dart';
import '../utils/app_toast.dart';

/// 发布 / 编辑朋友圈页面：文字 + 标记位置 + 相册多选图片（最多 9 张）。
///
/// 未传 [editingMoment] 时为发布模式：图片复制到应用文档目录 `user_moments/`
/// 下（保存绝对路径，便于展示与数据包导出），写入「自己」账号的朋友圈并持久化。
/// 传入 [editingMoment] 时为编辑模式：预填已有内容，可修改发布时间，
/// 保存后以编辑后的 [Moment] 通过 `Navigator.pop` 返回（保持 id / 点赞 / 评论不变），
/// 由调用方替换原动态。
class PublishMomentScreen extends StatefulWidget {
  final Moment? editingMoment;

  const PublishMomentScreen({super.key, this.editingMoment});

  @override
  State<PublishMomentScreen> createState() => _PublishMomentScreenState();
}

class _PublishMomentScreenState extends State<PublishMomentScreen> {
  static const int _maxImages = 9;

  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final List<String> _existingPaths = []; // 编辑模式：已有的本地图片路径
  final List<XFile> _picked = [];
  String _visibilityId = VisibilityScope.all; // 展示范围（默认全部角色可见）
  DateTime? _createdAt; // 编辑模式：发布日期（默认沿用原时间）
  bool _saving = false;

  bool get _isEdit => widget.editingMoment != null;

  @override
  void initState() {
    super.initState();
    final editing = widget.editingMoment;
    if (editing != null) {
      _contentController.text = editing.content;
      _locationController.text = editing.location;
      _visibilityId = editing.visibility;
      _createdAt = editing.createdAt;
      _existingPaths.addAll(
        editing.images.where((p) => File(p).existsSync()),
      );
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_saving &&
      (_contentController.text.trim().isNotEmpty || _picked.isNotEmpty ||
          _existingPaths.isNotEmpty);

  Future<void> _pickImages() async {
    if (_existingPaths.length + _picked.length >= _maxImages) return;
    final files = await ImagePicker().pickMultiImage(
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 80,
    );
    if (files.isEmpty || !mounted) return;
    setState(() {
      _picked.addAll(files);
      final total = _existingPaths.length + _picked.length;
      if (total > _maxImages) {
        _picked.removeRange(_maxImages - _existingPaths.length, _picked.length);
      }
    });
  }

  void _removeImage(bool isExisting, int index) {
    setState(() {
      if (isExisting) {
        _existingPaths.removeAt(index);
      } else {
        _picked.removeAt(index);
      }
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      // 新选图片复制到应用文档目录 user_moments/，存绝对路径
      final newPaths = [..._existingPaths];
      if (_picked.isNotEmpty) {
        final docDir = await getApplicationDocumentsDirectory();
        final dir = Directory('${docDir.path}/user_moments');
        await dir.create(recursive: true);
        final ts = DateTime.now().millisecondsSinceEpoch;
        for (var i = 0; i < _picked.length; i++) {
          final source = File(_picked[i].path);
          if (!source.existsSync()) continue;
          final target = File(
              '${dir.path}/moment_${ts}_$i.${_extensionOf(_picked[i].path)}');
          await target.writeAsBytes(source.readAsBytesSync(), flush: true);
          newPaths.add(target.path);
        }
      }
      if (!mounted) return;
      final content = _contentController.text.trim();
      final location = _locationController.text.trim();
      if (_isEdit) {
        final old = widget.editingMoment!;
        // 清理编辑时被移除的旧图片（仅清理"自己"发布目录 user_moments/ 下）
        final removed = old.images.where((p) => !newPaths.contains(p)).toList();
        for (final p in removed) {
          try {
            if (p.replaceAll('\\', '/').contains('/user_moments/')) {
              final f = File(p);
              if (f.existsSync()) f.deleteSync();
            }
          } catch (_) {}
        }
        final characterProvider = context.read<CharacterProvider>();
        final api = context.read<ApiProvider>();
        final notificationProvider =
            context.read<MomentNotificationProvider>();
        final chatProvider = context.read<ChatProvider>();
        final chatSettings = context.read<ChatSettingsProvider>();
        final edited = Moment(
          id: old.id,
          content: content,
          location: location,
          visibility: _visibilityId,
          images: newPaths,
          likes: old.likes,
          comments: old.comments,
          createdAt: _createdAt ?? old.createdAt,
        );
        Navigator.pop(context, edited);
        // 重新编辑等效于重新发布：重新触发 AI 互动
        // （按新的展示范围遍历可见角色，重新请求点赞/评论）
        _startAiEngagement(
          characterProvider: characterProvider,
          api: api,
          notificationProvider: notificationProvider,
          chatProvider: chatProvider,
          chatSettings: chatSettings,
          moment: edited,
        );
      } else {
        final characterProvider = context.read<CharacterProvider>();
        final api = context.read<ApiProvider>();
        final notificationProvider =
            context.read<MomentNotificationProvider>();
        final chatProvider = context.read<ChatProvider>();
        final chatSettings = context.read<ChatSettingsProvider>();
        final moment = await characterProvider.publishSelfMoment(
          content: content,
          images: newPaths,
          location: location,
          visibility: _visibilityId,
        );
        if (!mounted) return;
        // 先返回朋友圈列表，再后台启动 AI 互动（含非多模态提示弹窗）
        Navigator.pop(context, true);
        _startAiEngagement(
          characterProvider: characterProvider,
          api: api,
          notificationProvider: notificationProvider,
          chatProvider: chatProvider,
          chatSettings: chatSettings,
          moment: moment,
        );
      }
    } catch (_) {
      if (!mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('保存失败'),
          content: const Text('保存朋友圈时出错，请重试'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'jpg';
    final ext = path.substring(dot + 1).toLowerCase();
    const allowed = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'};
    return allowed.contains(ext) ? ext : 'jpg';
  }

  /// 发布成功后后台启动朋友圈 AI 互动：
  /// 遍历展示范围内可见角色，请求模型决定是否点赞/评论。
  /// 未配置「朋友圈互动」模型时 Toast 提示；图文动态但模型非多模态时
  /// 弹窗提示 AI 回复可能效果不佳（互动仍继续尝试）。
  void _startAiEngagement({
    required CharacterProvider characterProvider,
    required ApiProvider api,
    required MomentNotificationProvider notificationProvider,
    required ChatProvider chatProvider,
    required ChatSettingsProvider chatSettings,
    required Moment moment,
  }) {
    final model = api.getModelById(api.momentModelId);
    final characters =
        MomentAiService.visibleCharacters(characterProvider, moment.visibility);
    if (model == null) {
      const msg = '请先在「API 设置」中配置「朋友圈互动」模型';
      DevLogService.instance.log(msg);
      showAppToast(msg);
      return;
    }
    if (characters.isEmpty) {
      DevLogService.instance.log('朋友圈互动：展示范围内没有可见角色，跳过');
      return;
    }

    // 图文动态但模型未检测为多模态 → 弹窗提示 AI 回复可能效果不佳
    final visionSupported = api.isVisionSupported(api.momentModelId);
    if (moment.images.isNotEmpty && visionSupported != true) {
      final rootCtx = appNavigatorKey.currentContext;
      if (rootCtx != null) {
        showCupertinoDialog<void>(
          context: rootCtx,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('提示'),
            content: const Text(
              '当前「朋友圈互动」模型可能不支持图片，AI 回复效果可能不佳。',
            ),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(ctx),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      }
    }

    // 后台启动互动（不阻塞界面）
    unawaited(MomentAiService.run(
      characterProvider: characterProvider,
      apiProvider: api,
      notificationProvider: notificationProvider,
      chatProvider: chatProvider,
      chatSettings: chatSettings,
      moment: moment,
      characters: characters,
    ));
  }

  /// 当前展示范围的显示文案（分组被删除后回退到全部角色可见）
  String get _visibilityLabel {
    if (_visibilityId == VisibilityScope.onlyMe) return '仅自己可见';
    if (_visibilityId == VisibilityScope.all) return '全部角色可见';
    final groups = context.read<CharacterProvider>().visibilityGroups;
    for (final g in groups) {
      if (g.id == _visibilityId) return g.name;
    }
    return '全部角色可见';
  }

  /// 打开展示范围选择页（固定选项 + 自定义分组）
  Future<void> _openVisibility() async {
    final id = await Navigator.push<String>(
      context,
      CupertinoPageRoute(
        builder: (_) => MomentVisibilityScreen(selectedId: _visibilityId),
      ),
    );
    if (id == null || !mounted) return;
    setState(() => _visibilityId = id);
  }

  /// 编辑模式：弹出底部日期选择器修改发布日期
  Future<void> _pickCreatedAt() async {
    final initial = _createdAt ?? DateTime.now();
    DateTime? picked = initial;
    final result = await showCupertinoModalPopup<DateTime>(
      context: context,
      barrierColor: CupertinoColors.black.withValues(alpha: 0.3),
      builder: (ctx) => Container(
        height: 300,
        color: context.listBgColor,
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: () => Navigator.pop(ctx, picked),
                    child: const Text(
                      '完成',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.dateAndTime,
                initialDateTime: initial,
                minimumDate: DateTime(2000, 1, 1),
                maximumDate: DateTime.now(), // 不允许晚于当前时间
                backgroundColor: context.listBgColor,
                onDateTimeChanged: (d) => picked = d,
              ),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _createdAt = result);
  }

  String _formatDateTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _canSave;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        middle: Text(_isEdit ? '编辑动态' : '发表动态'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: canSave ? _save : null,
          child: Text(
            _saving
                ? (_isEdit ? '保存中...' : '发表中...')
                : (_isEdit ? '保存' : '发表'),
            style: TextStyle(
              color: canSave
                  ? context.accentColor
                  : context.textSecondaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: CupertinoTextField(
              controller: _contentController,
              autofocus: !_isEdit,
              maxLines: 8,
              minLines: 4,
              maxLength: 500,
              placeholder: '这一刻的想法...',
              placeholderStyle: TextStyle(color: context.textSecondaryColor),
              padding: const EdgeInsets.all(12),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 12),
          _buildImageGrid(context),
          const SizedBox(height: 8),
          Text(
            '图片最多 $_maxImages 张',
            style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
          ),
          const SizedBox(height: 12),
          // 标记位置（发布页底部填写项）
          Container(
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.location_fill,
                  size: 16,
                  color: context.textSecondaryColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CupertinoTextField(
                    controller: _locationController,
                    maxLength: 50,
                    placeholder: '标记位置',
                    placeholderStyle:
                        TextStyle(color: context.textSecondaryColor),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 展示范围：点击进入选择页（仅自己可见 / 全部角色可见 / 自定义分组）
          Container(
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openVisibility,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.eye,
                      size: 16,
                      color: context.textSecondaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _visibilityLabel,
                        style: TextStyle(
                          fontSize: 16,
                          color: context.textPrimaryColor,
                        ),
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: context.textSecondaryColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isEdit) ...[
            const SizedBox(height: 12),
            // 编辑模式：发布日期（点击弹出日期选择器修改）
            Container(
              decoration: BoxDecoration(
                color: context.listBgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _pickCreatedAt,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.calendar,
                        size: 16,
                        color: context.textSecondaryColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _createdAt == null
                              ? '未设置日期'
                              : _formatDateTime(_createdAt!),
                          style: TextStyle(
                            fontSize: 16,
                            color: context.textPrimaryColor,
                          ),
                        ),
                      ),
                      Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                        color: context.textSecondaryColor,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 已选图片 3 列网格（每张可删除）+ 添加按钮
  Widget _buildImageGrid(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cell = (screenWidth - 32 - 8) / 3;
    final items = <Widget>[
      for (var i = 0; i < _existingPaths.length; i++)
        _buildImageCell(
          context,
          cell,
          Image.file(File(_existingPaths[i]), fit: BoxFit.cover),
          onRemove: () => _removeImage(true, i),
        ),
      for (var i = 0; i < _picked.length; i++)
        _buildImageCell(
          context,
          cell,
          Image.file(File(_picked[i].path), fit: BoxFit.cover),
          onRemove: () => _removeImage(false, i),
        ),
    ];
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        ...items,
        if (_existingPaths.length + _picked.length < _maxImages)
          GestureDetector(
            onTap: _pickImages,
            child: Container(
              width: cell,
              height: cell,
              decoration: BoxDecoration(
                color: context.listBgColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.separatorColor),
              ),
              alignment: Alignment.center,
              child: Icon(
                CupertinoIcons.add,
                size: 28,
                color: context.textSecondaryColor,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImageCell(
    BuildContext context,
    double cell,
    Widget image, {
    required VoidCallback onRemove,
  }) {
    return SizedBox(
      width: cell,
      height: cell,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: image,
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: CupertinoColors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  CupertinoIcons.xmark,
                  size: 13,
                  color: CupertinoColors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

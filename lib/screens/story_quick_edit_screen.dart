import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../config/theme.dart';
import '../models/story_package.dart';
import '../providers/story_provider.dart';
import '../services/story_editing_service.dart';
import '../services/story_service.dart';
import '../utils/file_picker_helper.dart';
import '../utils/app_toast.dart';
import '../widgets/settings/settings_ui.dart';

class StoryQuickEditScreen extends StatefulWidget {
  final StoryEditingService service;
  final Future<Uint8List?> Function()? pickImage;
  const StoryQuickEditScreen(
      {super.key, this.service = const StoryEditingService(), this.pickImage});

  @override
  State<StoryQuickEditScreen> createState() => _StoryQuickEditScreenState();
}

class _StoryQuickEditScreenState extends State<StoryQuickEditScreen> {
  final _search = TextEditingController();
  final _id = TextEditingController();
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _tags = TextEditingController();
  final _summary = TextEditingController();
  final _introduction = TextEditingController();
  final _memories = TextEditingController();
  final _images = TextEditingController();
  List<StoryCatalogEntry> _entries = [];
  Map<String, dynamic>? _original;
  StorySourceConfig? _config;
  StoryCatalogEntry? _entry;
  bool _checking = true,
      _loadingDetail = false,
      _saving = false,
      _isNew = false;
  bool _writable = false;
  int _selection = 0;
  String? _error;
  bool _mediaBusy = false,
      _showMetadata = false,
      _showMemories = false,
      _showPaths = false;
  final Map<String, Uint8List> _previews = {};
  bool get _busy => _saving || _mediaBusy;
  String get _file => _isNew ? 'assets/${_id.text.trim()}.json' : _entry!.file;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void dispose() {
    for (final c in [
      _search,
      _id,
      _title,
      _author,
      _tags,
      _summary,
      _introduction,
      _memories,
      _images
    ]) {
      c.dispose();
    }
    _selection++;
    super.dispose();
  }

  Future<void> _prepare() async {
    if (_busy || !mounted) return;
    final provider = context.read<StoryProvider>();
    setState(() {
      _checking = true;
      _writable = false;
      _error = null;
    });
    try {
      await provider.init();
      final config = provider.config;
      await widget.service.checkWrite(config);
      final index = await widget.service.loadIndex(config);
      if (!mounted) return;
      setState(() {
        _config = config;
        _entries = (index['stories'] as List)
            .map((v) =>
                StoryCatalogEntry.fromJson(Map<String, dynamic>.from(v as Map)))
            .toList();
        _writable = true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = provider.readableError(error));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _create() {
    if (_busy) return;
    _selection++;
    _id.text = 'story-${const Uuid().v4()}';
    for (final c in [
      _title,
      _author,
      _tags,
      _summary,
      _introduction,
      _memories,
      _images
    ]) {
      c.clear();
    }
    setState(() {
      _original = {
        'schemaVersion': 2,
        'version': 1,
        'publishedAt': DateTime.now().toUtc().toIso8601String()
      };
      _entry = null;
      _isNew = true;
      _loadingDetail = false;
      _error = null;
      _showMetadata = false;
      _showMemories = false;
      _showPaths = false;
      _previews.clear();
    });
  }

  Future<void> _select(StoryCatalogEntry entry) async {
    if (_busy) return;
    final selection = ++_selection;
    setState(() {
      _entry = entry;
      _original = null;
      _isNew = false;
      _loadingDetail = true;
      _error = null;
    });
    try {
      final detail = await widget.service.loadDetail(_config!, entry);
      if (!mounted || selection != _selection) return;
      final story = StoryPackage.fromJson(detail);
      _id.text = story.storyId;
      _title.text = story.title;
      _author.text = story.author;
      _tags.text = story.tags.join('，');
      _summary.text = story.summary.isEmpty ? entry.summary : story.summary;
      _introduction.text = story.introduction;
      _memories.text = story.memories.map((m) => m.content).join('\n\n');
      _images.text = story.images.join('\n');
      setState(() => _original = detail);
    } catch (error) {
      if (mounted && selection == _selection) {
        setState(() => _error = '详情加载失败：$error');
      }
    } finally {
      if (mounted && selection == _selection) {
        setState(() => _loadingDetail = false);
      }
    }
  }

  List<String> _lines(String value) => value
      .split('\n')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();

  Future<void> _save() async {
    if (_original == null || _busy) return;
    if (_title.text.trim().isEmpty || _introduction.text.trim().isEmpty) {
      setState(() => _error = '请填写标题和帖子正文');
      return;
    }
    final provider = context.read<StoryProvider>();
    final file = _file;
    final detail = <String, dynamic>{
      ..._original!,
      'storyId': _id.text.trim(),
      'title': _title.text.trim(),
      'author': _author.text.trim(),
      'summary': _summary.text.trim(),
      'tags': _tags.text
          .split(RegExp(r'[,，\n]'))
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList(),
      'introduction': _introduction.text.trim(),
      'memories': _lines(_memories.text),
      'images': _lines(_images.text),
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.publish(_config!, detail, file, isNew: _isNew);
      if (!mounted) return;
      final updated = StoryCatalogEntry.fromJson({...detail, 'file': file});
      setState(() {
        _entries.removeWhere((e) => e.storyId == updated.storyId);
        _entries.insert(0, updated);
        _entry = updated;
        _original = detail;
        _isNew = false;
      });
      showAppToast('帖子已发布');
      if (provider.config == _config) await provider.loadCatalog(force: true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _backToList() {
    if (_busy) return;
    _selection++;
    setState(() {
      _original = null;
      _entry = null;
      _isNew = false;
      _loadingDetail = false;
      _error = null;
    });
  }

  Future<void> _deletePost(StoryCatalogEntry entry) async {
    if (_busy) return;
    final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
              title: const Text('删除帖子？'),
              content: Text('将从社区删除「${entry.title}」及其详情文件。此操作无法撤销。'),
              actions: [
                CupertinoDialogAction(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                CupertinoDialogAction(
                    isDestructiveAction: true,
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除')),
              ],
            ));
    if (confirmed != true || !mounted || _busy) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.deletePost(_config!, entry);
      if (!mounted) return;
      setState(() => _entries.removeWhere((v) => v.storyId == entry.storyId));
      showAppToast('帖子已删除');
      final provider = context.read<StoryProvider>();
      if (provider.config == _config) await provider.loadCatalog(force: true);
    } catch (error) {
      if (mounted) setState(() => _error = '删除失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadImage() async {
    if (_busy) return;
    setState(() {
      _mediaBusy = true;
      _error = null;
    });
    try {
      Uint8List? bytes;
      if (widget.pickImage != null) {
        bytes = await widget.pickImage!();
      } else {
        final picked = await FilePickerHelper.pickFile();
        if (picked != null) bytes = await File(picked.path).readAsBytes();
      }
      if (bytes == null || !mounted) return;
      final codec = await ui.instantiateImageCodec(bytes);
      codec.dispose();
      final path = await widget.service.uploadImage(_config!, _file, bytes);
      if (!mounted) return;
      setState(() {
        _images.text = [..._lines(_images.text), path].join('\n');
        _previews[path] = bytes!;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '图片上传失败：$error');
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  Future<void> _deleteImage(String path) async {
    if (_busy) return;
    setState(() {
      _mediaBusy = true;
      _error = null;
    });
    try {
      await widget.service
          .deleteImage(_config!, _file, path, entry: _isNew ? null : _entry);
      if (!mounted) return;
      setState(() {
        _images.text = _lines(_images.text).where((p) => p != path).join('\n');
        _previews.remove(path);
      });
      final provider = context.read<StoryProvider>();
      if (!_isNew && provider.config == _config) {
        await provider.loadCatalog(force: true);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '图片删除失败：$error');
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = _original != null || _loadingDetail;
    final query = _search.text.trim().toLowerCase();
    final results = _entries
        .where((e) =>
            query.isEmpty ||
            [e.title, e.storyId, e.author, e.summary, ...e.tags]
                .join(' ')
                .toLowerCase()
                .contains(query))
        .toList();
    return CupertinoPageScaffold(
      navigationBar: settingsNavigationBar(
          context, editing ? (_isNew ? '创建帖子' : '编辑帖子') : '帖子快捷编辑',
          compact: true,
          onBack: editing ? _backToList : (_busy ? () {} : null),
          trailing: !editing
              ? null
              : CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _busy || _original == null ? null : _save,
                  child: _saving
                      ? const CupertinoActivityIndicator()
                      : Text(_isNew ? '发布' : '保存'),
                )),
      backgroundColor: context.scaffoldColor,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          if (!editing) CupertinoSliverRefreshControl(onRefresh: _prepare),
          SliverPadding(
              padding: settingsPageContentPadding(context),
              sliver: SliverList.list(children: [
                if (_checking)
                  const Padding(
                      padding: EdgeInsets.all(36),
                      child: Center(child: CupertinoActivityIndicator()))
                else ...[
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!,
                            style: TextStyle(color: context.textPrimaryColor))),
                  if (!_writable)
                    CupertinoButton(
                        onPressed: _prepare, child: const Text('重新检测'))
                  else if (editing) ...[
                    if (_loadingDetail)
                      const Center(child: CupertinoActivityIndicator())
                    else
                      _composer(),
                  ] else ...[
                    SettingsSection(children: [
                      SettingsRow(
                        icon: CupertinoIcons.add_circled,
                        title: const Text('创建新帖子'),
                        subtitle: const Text('编写正文、标签和首次导入的记忆点'),
                        showChevron: true,
                        onTap: _create,
                      )
                    ]),
                    Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: CupertinoSearchTextField(
                          key: const Key('story-editor-search'),
                          controller: _search,
                          placeholder: '搜索标题、编号、作者或标签',
                          onChanged: (_) => setState(() {}),
                        )),
                    SettingsSection(title: '帖子（${results.length}）', children: [
                      if (results.isEmpty)
                        SettingsRow(
                            title: Text(
                                query.isEmpty ? '暂无帖子，创建第一篇吧' : '没有找到匹配的帖子')),
                      for (final entry in results)
                        GestureDetector(
                            onLongPress:
                                _busy ? null : () => _deletePost(entry),
                            child: SettingsRow(
                                leading: CupertinoButton(
                                  key: ValueKey('delete-post:${entry.storyId}'),
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(28, 40),
                                  onPressed:
                                      _busy ? null : () => _deletePost(entry),
                                  child: const Icon(CupertinoIcons.trash,
                                      size: 20,
                                      color: CupertinoColors.destructiveRed),
                                ),
                                title: Text(entry.title),
                                subtitle: Text(
                                    '${entry.author} · ${entry.storyId}\n${entry.summary}'),
                                showChevron: true,
                                onTap: _busy ? null : () => _select(entry))),
                    ]),
                    Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        child: Text(_saving ? '正在删除…' : '下拉刷新 · 长按帖子删除',
                            style: TextStyle(
                                color: context.textSecondaryColor,
                                fontSize: 12))),
                  ],
                ],
              ])),
        ],
      ),
    );
  }

  Widget _composer() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: context.fieldBgColor, shape: BoxShape.circle),
                child: Icon(CupertinoIcons.person_fill,
                    color: context.textSecondaryColor)),
            const SizedBox(width: 12),
            Expanded(
                child: Text(
                    _author.text.trim().isEmpty ? '分享你的故事' : _author.text,
                    style: TextStyle(
                        color: context.textPrimaryColor,
                        fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 16),
          _input('标题（必填）', _title, placeholder: '为故事起一个标题', title: true),
          const SizedBox(height: 12),
          _input('帖子正文（必填）', _introduction,
              placeholder: '有什么故事想分享？', lines: 6, maxLines: null),
          const SizedBox(height: 12),
          if (_lines(_images.text).isNotEmpty)
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final path in _lines(_images.text)) _imagePreview(path),
            ]),
          Row(children: [
            CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                onPressed: _busy ? null : _uploadImage,
                child: const Row(children: [
                  Icon(CupertinoIcons.photo, size: 22),
                  SizedBox(width: 6),
                  Text('添加图片')
                ])),
            const Spacer(),
            if (_mediaBusy) const CupertinoActivityIndicator(),
          ]),
          Container(height: 0.5, color: context.settingsDividerColor),
          _disclosure('标签与发布信息', _showMetadata,
              () => setState(() => _showMetadata = !_showMetadata)),
          if (_showMetadata) ...[
            _field('标签（用逗号分隔）', _tags),
            _field('作者', _author),
            _field('摘要', _summary, lines: 2),
            _field('故事编号', _id, readOnly: !_isNew),
          ],
          _disclosure('故事记忆点（可选）', _showMemories,
              () => setState(() => _showMemories = !_showMemories)),
          if (_showMemories) ...[
            Text('每个非空行作为一条记忆点；可用空行分隔段落，空行不会导入。',
                style:
                    TextStyle(fontSize: 12, color: context.textSecondaryColor)),
            const SizedBox(height: 8),
            _input('记忆点（每行一条）', _memories,
                placeholder: '输入首次导入的记忆点', lines: 4, maxLines: null),
          ],
          _disclosure('图片路径（可选）', _showPaths,
              () => setState(() => _showPaths = !_showPaths)),
          if (_showPaths)
            _input('图片相对路径（每行一条，可留空）', _images,
                placeholder: 'img/图片文件名.png',
                lines: 2,
                maxLines: null,
                onChanged: (_) => setState(() {})),
        ]),
      );

  Widget _disclosure(String label, bool open, VoidCallback onTap) =>
      CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 12),
        onPressed: _busy ? null : onTap,
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14, color: context.textSecondaryColor))),
          Icon(open ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
              size: 14),
        ]),
      );

  Widget _imagePreview(String path) {
    Widget image;
    try {
      final bytes = _previews[path];
      final uri = widget.service.imageUri(_config!, _file, path);
      Widget failure(BuildContext context, Object error, StackTrace? stack) =>
          Center(
              child: Text('图片无法预览',
                  style: TextStyle(color: context.textSecondaryColor)));
      image = bytes != null
          ? Image.memory(bytes,
              fit: BoxFit.cover, width: 144, height: 144, errorBuilder: failure)
          : Image.network(uri.toString(),
              headers: StoryService.staticHeaders(_config!, uri),
              fit: BoxFit.cover,
              width: 144,
              height: 144,
              errorBuilder: failure);
    } catch (_) {
      image = const Center(child: Text('图片路径无效'));
    }
    return SizedBox(
        width: 144,
        height: 144,
        child: Stack(children: [
          Positioned.fill(
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(14), child: image)),
          Positioned(
              right: 2,
              top: 2,
              child: CupertinoButton(
                  key: ValueKey('delete-image:$path'),
                  padding: const EdgeInsets.all(6),
                  minimumSize: const Size(32, 32),
                  onPressed: _busy ? null : () => _deleteImage(path),
                  child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                          color: Color(0xCC000000), shape: BoxShape.circle),
                      child: const Icon(CupertinoIcons.xmark,
                          color: CupertinoColors.white, size: 14)))),
        ]));
  }

  Widget _input(String label, TextEditingController controller,
          {int lines = 1,
          int? maxLines = 1,
          bool readOnly = false,
          bool title = false,
          String? placeholder,
          ValueChanged<String>? onChanged}) =>
      CupertinoTextField(
        key: ValueKey(label),
        controller: controller,
        readOnly: readOnly || _busy,
        minLines: lines,
        maxLines: maxLines,
        placeholder: placeholder,
        placeholderStyle: TextStyle(
            color: context.textSecondaryColor, fontSize: title ? 20 : 16),
        padding: const EdgeInsets.symmetric(vertical: 8),
        style: TextStyle(
            color: context.textPrimaryColor,
            fontSize: title ? 20 : 16,
            fontWeight: title ? FontWeight.w600 : FontWeight.normal,
            height: 1.5),
        decoration: null,
        onChanged: onChanged,
      );

  Widget _field(String label, TextEditingController controller,
          {int lines = 1, bool readOnly = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style:
                  TextStyle(fontSize: 12, color: context.textSecondaryColor)),
          _input(label, controller,
              lines: lines, maxLines: lines, readOnly: readOnly),
        ]),
      );
}

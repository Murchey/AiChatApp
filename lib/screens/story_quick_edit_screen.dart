import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../config/theme.dart';
import '../models/story_package.dart';
import '../providers/story_provider.dart';
import '../services/story_editing_service.dart';
import '../utils/app_toast.dart';
import '../widgets/settings/settings_ui.dart';

class StoryQuickEditScreen extends StatefulWidget {
  final StoryEditingService service;
  const StoryQuickEditScreen(
      {super.key, this.service = const StoryEditingService()});

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
    });
  }

  Future<void> _select(StoryCatalogEntry entry) async {
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
      _memories.text = story.memories.map((m) => m.content).join('\n');
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
    if (_original == null || _saving) return;
    if (_title.text.trim().isEmpty || _introduction.text.trim().isEmpty) {
      setState(() => _error = '请填写标题和帖子正文');
      return;
    }
    final provider = context.read<StoryProvider>();
    final file = _isNew ? 'assets/${_id.text.trim()}/1.json' : _entry!.file;
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
    _selection++;
    setState(() {
      _original = null;
      _entry = null;
      _isNew = false;
      _loadingDetail = false;
      _error = null;
    });
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
      navigationBar: settingsNavigationBar(context, '帖子快捷编辑',
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _saving || _original == null ? null : _save,
            child: _saving
                ? const CupertinoActivityIndicator()
                : Text(_isNew ? '发布' : '保存'),
          )),
      backgroundColor: context.scaffoldColor,
      child: ListView(
        padding: settingsPageContentPadding(context),
        children: [
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
              CupertinoButton(onPressed: _prepare, child: const Text('重新检测'))
            else if (editing) ...[
              CupertinoButton(
                  onPressed: _saving ? null : _backToList,
                  child: const Text('返回帖子列表')),
              if (_loadingDetail)
                const Center(child: CupertinoActivityIndicator())
              else
                SettingsSection(title: _isNew ? '新建帖子' : '编辑帖子', children: [
                  _field('故事编号', _id, readOnly: !_isNew),
                  _field('标题（必填）', _title),
                  _field('作者', _author),
                  _field('标签（用逗号分隔）', _tags),
                  _field('摘要', _summary, lines: 2),
                  _field('帖子正文（必填）', _introduction, lines: 6),
                  _field('记忆点（每行一条）', _memories, lines: 5),
                  _field('图片相对路径（每行一条，可留空）', _images, lines: 2),
                ]),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: CupertinoSearchTextField(
                    key: const Key('story-editor-search'),
                    controller: _search,
                    placeholder: '搜索标题、编号、作者或标签',
                    onChanged: (_) => setState(() {}),
                  )),
              SettingsSection(title: '帖子（${results.length}）', children: [
                if (results.isEmpty)
                  SettingsRow(
                      title: Text(query.isEmpty ? '暂无帖子，创建第一篇吧' : '没有找到匹配的帖子')),
                for (final entry in results)
                  SettingsRow(
                      title: Text(entry.title),
                      subtitle: Text(
                          '${entry.author} · ${entry.storyId}\n${entry.summary}'),
                      showChevron: true,
                      onTap: () => _select(entry)),
              ]),
              CupertinoButton(onPressed: _prepare, child: const Text('刷新帖子列表')),
            ],
          ],
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller,
          {int lines = 1, bool readOnly = false}) =>
      SettingsRow(
        title: Text(label),
        subtitle: CupertinoTextField(
          key: ValueKey(label),
          controller: controller,
          readOnly: readOnly || _saving,
          minLines: lines,
          maxLines: lines,
          padding: const EdgeInsets.all(10),
          style: TextStyle(color: context.textPrimaryColor),
          decoration: BoxDecoration(
              color: context.fieldBgColor,
              borderRadius: BorderRadius.circular(8)),
        ),
      );
}

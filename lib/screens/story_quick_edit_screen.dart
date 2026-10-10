import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../models/story_package.dart';
import '../providers/story_provider.dart';
import '../services/story_service.dart';
import '../utils/app_toast.dart';
import '../widgets/settings/settings_ui.dart';

class StoryQuickEditScreen extends StatefulWidget {
  const StoryQuickEditScreen({super.key});

  @override
  State<StoryQuickEditScreen> createState() => _StoryQuickEditScreenState();
}

class _StoryQuickEditScreenState extends State<StoryQuickEditScreen> {
  StoryCatalogEntry? _entry;
  StoryPackage? _story;
  late final TextEditingController _title;
  late final TextEditingController _summary;
  late final TextEditingController _introduction;
  late final TextEditingController _memories;
  bool _checking = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _summary = TextEditingController();
    _introduction = TextEditingController();
    _memories = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    _introduction.dispose();
    _memories.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final provider = context.read<StoryProvider>();
    try {
      await provider.init();
      await StoryService.probeStaticWrite(provider.config);
      if (provider.entries.isEmpty) await provider.loadCatalog(force: true);
      if (mounted) setState(() => _checking = false);
    } catch (error) {
      if (mounted)
        setState(() {
          _checking = false;
          _error = '$error';
        });
    }
  }

  Future<void> _select(StoryCatalogEntry entry) async {
    final provider = context.read<StoryProvider>();
    setState(() {
      _entry = entry;
      _story = null;
      _error = null;
    });
    try {
      final story = await provider.loadPackage(entry);
      if (!mounted) return;
      _title.text = story.title;
      _summary.text = story.summary;
      _introduction.text = story.introduction;
      _memories.text = story.memories.map((m) => m.content).join('\n');
      setState(() => _story = story);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _save() async {
    final entry = _entry;
    final story = _story;
    final provider = context.read<StoryProvider>();
    if (entry == null || story == null) return;
    setState(() => _saving = true);
    try {
      final indexUri = StoryService.staticIndexUri(provider.config);
      final detailUri = StoryService.resolveStaticFile(indexUri, entry.file);
      final memories = _memories.text
          .split('\n')
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toList();
      final detail = <String, dynamic>{
        'schemaVersion': 2,
        'storyId': story.storyId,
        'version': story.version,
        'title': _title.text.trim(),
        'author': story.author,
        'publishedAt': story.publishedAt,
        'summary': _summary.text.trim(),
        'tags': story.tags,
        'introduction': _introduction.text,
        'memories': memories,
        'images': story.images,
      };
      await StoryService.putStaticJson(provider.config, detailUri, detail);
      final updated = StoryCatalogEntry(
          storyId: entry.storyId,
          version: entry.version,
          title: _title.text.trim(),
          author: entry.author,
          summary: _summary.text.trim(),
          publishedAt: entry.publishedAt,
          tags: entry.tags,
          file: entry.file,
          downloadCount: entry.downloadCount);
      final decoded = await StoryService.getStaticJson(
          provider.config, indexUri,
          filePath: provider.config.path);
      if (decoded is Map && decoded['stories'] is List) {
        final index = decoded.cast<String, dynamic>();
        index['stories'] = (decoded['stories'] as List).map((v) {
          if (v is Map && v['storyId']?.toString() == entry.storyId)
            return updated.toJson();
          return v;
        }).toList();
        await StoryService.putStaticJson(provider.config, indexUri, index);
      }
      if (mounted) showAppToast('帖子已保存');
    } catch (error) {
      if (mounted) showAppToast('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoryProvider>();
    return CupertinoPageScaffold(
      navigationBar: settingsNavigationBar(context, '帖子快捷编辑',
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _saving || _story == null ? null : _save,
            child: const Text('保存'),
          )),
      backgroundColor: context.scaffoldColor,
      child: ListView(
        padding: settingsPageContentPadding(context),
        children: [
          if (_checking)
            const Padding(
                padding: EdgeInsets.all(36),
                child: Center(child: CupertinoActivityIndicator()))
          else if (_error != null)
            Padding(
                padding: const EdgeInsets.all(20),
                child: Text('写权限检测失败：$_error',
                    style: TextStyle(color: context.textSecondaryColor)))
          else ...[
            SettingsSection(title: '选择帖子', children: [
              for (final entry in provider.entries)
                SettingsRow(
                    title: Text(entry.title),
                    subtitle: Text(entry.summary),
                    showChevron: true,
                    onTap: () => _select(entry)),
            ]),
            if (_story != null)
              SettingsSection(title: '编辑内容', children: [
                _field('标题', _title),
                _field('摘要', _summary),
                _field('帖子正文', _introduction, lines: 6),
                _field('记忆点（每行一条）', _memories, lines: 5),
              ]),
          ],
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller,
          {int lines = 1}) =>
      SettingsRow(
        title: Text(label),
        subtitle: CupertinoTextField(
            controller: controller,
            minLines: lines,
            maxLines: lines,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: context.fieldBgColor,
                borderRadius: BorderRadius.circular(8))),
      );
}

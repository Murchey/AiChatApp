import 'package:flutter/cupertino.dart';
import '../models/story_index.dart';
import '../config/theme.dart';

class StoryIndexSelector extends StatelessWidget {
  final List<StoryIndexReference> indexes;
  final String? selected;
  final bool loading;
  final Future<void> Function(String) onSelected;
  const StoryIndexSelector(
      {super.key,
      required this.indexes,
      required this.selected,
      required this.onSelected,
      this.loading = false});

  @override
  Widget build(BuildContext context) {
    final matches = indexes.where((v) => v.file == selected);
    final title = matches.isEmpty ? '最新故事' : matches.first.title;
    return CupertinoButton(
      key: const ValueKey('story-index-selector'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onPressed: loading
          ? null
          : () async {
              FocusScope.of(context).unfocus();
              final file = await showCupertinoModalPopup<String>(
                context: context,
                builder: (context) => Container(
                  key: const ValueKey('story-index-panel'),
                  height: MediaQuery.sizeOf(context).height * 0.5,
                  decoration: BoxDecoration(
                    color: context.scaffoldColor,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SafeArea(
                    top: false,
                    child: Column(children: [
                      const SizedBox(height: 10),
                      Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: context.textSecondaryColor
                                .withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(2),
                          )),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                        child: Row(children: [
                          Expanded(
                              child: Text('选择索引',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: context.textPrimaryColor))),
                          CupertinoButton(
                            padding: const EdgeInsets.all(10),
                            onPressed: () => Navigator.pop(context),
                            child: const Icon(CupertinoIcons.xmark, size: 18),
                          ),
                        ]),
                      ),
                      Expanded(
                          child: ListView.separated(
                        key: const ValueKey('story-index-panel-list'),
                        padding: EdgeInsets.zero,
                        itemCount: indexes.length,
                        separatorBuilder: (_, __) => Container(
                            height: 0.5,
                            margin: const EdgeInsets.symmetric(horizontal: 20),
                            color: context.settingsDividerColor),
                        itemBuilder: (context, i) {
                          final index = indexes[i];
                          final active = index.file == selected;
                          return CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            onPressed: () => Navigator.pop(context, index.file),
                            child: Row(children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(index.title,
                                        style: TextStyle(
                                            color: context.textPrimaryColor,
                                            fontSize: 16)),
                                    const SizedBox(height: 4),
                                    Text(index.file,
                                        style: TextStyle(
                                            color: context.textSecondaryColor,
                                            fontSize: 12)),
                                  ])),
                              if (active)
                                Icon(CupertinoIcons.check_mark,
                                    size: 20, color: context.accentColor),
                            ]),
                          );
                        },
                      )),
                    ]),
                  ),
                ),
              );
              if (file != null) await onSelected(file);
            },
      child: Row(children: [
        Expanded(child: Text('索引：$title', overflow: TextOverflow.ellipsis)),
        const Icon(CupertinoIcons.chevron_down, size: 14),
      ]),
    );
  }
}

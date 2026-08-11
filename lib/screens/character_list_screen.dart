import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../models/character.dart';
import '../providers/character_provider.dart';
import '../widgets/alphabet_index_bar.dart';

class CharacterListScreen extends StatefulWidget {
  const CharacterListScreen({super.key});

  @override
  State<CharacterListScreen> createState() => _CharacterListScreenState();
}

class _CharacterListScreenState extends State<CharacterListScreen> {
  final Map<String, GlobalKey> _sectionKeys = {};
  bool _showIndexTooltip = false;
  String _currentTooltipLetter = '';

  @override
  void dispose() {
    _sectionKeys.clear();
    super.dispose();
  }

  /// 滚动到指定分组的字母标题（对齐到顶部）
  void _scrollToSection(String letter) {
    final key = _sectionKeys[letter];
    if (key?.currentContext == null) return;
    Scrollable.ensureVisible(
      key!.currentContext!,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: 0.0,
    );
  }

  /// 无数据字母就近滚动到下一个有数据的分组
  void _scrollToNearest(String letter, Set<String> availableLetters) {
    if (availableLetters.contains(letter)) {
      _scrollToSection(letter);
      return;
    }
    final letters = ['#', ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')];
    final index = letters.indexOf(letter);
    for (int i = index + 1; i < letters.length; i++) {
      if (availableLetters.contains(letters[i])) {
        _scrollToSection(letters[i]);
        return;
      }
    }
    for (int i = index - 1; i >= 0; i--) {
      if (availableLetters.contains(letters[i])) {
        _scrollToSection(letters[i]);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('通讯录'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {},
          child: const Icon(CupertinoIcons.search),
        ),
      ),
      child: Consumer<CharacterProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CupertinoActivityIndicator());
          }

          if (provider.characters.isEmpty) {
            return Center(
              child: Text(
                '暂无可用角色',
                style: TextStyle(color: context.textSecondaryColor),
              ),
            );
          }

          // 按拼音首字母分组排序
          final groups = provider.sortedCharactersGrouped;
          // 获取有数据的字母
          final availableLetters = groups.map((g) => g.key).toSet();
          // 为每个分组标题创建 GlobalKey
          for (final group in groups) {
            _sectionKeys.putIfAbsent(group.key, () => GlobalKey());
          }

          return Stack(
            children: [
              // 主列表（普通 ListView 一次性构建，GlobalKey 定位有效）
              Container(
                color: context.scaffoldColor,
                child: ListView(
                  padding: const EdgeInsets.only(right: 28),
                  children: [
                    for (final group in groups) ...[
                      // 字母标题
                      Container(
                        key: _sectionKeys[group.key],
                        width: double.infinity,
                        color: context.scaffoldColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          group.key,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ),
                      // 角色列表
                      for (final character in group.value)
                        CupertinoListTile(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          leading: _buildAvatar(context, character),
                          title: Text(
                            character.name,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              color: context.textPrimaryColor,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              character.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: context.textSecondaryColor,
                              ),
                            ),
                          ),
                          trailing: Icon(
                            CupertinoIcons.chevron_right,
                            size: 16,
                            color: context.textSecondaryColor,
                          ),
                          onTap: () {
                            Navigator.pushNamed(
                              context,
                              AppRoutes.characterDetail,
                              arguments: character.id,
                            );
                          },
                        ),
                      Container(
                        height: 0.5,
                        margin: const EdgeInsets.only(left: 76),
                        color: context.separatorColor,
                      ),
                    ],
                  ],
                ),
              ),
              // 右侧字母索引栏
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: AlphabetIndexBar(
                  availableLetters: availableLetters,
                  onLetterChanged: (letter) {
                    setState(() {
                      _showIndexTooltip = true;
                      _currentTooltipLetter = letter;
                    });
                    _scrollToNearest(letter, availableLetters);
                  },
                  onDragEnd: () {
                    setState(() {
                      _showIndexTooltip = false;
                    });
                  },
                ),
              ),
              // 字母提示气泡
              if (_showIndexTooltip)
                Positioned(
                  right: 48,
                  top: MediaQuery.of(context).size.height / 2 - 32,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: context.accentColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _currentTooltipLetter,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 角色头像：已设置显示图片，未设置显示默认用户图标
  Widget _buildAvatar(BuildContext context, Character character) {
    if (character.avatar.isNotEmpty) {
      return Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.accentColor.withValues(alpha: 0.15),
          image: DecorationImage(
            image: MemoryImage(base64Decode(character.avatar)),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.accentColor.withValues(alpha: 0.15),
      ),
      alignment: Alignment.center,
      child: Icon(
        CupertinoIcons.person_fill,
        size: 30,
        color: context.accentColor,
      ),
    );
  }
}

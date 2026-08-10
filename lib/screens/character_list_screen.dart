import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../providers/character_provider.dart';

class CharacterListScreen extends StatelessWidget {
  const CharacterListScreen({super.key});

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

          // 按拼音首字母分组排序（类似手机通讯录）
          final groups = provider.sortedCharactersGrouped;
          return Container(
            color: context.listBgColor,
            child: ListView(
              children: [
                for (final group in groups) ...[
                  Container(
                    width: double.infinity,
                    color: context.scaffoldColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
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
                  for (final character in group.value)
                    CupertinoListTile(
                      leading: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: context.accentColor.withValues(alpha: 0.15),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          character.name.isNotEmpty ? character.name[0] : '?',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: context.accentColor,
                          ),
                        ),
                      ),
                      title: Text(
                        character.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          character.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
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
                    margin: const EdgeInsets.only(left: 72),
                    color: context.separatorColor,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

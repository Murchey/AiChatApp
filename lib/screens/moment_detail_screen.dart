import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../models/character.dart';
import '../models/moment.dart';
import '../providers/character_provider.dart';
import '../widgets/moment_card.dart';
import '../widgets/moments/moment_interactions.dart';

/// 单条朋友圈详情：展示完整动态和全部评论，底部固定评论输入栏。
class MomentDetailScreen extends StatefulWidget {
  final String characterId;
  final String momentId;

  const MomentDetailScreen({
    super.key,
    required this.characterId,
    required this.momentId,
  });

  @override
  State<MomentDetailScreen> createState() => _MomentDetailScreenState();
}

class _MomentDetailScreenState extends State<MomentDetailScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _replyTo;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Character? _character(CharacterProvider provider) =>
      provider.getCharacterById(widget.characterId);

  Moment? _moment(Character? character) {
    if (character == null) return null;
    for (final moment in character.moments) {
      if (moment.id == widget.momentId) return moment;
    }
    return null;
  }

  void _startReply(String? name) {
    setState(() => _replyTo = name);
    _focusNode.requestFocus();
  }

  Future<void> _sendComment(Character character, Moment moment) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final replyTo = _replyTo;
    _controller.clear();
    setState(() => _replyTo = null);
    await submitMomentComment(
      context,
      character: character,
      moment: moment,
      text: text,
      replyTo: replyTo,
    );
  }

  Widget _composer(BuildContext context, Character character, Moment moment) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          12,
          8,
          12,
          8 + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: context.listBgColor,
          border: Border(
            top: BorderSide(color: context.separatorColor),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLength: 100,
                maxLines: 1,
                placeholder: _replyTo == null ? '说点什么...' : '回复 $_replyTo',
                placeholderStyle: TextStyle(color: context.textSecondaryColor),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                onSubmitted: (_) => _sendComment(character, moment),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) {
                final canSend = value.text.trim().isNotEmpty;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: canSend ? () => _sendComment(character, moment) : null,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: canSend
                          ? context.accentColor
                          : context.separatorColor,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      CupertinoIcons.arrow_up,
                      size: 18,
                      color: CupertinoColors.white,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('朋友圈详情'),
      ),
      backgroundColor: context.momentsBgColor,
      child: Consumer<CharacterProvider>(
        builder: (context, provider, _) {
          final character = _character(provider);
          final moment = _moment(character);
          if (character == null || moment == null) {
            return Center(
              child: Text(
                '这条朋友圈已不存在',
                style: TextStyle(color: context.textSecondaryColor),
              ),
            );
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.only(
                    top: MediaQuery.paddingOf(context).top + 12,
                    left: 16,
                    right: 16,
                    bottom: 20,
                  ),
                  children: [
                    MomentCard(
                      character: character,
                      moment: moment,
                      detailMode: true,
                      onReplyRequested: _startReply,
                    ),
                  ],
                ),
              ),
              _composer(context, character, moment),
            ],
          );
        },
      ),
    );
  }
}

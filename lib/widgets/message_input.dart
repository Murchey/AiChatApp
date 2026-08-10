import 'package:flutter/cupertino.dart';
import '../config/theme.dart';

class MessageInput extends StatefulWidget {
  final Function(String) onSend;

  const MessageInput({super.key, required this.onSend});

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _hasText = _controller.text.trim().isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSend(text);
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: context.navBarColor,
        border: Border(
          top: BorderSide(color: context.separatorColor),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {},
              child: Icon(
                CupertinoIcons.add_circled,
                color: context.textSecondaryColor,
              ),
            ),
            Expanded(
              child: CupertinoTextField(
                controller: _controller,
                placeholder: '输入消息...',
                maxLines: 4,
                minLines: 1,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                style: TextStyle(
                  fontSize: 16,
                  color: context.textPrimaryColor,
                ),
                decoration: BoxDecoration(
                  color: context.fieldBgColor,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CupertinoButton.filled(
              onPressed: _hasText ? _handleSend : null,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              borderRadius: BorderRadius.circular(20),
              child: Text(
                '发送',
                style: TextStyle(
                  color: _hasText
                      ? CupertinoColors.white
                      : CupertinoColors.systemGrey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

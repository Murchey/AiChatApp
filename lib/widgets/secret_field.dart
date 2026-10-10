import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// Keeps the original field styling while offering reveal and copy actions.
class SecretField extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;
  final Widget Function(bool revealed) builder;
  const SecretField(
      {super.key,
      required this.controller,
      required this.builder,
      this.enabled = true});

  @override
  State<SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<SecretField> {
  bool _revealed = false;
  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.builder(false);
    return Row(children: [
      Expanded(child: widget.builder(_revealed)),
      CupertinoButton(
        padding: const EdgeInsets.all(8),
        onPressed: () => setState(() => _revealed = !_revealed),
        child: Icon(_revealed ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
            semanticLabel: _revealed ? '隐藏密钥' : '显示密钥'),
      ),
      if (_revealed)
        CupertinoButton(
          padding: const EdgeInsets.all(8),
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: widget.controller.text)),
          child: const Icon(CupertinoIcons.doc_on_doc, semanticLabel: '复制密钥'),
        ),
    ]);
  }
}

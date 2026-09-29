import 'package:flutter/cupertino.dart';

/// 弹出单字段编辑框
void showEditFieldDialog(
  BuildContext context, {
  required String title,
  required String initial,
  required String hint,
  bool multiline = false,
  int? maxLength,
  required void Function(String value) onSave,
}) {
  final controller = TextEditingController(text: initial);
  showCupertinoDialog<void>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: multiline
            ? CupertinoTextField(
                controller: controller,
                maxLines: 4,
                minLines: 2,
                padding: const EdgeInsets.all(10),
                placeholder: hint,
                maxLength: maxLength,
              )
            : CupertinoTextField(
                controller: controller,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                placeholder: hint,
                maxLength: maxLength,
              ),
      ),
      actions: [
        CupertinoDialogAction(
          child: const Text('取消'),
          onPressed: () => Navigator.pop(ctx),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () {
            onSave(controller.text.trim());
            Navigator.pop(ctx);
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

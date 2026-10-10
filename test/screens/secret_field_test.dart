import 'package:ai_chat/widgets/secret_field.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reveal permits selection and copying; hide restores masking',
      (tester) async {
    final controller = TextEditingController(text: 'sample-secret');
    addTearDown(controller.dispose);
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(CupertinoApp(
        home: CupertinoPageScaffold(
            child: Center(
      child: SecretField(
          controller: controller,
          builder: (revealed) => CupertinoTextField(
              controller: controller, obscureText: !revealed)),
    ))));
    expect(
        tester
            .widget<CupertinoTextField>(find.byType(CupertinoTextField))
            .obscureText,
        true);
    await tester.tap(find.byIcon(CupertinoIcons.eye));
    await tester.pump();
    expect(
        tester
            .widget<CupertinoTextField>(find.byType(CupertinoTextField))
            .obscureText,
        false);
    await tester.tap(find.byIcon(CupertinoIcons.doc_on_doc));
    await tester.pump();
    expect(copied, 'sample-secret');
    await tester.tap(find.byIcon(CupertinoIcons.eye_slash));
    await tester.pump();
    expect(
        tester
            .widget<CupertinoTextField>(find.byType(CupertinoTextField))
            .obscureText,
        true);
  });
}

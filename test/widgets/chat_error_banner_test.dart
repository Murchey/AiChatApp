import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/config/theme.dart';
import 'package:ai_chat/widgets/chat/chat_error_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 足够长的错误文本：错误条截断为 2 行，弹窗内应完整展示
  final longError = '请求出错（HTTP 429）：请求限流或账户额度不足，' * 20;

  Widget wrap(Widget child) {
    return CupertinoApp(
      theme: AppTheme.buildTheme(
        brightness: Brightness.light,
        accent: AppColors.presetColors.first,
      ),
      home: CupertinoPageScaffold(child: Center(child: child)),
    );
  }

  testWidgets('点击错误条弹出完整报错弹窗，可一键复制', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    var dismissed = false;
    await tester.pumpWidget(wrap(ChatErrorBanner(
      error: longError,
      onDismiss: () => dismissed = true,
    )));
    await tester.pump();

    // 弹窗未打开时只显示截断的错误条
    expect(find.byType(SelectableText), findsNothing);

    await tester.tap(find.byType(ChatErrorBanner));
    await tester.pumpAndSettle();

    // 弹窗内完整展示全部错误文本
    expect(find.text('请求失败'), findsOneWidget);
    final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(selectable.data, longError);

    // 「复制」按钮复制完整文本
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(copied, longError);
    expect(find.text('请求失败'), findsNothing);
    expect(dismissed, isFalse);
  });

  testWidgets('长按错误条直接复制完整错误信息', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(wrap(ChatErrorBanner(
      error: longError,
      onDismiss: () {},
    )));
    await tester.pump();

    await tester.longPress(find.byType(ChatErrorBanner));
    await tester.pump();
    expect(copied, longError);
    // 长按复制不弹窗
    expect(find.byType(SelectableText), findsNothing);
  });

  testWidgets('弹窗可长按选择文本，关闭按钮与右上角关闭互不影响', (tester) async {
    await tester.pumpWidget(wrap(ChatErrorBanner(
      error: '鉴权失败（HTTP 401）',
      onDismiss: () {},
    )));
    await tester.pump();

    await tester.tap(find.byType(ChatErrorBanner));
    await tester.pumpAndSettle();
    // 弹窗（SelectableText）与背景错误条各自持有一份文本
    expect(find.text('鉴权失败（HTTP 401）', findRichText: true), findsNWidgets(2));

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNothing);
  });
}

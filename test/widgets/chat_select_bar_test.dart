import 'package:ai_chat/config/theme.dart';
import 'package:ai_chat/widgets/chat/chat_select_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('多选操作栏在窄屏下不溢出且删除可用', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var deleted = 0;
    await tester.pumpWidget(
      CupertinoApp(
        theme: AppTheme.buildTheme(
          brightness: Brightness.light,
          accent: AppColors.presetColors.first,
        ),
        home: CupertinoPageScaffold(
          child: ChatSelectBar(
            count: 99,
            selectingMemory: false,
            onCancel: () {},
            onForwardSingle: () {},
            onForwardMerge: () {},
            onDelete: () => deleted++,
          ),
        ),
      ),
    );

    expect(find.text('逐条转发'), findsOneWidget);
    expect(find.text('合并转发'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('删除'));
    expect(deleted, 1);
  });

  testWidgets('删除按钮在未选中消息时禁用', (tester) async {
    var deleted = 0;
    await tester.pumpWidget(
      CupertinoApp(
        theme: AppTheme.buildTheme(
          brightness: Brightness.light,
          accent: AppColors.presetColors.first,
        ),
        home: CupertinoPageScaffold(
          child: ChatSelectBar(
            count: 0,
            selectingMemory: false,
            onCancel: () {},
            onDelete: () => deleted++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('删除'));
    expect(deleted, 0);
  });
}

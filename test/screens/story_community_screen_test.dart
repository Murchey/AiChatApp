import 'package:ai_chat/config/theme.dart';
import 'package:ai_chat/providers/story_provider.dart';
import 'package:ai_chat/screens/story_community_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget themed(Widget child) {
    return CupertinoApp(
      theme: AppTheme.buildTheme(
        brightness: Brightness.light,
        accent: AppColors.presetColors.first,
      ),
      home: child,
    );
  }

  testWidgets('feed keeps source settings behind the navigation gear',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = StoryProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider.value(value: provider)],
        child: themed(const StoryCommunityScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('故事线社区'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.gear), findsOneWidget);
    expect(find.text('打开故事线设置'), findsOneWidget);
    expect(find.text('服务器地址'), findsNothing);

    await tester.tap(find.byIcon(CupertinoIcons.gear).last);
    await tester.pumpAndSettle();
    expect(find.text('故事线设置'), findsOneWidget);
    expect(find.text('服务器地址'), findsOneWidget);
    expect(find.text('故事来源'), findsOneWidget);
  });
}

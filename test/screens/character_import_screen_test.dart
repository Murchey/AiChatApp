import 'dart:async';

import 'package:ai_chat/models/character.dart';
import 'package:ai_chat/models/character_pack_entry.dart';
import 'package:ai_chat/providers/character_provider.dart';
import 'package:ai_chat/providers/chat_provider.dart';
import 'package:ai_chat/providers/memory_point_provider.dart';
import 'package:ai_chat/providers/settings_provider.dart';
import 'package:ai_chat/screens/character_import_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('角色导入显示进度弹窗并阻止重复触发', (tester) async {
    final provider = _SlowCharacterProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider(),
          ),
          ChangeNotifierProvider<CharacterProvider>.value(value: provider),
          ChangeNotifierProvider<MemoryPointProvider>(
            create: (_) => MemoryPointProvider(),
          ),
          ChangeNotifierProvider<ChatProvider>(
            create: (_) => ChatProvider(),
          ),
        ],
        child: CupertinoApp(
          home: CharacterImportScreen(
            zipName: '测试角色包',
            entries: [
              CharacterPackEntry(
                folderName: '测试角色',
                character: Character(
                  id: 'placeholder',
                  name: '测试角色',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('确定导入 (1)'));
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.byKey(const ValueKey('character-import-progress-dialog')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('character-import-progress-count')),
        findsOneWidget);
    expect(provider.callCount, 1);

    // 弹窗遮罩会拦截第二次点击，导入按钮也处于禁用状态。
    await tester.tap(find.text('正在导入...'), warnIfMissed: false);
    await tester.pump();
    expect(provider.callCount, 1);

    provider.completeImport();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(provider.callCount, 1);
    expect(find.text('导入成功'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('character-import-progress-dialog')),
      findsNothing,
    );
  });
}

class _SlowCharacterProvider extends CharacterProvider {
  final Completer<void> _gate = Completer<void>();
  int callCount = 0;

  void completeImport() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<Character> addCharacter(Character character) async {
    callCount++;
    await _gate.future;
    return character;
  }
}

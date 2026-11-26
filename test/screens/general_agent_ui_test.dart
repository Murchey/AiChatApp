import 'package:ai_chat/widgets/chat/chat_detail_prompt_panel.dart';
import 'package:ai_chat/models/character.dart';
import 'package:ai_chat/providers/character_provider.dart';
import 'package:ai_chat/screens/prompt_edit_screen.dart';
import 'package:provider/provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

class _PromptCharacters extends CharacterProvider {
  Character character =
      Character(id: 'general-agent', name: '助手', isGeneralAgent: true);

  @override
  Character? getCharacterById(String id) =>
      id == character.id ? character : null;

  @override
  Future<void> updateSystemPrompt(String id, String prompt) async {
    character = character.copyWith(systemPrompt: prompt);
    notifyListeners();
  }
}

void main() {
  testWidgets('一般智能体详情显示智能体提示词且隐藏记忆点管理', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoPageScaffold(
          child: ChatDetailPromptPanel(
            onOpenPrompt: _noop,
            onOpenMemory: _noop,
            isGeneralAgent: true,
          ),
        ),
      ),
    );

    expect(find.text('定义智能体的任务、行为与回答方式，点击进入编辑'), findsOneWidget);
    expect(find.text('记忆点管理'), findsNothing);
  });

  testWidgets('一般智能体离开提示词编辑页前保存最后输入', (tester) async {
    final provider = _PromptCharacters();
    await tester.pumpWidget(ChangeNotifierProvider<CharacterProvider>.value(
      value: provider,
      child: const CupertinoApp(
        home: PromptEditScreen(
          characterId: 'general-agent',
          characterName: '助手',
        ),
      ),
    ));
    await tester.enterText(find.byType(CupertinoTextField), '最后一段提示词');
    await tester.pump();
    await tester.pumpWidget(const CupertinoApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(provider.getCharacterById('general-agent')?.systemPrompt, '最后一段提示词');
  });

  testWidgets('普通角色详情保留角色提示词和记忆点管理', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoPageScaffold(
          child: ChatDetailPromptPanel(
            onOpenPrompt: _noop,
            onOpenMemory: _noop,
          ),
        ),
      ),
    );

    expect(find.text('定义角色对话时的行为与设定，点击进入编辑'), findsOneWidget);
    expect(find.text('记忆点管理'), findsOneWidget);
  });
}

void _noop() {}

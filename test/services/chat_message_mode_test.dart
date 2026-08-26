import 'package:ai_chat/services/llm_service.dart';
import 'package:ai_chat/services/prompt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('roleplay output instruction describes bracket action flow', () {
    final instruction = PromptBuilder.buildOutputInstruction(
      characterName: '角色',
      replyToUser: true,
      roleplayMode: true,
    );

    expect(instruction, contains('括号动作流语C格式'));
    expect(instruction, contains('（动作/神态/环境描写）'));
    expect(instruction, isNot(contains('必须且只能是一个 JSON 字符串数组')));
  });

  test('roleplay prompt only contains persona, relationship and memories', () {
    final prompt = PromptBuilder.buildSystemPrompt(
      baseSystemPrompt: '你是一位不苟言笑的剑客。',
      characterName: '角色原名',
      userNickname: '不应出现的用户资料',
      userRelationship: '恋人',
      currentTime: DateTime(2026, 8, 26, 3),
      activeStart: '09:00',
      activeEnd: '22:00',
      memoryPoints: const ['曾在雨夜共撑一把伞'],
      extraContext: '【近期朋友圈】不应出现\n【角色资料卡】备注：不应出现',
      roleplayMode: true,
    );

    expect(prompt, contains('你是一位不苟言笑的剑客。'));
    expect(prompt, contains('你与用户的关系：恋人'));
    expect(prompt, contains('曾在雨夜共撑一把伞'));
    expect(prompt, isNot(contains('不应出现的用户资料')));
    expect(prompt, isNot(contains('近期朋友圈')));
    expect(prompt, isNot(contains('角色资料卡')));
    expect(prompt, isNot(contains('活跃时段')));
    expect(prompt, isNot(contains('当前时间')));
  });

  test('roleplay output instruction never appends current time', () {
    final instruction = PromptBuilder.buildOutputInstruction(
      characterName: '角色',
      currentTime: DateTime(2026, 8, 26, 3),
      roleplayMode: true,
    );

    expect(instruction, isNot(contains('当前时间')));
    expect(instruction, isNot(contains('2026-08-26')));
  });

  test('roleplay parser preserves the complete action flow', () {
    const raw = '（指尖轻轻叩击桌面，目光并未从书页上移开）这茶凉了，换一盏吧。'
        '（抬眼看向你，语气平淡）你方才说的事，我再想想。';

    expect(LLMService.parseRoleplayMessage(raw), [raw]);
  });

  test('roleplay parser removes a markdown text fence only', () {
    const raw = '```text\n（抬眼）你来了。\n```';

    expect(LLMService.parseRoleplayMessage(raw), ['（抬眼）你来了。']);
  });
}

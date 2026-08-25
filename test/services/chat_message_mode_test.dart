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

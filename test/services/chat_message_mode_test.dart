import 'package:ai_chat/services/llm_service.dart';
import 'package:ai_chat/services/prompt_builder.dart';
import 'package:ai_chat/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('roleplay reply separates persisted choices from visible narration', () {
    const raw = '（抬眼看向你）雨还没停。\n'
        '<<<CHOICES>>>["撑伞靠近","继续沉默","提起旧约","转身离开"]<<<END_CHOICES>>>';

    final reply = LLMService.parseRoleplayReply(raw);

    expect(reply.content, '（抬眼看向你）雨还没停。');
    expect(reply.choices, ['撑伞靠近', '继续沉默', '提起旧约', '转身离开']);
  });

  test('stream usage chunk parses token usage even without text choices', () {
    final chunk = LLMService.parseStreamChunk(
      '{"choices":[],"usage":{"prompt_tokens":123,"completion_tokens":45,"total_tokens":168}}',
    );

    expect(chunk.content, isEmpty);
    expect(chunk.usage.promptTokens, 123);
    expect(chunk.usage.completionTokens, 45);
    expect(chunk.usage.totalTokens, 168);
  });

  test(
      'companionship roleplay prompt keeps user choice while avoiding forced drama',
      () {
    final prompt = PromptBuilder.buildSystemPrompt(
      characterName: '角色',
      userNickname: '用户',
      userRelationship: '恋人',
      currentTime: DateTime(2026, 8, 26),
      roleplayMode: true,
      roleplayProgressionStyle: 'companionship',
    );

    expect(prompt, contains('剧情推进风格：情感陪伴'));
    expect(prompt, contains('不主动引入高强度冲突'));
    expect(prompt, contains('必须由用户自己决定'));
  });

  test('memory compression prompt preserves dialogue context and stays concise',
      () {
    expect(LLMService.kCompressSystemPrompt, contains('说话人'));
    expect(LLMService.kCompressSystemPrompt, contains('不超过 600 字'));
    expect(LLMService.kCompressSystemPrompt, contains('直接输出摘要内容'));
  });

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

  test('non-stream roleplay instruction does not request embedded choices', () {
    final instruction = PromptBuilder.buildOutputInstruction(
      characterName: '角色',
      replyToUser: true,
      roleplayMode: true,
      includeRoleplayChoices: false,
    );

    expect(instruction, isNot(contains('<<<CHOICES>>>')));
    expect(instruction, contains('括号动作流语C格式'));
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

  test(
      'roleplay prompt allows user-authored actions without taking user control',
      () {
    final prompt = PromptBuilder.buildSystemPrompt(
      characterName: '角色',
      userNickname: '用户',
      userRelationship: '同伴',
      currentTime: DateTime(2026, 8, 26),
      roleplayMode: true,
    );

    expect(prompt, contains('用户可以通过普通消息或“剧情行动”推进自己的角色与故事'));
    expect(prompt, contains('尊重用户已经明确写出的行动、台词和剧情结果'));
    expect(prompt, contains('不要擅自替用户追加未写出的行动、台词或决定'));
  });

  test('roleplay narration has its own message type', () {
    final message = Message(
      id: 'narration-1',
      conversationId: 'conversation-1',
      content: '（我推开门，走进客栈）',
      type: MessageType.narration,
      sender: MessageSender.user,
    );

    final restored = Message.fromJson(message.toJson());

    expect(restored.type, MessageType.narration);
    expect(restored.isFromUser, isTrue);
  });
}

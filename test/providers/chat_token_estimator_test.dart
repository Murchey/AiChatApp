import 'package:ai_chat/providers/api_provider.dart';
import 'package:ai_chat/providers/chat_token_estimator.dart';
import 'package:ai_chat/services/llm_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ApiModel model(String name, {int contextLength = 8192}) => ApiModel(
        id: name,
        displayName: name,
        modelName: name,
        contextLength: contextLength,
      );

  test('counts exact system, history and output instruction payload', () {
    final messages = <Map<String, Object>>[
      {'role': 'system', 'content': 'system'},
      {'role': 'assistant', 'content': 'history'},
      {'role': 'user', 'content': 'instruction'},
    ];
    final budget = ChatTokenEstimator.requestBudget(
      model: model('test', contextLength: 4096),
      messages: messages,
      requestedOutputTokens: 1024,
    );
    expect(
        budget.inputTokens,
        ChatTokenEstimator.estimateText('system') +
            ChatTokenEstimator.estimateText('history') +
            ChatTokenEstimator.estimateText('instruction') +
            15);
    expect(budget.outputTokens, 1024);
    expect(budget.safetyMarginTokens, 410);
    expect(budget.exceedsContext, isFalse);
  });

  test('uses effective output cap for reasoning models', () {
    expect(
        ChatTokenEstimator.effectiveOutputTokens(
            model('vendor/grok-4.3'), 1024),
        4096);
    expect(
        ChatTokenEstimator.effectiveOutputTokens(
            model('grok-4.3-non-reasoning'), 1024),
        1024);
  });

  test('visual reserve is independent of encoded image size', () {
    final budget = ChatTokenEstimator.requestBudget(
      model: model('test'),
      messages: <Map<String, Object>>[
        {
          'role': 'user',
          'content': [
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,${'A' * 1000000}'}
            }
          ],
        },
      ],
      requestedOutputTokens: 1024,
    );
    expect(budget.inputTokens, 4096 + 5);
    expect(budget.exceedsContext, isFalse);
  });

  test('rejects requests only when known context cannot fit reserve', () {
    final budget = ChatTokenEstimator.requestBudget(
      model: model('small', contextLength: 1024),
      messages: const [
        {'role': 'system', 'content': 'system'},
        {'role': 'user', 'content': 'instruction'},
      ],
      requestedOutputTokens: 1024,
    );
    expect(budget.exceedsContext, isTrue);
    expect(budget.ensureFits, throwsA(isA<LLMException>()));
    expect(
      ChatTokenEstimator.requestBudget(
        model: model('unknown', contextLength: 0),
        messages: const [
          {'role': 'system', 'content': 'system'},
        ],
        requestedOutputTokens: 1024,
      ).exceedsContext,
      isFalse,
    );
  });
}

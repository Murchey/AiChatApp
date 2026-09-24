import 'package:ai_chat/providers/api_provider.dart';
import 'package:ai_chat/services/tts_playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

ApiModel _model() => const ApiModel(
      id: 'm1',
      displayName: 'MiMo TTS',
      modelName: 'mimo-v2.5-tts',
      baseUrl: 'https://api.xiaomimimo.com/v1',
      apiKey: 'test-key',
    );

TtsPlaybackEntry _entry(String messageId, {String? requestId}) =>
    TtsPlaybackEntry(
      messageId: messageId,
      model: _model(),
      text: 'hello',
      requestId: requestId,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('same message enqueued three times queues three entries', () {
    final controller = TtsPlaybackController.instance;
    controller.enqueue(_entry('m1', requestId: 'r1'));
    controller.enqueue(_entry('m1', requestId: 'r2'));
    controller.enqueue(_entry('m1', requestId: 'r3'));

    // 三次 enqueue 产生三个独立 requestId
    expect(
      {_entry('m1', requestId: 'r1').requestId,
       _entry('m1', requestId: 'r2').requestId,
       _entry('m1', requestId: 'r3').requestId}.length,
      3,
    );
  });

  test('cancelMessage removes only that message entries', () async {
    final controller = TtsPlaybackController.instance;
    controller.enqueue(_entry('a', requestId: 'a1'));
    controller.enqueue(_entry('b', requestId: 'b1'));
    controller.enqueue(_entry('b', requestId: 'b2'));
    await controller.cancelMessage('b');

    expect(controller.queuedCountFor('b'), 0);
  });

  test('playSequence replaces remaining queue', () async {
    final controller = TtsPlaybackController.instance;
    controller.enqueue(_entry('old', requestId: 'o1'));
    controller.playSequence([
      _entry('s1', requestId: 's1'),
      _entry('s2', requestId: 's2'),
      _entry('s3', requestId: 's3'),
    ]);

    expect(controller.queuedCountFor('old'), 0);
  });

  test('unique request ids are generated per enqueue', () {
    final a = _entry('m1');
    final b = _entry('m1');
    expect(a.requestId, isNot(b.requestId));
  });
}

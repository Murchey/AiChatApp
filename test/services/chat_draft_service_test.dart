import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/services/chat_draft_service.dart';

void main() {
  test('unchanged and already queued drafts are not written again', () async {
    final gate = Completer<void>();
    final written = <String>[];
    final service = ChatDraftService(
        read: (_) async => 'saved',
        write: (_, text) async {
          await gate.future;
          written.add(text);
        });
    await service.load('a');
    await service.flushAll();
    expect(written, isEmpty);
    service.update('a', 'new');
    final first = service.flush('a');
    final second = service.flush('a');
    expect(identical(first, second), true);
    gate.complete();
    await first;
    await service.flushAll();
    service.update('a', 'new');
    await service.flush('a');
    expect(written, ['new']);
    service.reset();
  });
  test(
      'verbatim text survives flush and reopening, clearing only removes that conversation',
      () async {
    final disk = <String, String>{};
    final service = ChatDraftService(
        read: (id) async => disk[id],
        write: (id, text) async {
          disk[id] = text;
        });
    service.update('a', '  中文\n\n草稿  ');
    service.update('b', '另一个角色');
    await service.flushAll();
    service.reset();
    expect(await service.load('a'), '  中文\n\n草稿  ');
    await service.remove('a');
    expect(disk['a'], '');
    expect(disk['b'], '另一个角色');
    service.reset();
  });
  test('late disk read never replaces newly typed text', () async {
    final gate = Completer<String?>();
    final service =
        ChatDraftService(read: (_) => gate.future, write: (_, text) async {});
    final load = service.load('a');
    service.update('a', '新内容');
    gate.complete('旧内容');
    expect(await load, '新内容');
    service.reset();
  });
  test('writes serialize and newer edits are not cleared by older sends',
      () async {
    final gate = Completer<void>();
    final written = <String>[];
    final service = ChatDraftService(
        read: (_) async => '',
        write: (id, text) async {
          if (text == 'old') await gate.future;
          written.add(text);
        });
    service.update('a', 'old');
    final old = service.flush('a');
    service.update('a', 'new');
    final newer = service.flush('a');
    gate.complete();
    await Future.wait([old, newer]);
    await service.clearIfUnchanged('a', 'old');
    expect(written, ['old', 'new']);
    expect(await service.load('a'), 'new');
    service.reset();
  });
  test('a failed write does not poison subsequent saves', () async {
    var fails = true;
    String? saved;
    final service = ChatDraftService(
        read: (_) async => '',
        write: (id, text) async {
          if (fails) {
            fails = false;
            throw StateError('disk failure');
          }
          saved = text;
        });
    service.update('a', 'draft');
    await expectLater(service.flush('a'), throwsStateError);
    await service.flush('a');
    expect(saved, 'draft');
    service.reset();
  });
}

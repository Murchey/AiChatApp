import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:ai_chat/widgets/chat_send_button.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ai_chat/providers/settings_provider.dart';
import 'package:ai_chat/widgets/message_input.dart';
import 'package:ai_chat/services/chat_draft_service.dart';

void main() {
  Future<void> mount(WidgetTester tester, ChatDraftService service,
      Future<bool> Function(String) send,
      {Key? inputKey,
      Future<bool> Function(String, VoidCallback)? sendWithFeedback}) async {
    await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: CupertinoApp(
            home: CupertinoPageScaffold(
                child: Align(
                    alignment: Alignment.bottomCenter,
                    child: MessageInput(
                        key: inputKey,
                        draftConversationId: 'a',
                        draftService: service,
                        onSend: (_) {},
                        onSendDraft: send,
                        onSendWithFeedback: sendWithFeedback,
                        enterToSend: true,
                        showStickerButton: false))))));
    await tester.pump();
  }

  testWidgets(
      'local acceptance clears input before persistence and preserves new text',
      (tester) async {
    final disk = <String, String>{};
    final drafts = ChatDraftService(
        read: (id) async => disk[id],
        write: (id, text) async {
          disk[id] = text;
        });
    final saved = Completer<bool>();
    var sends = 0;
    await mount(tester, drafts, (_) async => true,
        sendWithFeedback: (_, added) {
      sends++;
      added();
      return saved.future;
    });
    final field = find.byType(CupertinoTextField);
    await tester.enterText(field, ' 原始消息\n ');
    await tester.pump();
    await tester.tap(find.byType(ChatSendButton));
    await tester.pump();
    expect(saved.isCompleted, false);
    expect(tester.widget<CupertinoTextField>(field).controller!.text, '');
    expect(await drafts.load('a'), ' 原始消息\n ');
    await tester.enterText(field, '下一条');
    await tester.pump();
    await tester.tap(find.byType(ChatSendButton));
    expect(sends, 1);
    saved.complete(true);
    await tester.pump();
    expect(tester.widget<CupertinoTextField>(field).controller!.text, '下一条');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(disk['a'], '下一条');
    drafts.reset();
  });

  for (final failure in [false, true]) {
    testWidgets(
        'local acceptance clears immediately and restores failed send ($failure)',
        (tester) async {
      final writes = <String>[];
      final drafts = _CountingDraftService(writes);
      final saved = Completer<bool>();
      await mount(tester, drafts, (_) async => true,
          sendWithFeedback: (_, added) {
        added();
        return saved.future;
      });
      final field = find.byType(CupertinoTextField);
      await tester.enterText(field, ' 中文\n原始草稿 ');
      await tester.pump();
      await tester.tap(find.byType(ChatSendButton));
      await tester.pump();
      expect(tester.widget<CupertinoTextField>(field).controller!.text, '');
      if (failure) {
        saved.completeError(StateError('disk failure'));
      } else {
        saved.complete(false);
      }
      await tester.pump();
      expect(tester.widget<CupertinoTextField>(field).controller!.text,
          ' 中文\n原始草稿 ');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(writes.last, ' 中文\n原始草稿 ');
      drafts.reset();
    });
  }

  testWidgets(
      'successful local acceptance clears durable draft after leaving page',
      (tester) async {
    final writes = <String>[];
    final drafts = _CountingDraftService(writes);
    final saved = Completer<bool>();
    await mount(tester, drafts, (_) async => true,
        sendWithFeedback: (_, added) {
      added();
      return saved.future;
    });
    await tester.enterText(find.byType(CupertinoTextField), '发送');
    await tester.pump();
    await tester.tap(find.byType(ChatSendButton));
    await tester.pumpWidget(const SizedBox());
    saved.complete(true);
    await tester.pump();
    expect(await drafts.load('a'), '');
    expect(writes.last, '');
    drafts.reset();
  });

  testWidgets('typing identical text again and leaving preserves the new draft',
      (tester) async {
    final writes = <String>[];
    final drafts = _CountingDraftService(writes);
    final saved = Completer<bool>();
    await mount(tester, drafts, (_) async => true,
        sendWithFeedback: (_, added) {
      added();
      return saved.future;
    });
    final field = find.byType(CupertinoTextField);
    await tester.enterText(field, '重复内容');
    await tester.pump();
    await tester.tap(find.byType(ChatSendButton));
    await tester.pump();
    await tester.enterText(field, '重复内容');
    await tester.pumpWidget(const SizedBox());
    saved.complete(true);
    await tester.pump();
    expect(await drafts.load('a'), '重复内容');
    expect(writes.last, '重复内容');
    drafts.reset();
  });

  testWidgets(
      'IME selection and composing updates do not resave drafts or rebuild send button',
      (tester) async {
    final writes = <String>[];
    final drafts = _CountingDraftService(writes);
    await mount(tester, drafts, (_) async => true);
    final field = find.byType(CupertinoTextField);
    await tester.enterText(field, '中文草稿');
    await tester.pump();
    final button = tester.widget<ChatSendButton>(find.byType(ChatSendButton));
    final controller = tester.widget<CupertinoTextField>(field).controller!;
    await tester.pump(const Duration(milliseconds: 200));
    for (var i = 0; i < 100; i++) {
      controller.value = TextEditingValue(
          text: '中文草稿',
          selection: TextSelection.collapsed(offset: i % 4),
          composing: TextRange(start: 0, end: i % 4));
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(drafts.updates, 1);
    expect(writes, ['中文草稿']);
    expect(tester.widget<ChatSendButton>(find.byType(ChatSendButton)),
        same(button));
    await tester.enterText(field, '中文草稿继续输入');
    await tester.pump();
    expect(tester.widget<ChatSendButton>(find.byType(ChatSendButton)),
        same(button));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(writes.last, '中文草稿继续输入');
    drafts.reset();
  });
  testWidgets('cursor movement during send does not preserve the sent draft',
      (tester) async {
    final writes = <String>[];
    final drafts = _CountingDraftService(writes);
    final accepted = Completer<bool>();
    await mount(tester, drafts, (_) => accepted.future);
    final field = find.byType(CupertinoTextField);
    await tester.enterText(field, '发送这条');
    await tester.pump();
    await tester.tap(find.byType(ChatSendButton));
    final controller = tester.widget<CupertinoTextField>(field).controller!;
    controller.selection = const TextSelection.collapsed(offset: 0);
    accepted.complete(true);
    await tester.pump();
    expect(controller.text, '');
    expect(await drafts.load('a'), '');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    drafts.reset();
  });
  testWidgets(
      'restores without focusing and flushes when leaving or backgrounding',
      (tester) async {
    final disk = <String, String>{'a': '原草稿\n第二段'};
    final drafts = ChatDraftService(
        read: (id) async => disk[id],
        write: (id, text) async {
          disk[id] = text;
        });
    await mount(tester, drafts, (_) async => true);
    final field = find.byType(CupertinoTextField);
    expect(
        tester.widget<CupertinoTextField>(field).controller!.text, '原草稿\n第二段');
    expect(tester.widget<CupertinoTextField>(field).focusNode!.hasFocus, false);
    await tester.enterText(field, ' 新内容\n ');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(disk['a'], ' 新内容\n ');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    drafts.reset();
  });
  testWidgets(
      'late restore cannot overwrite typing and disposed send clears only old text',
      (tester) async {
    final read = Completer<String?>();
    final sent = Completer<bool>();
    final disk = <String, String>{};
    final drafts = ChatDraftService(
        read: (_) => read.future,
        write: (id, text) async {
          disk[id] = text;
        });
    await mount(tester, drafts, (_) => sent.future);
    final field = find.byType(CupertinoTextField);
    await tester.enterText(field, '输入中的新草稿');
    read.complete('磁盘上的旧草稿');
    await tester.pump();
    expect(
        tester.widget<CupertinoTextField>(field).controller!.text, '输入中的新草稿');
    await tester.tap(find.byType(ChatSendButton));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    sent.complete(true);
    await tester.pump();
    expect(await drafts.load('a'), '');
    expect(disk['a'], '');
    drafts.reset();
  });
  testWidgets(
      'accepted send clears draft, rejected send keeps it and new typing wins',
      (tester) async {
    final disk = <String, String>{};
    final drafts = ChatDraftService(
        read: (id) async => disk[id],
        write: (id, text) async {
          disk[id] = text;
        });
    final key = GlobalKey<MessageInputState>();
    Completer<bool>? pending;
    await mount(tester, drafts, (_) {
      pending = Completer<bool>();
      return pending!.future;
    }, inputKey: key);
    final field = find.byType(CupertinoTextField);
    // Text input action exercises the same send callback as the send button.
    await tester.enterText(field, '第一条');
    await tester.pump();
    await tester.tap(find.byType(ChatSendButton));
    await tester.pump();
    expect(pending, isNotNull);
    pending!.complete(false);
    await tester.pump();
    expect(tester.widget<CupertinoTextField>(field).controller!.text, '第一条');
    await tester.tap(find.byType(ChatSendButton));
    await tester.pump();
    await tester.enterText(field, '新的草稿');
    pending!.complete(true);
    await tester.pump();
    expect(tester.widget<CupertinoTextField>(field).controller!.text, '新的草稿');
    await tester.tap(find.byType(ChatSendButton));
    await tester.pump();
    pending!.complete(true);
    await tester.pump();
    expect(tester.widget<CupertinoTextField>(field).controller!.text, '');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    drafts.reset();
  });
}

class _CountingDraftService extends ChatDraftService {
  _CountingDraftService(List<String> writes)
      : super(
            read: (_) async => '',
            write: (_, text) async {
              writes.add(text);
            });
  int updates = 0;
  @override
  void update(String id, String text) {
    updates++;
    super.update(id, text);
  }
}

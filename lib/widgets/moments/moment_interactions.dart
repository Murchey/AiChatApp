import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../models/character.dart';
import '../../models/moment.dart';
import '../../providers/api_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/character_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/chat_settings_provider.dart';
import '../../providers/group_chat_provider.dart';
import '../../providers/memory_point_provider.dart';
import '../../providers/moment_notification_provider.dart';
import '../../services/moment_ai_service.dart';

/// 持久化一条动态的变更，保留未修改的字段。
Future<void> updateMomentData(
  BuildContext context, {
  required Character character,
  required Moment moment,
  List<String>? likes,
  List<MomentComment>? comments,
  Moment? replaced,
}) async {
  final target = replaced ??
      Moment(
        id: moment.id,
        content: moment.content,
        location: moment.location,
        visibility: moment.visibility,
        images: moment.images,
        likes: likes ?? moment.likes,
        comments: comments ?? moment.comments,
        createdAt: moment.createdAt,
      );
  final newMoments =
      character.moments.map((m) => m.id == moment.id ? target : m).toList();
  await context.read<CharacterProvider>().updateMoments(
        character.id,
        newMoments,
      );
}

Character? resolveMomentReplyTarget(
  BuildContext context,
  Character owner,
  String? replyTo,
) {
  if (replyTo != null && replyTo.isNotEmpty) {
    for (final character in context.read<CharacterProvider>().characters) {
      if (character.displayName == replyTo) return character;
    }
  }
  return owner;
}

void triggerMomentAiReply(
  BuildContext context, {
  required Character owner,
  required Moment moment,
  required Character replier,
  required String userComment,
  String? replyToName,
}) {
  var repliedComment = '';
  if (replyToName != null && replyToName.isNotEmpty) {
    for (final comment in moment.comments.reversed) {
      if (comment.sender == replyToName) {
        repliedComment = comment.content;
        break;
      }
    }
  }
  final user = context.read<AuthProvider>().user;
  final userNickname = user?.nickname ?? '';
  unawaited(MomentAiService.replyToUserComment(
    apiProvider: context.read<ApiProvider>(),
    chatSettings: context.read<ChatSettingsProvider>(),
    chatProvider: context.read<ChatProvider>(),
    groupChatProvider: context.read<GroupChatProvider>(),
    characterProvider: context.read<CharacterProvider>(),
    notificationProvider: context.read<MomentNotificationProvider>(),
    memoryPointProvider: context.read<MemoryPointProvider>(),
    character: replier,
    owner: owner,
    moment: moment,
    user: user,
    userNickname: userNickname.isEmpty ? '我' : userNickname,
    userComment: userComment,
    replyToName: replyToName ?? '',
    repliedComment: repliedComment,
  ));
}

/// 统一处理新增/编辑评论，供一级卡片和动态详情页共用。
Future<void> submitMomentComment(
  BuildContext context, {
  required Character character,
  required Moment moment,
  required String text,
  String? replyTo,
  int? editIndex,
  bool manageMode = false,
}) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return;
  if (editIndex != null) {
    if (editIndex < 0 || editIndex >= moment.comments.length) return;
    final comments = [...moment.comments];
    comments[editIndex] = MomentComment(
      sender: comments[editIndex].sender,
      content: trimmed,
      replyTo: comments[editIndex].replyTo,
    );
    await updateMomentData(context,
        character: character, moment: moment, comments: comments);
    return;
  }

  final myName = context.read<AuthProvider>().user?.nickname ?? '';
  final comments = [
    ...moment.comments,
    MomentComment(
      sender: myName.isEmpty ? '我' : myName,
      content: trimmed,
      replyTo: replyTo ?? '',
    ),
  ];
  // Resolve dependencies before the persistence await so the detail route can
  // safely be popped while the write is in flight.
  final replier = !manageMode
      ? resolveMomentReplyTarget(context, character, replyTo)
      : null;
  final update = updateMomentData(context,
      character: character, moment: moment, comments: comments);
  if (!manageMode) {
    if (replier != null && replier.id != CharacterProvider.selfCharacterId) {
      triggerMomentAiReply(
        context,
        owner: character,
        moment: moment,
        replier: replier,
        userComment: trimmed,
        replyToName: replyTo,
      );
    }
  }
  await update;
}

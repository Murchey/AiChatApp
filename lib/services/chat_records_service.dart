import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:gbk_codec/gbk_codec.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';

/// 聊天记录导出 / 导入服务
///
/// 导出格式为 zip 包：
///   chat.json      聊天记录（text 消息 content 为正文；
///                   image/file 消息 content 为包内相对路径）
///   images/xxx.jpg 图片消息的原始图片文件
///   files/原名      文件消息的原始文件
class ChatRecordsService {
  /// 将消息列表打包为聊天记录 zip 的字节（chat.json + images/ + files/）。
  ///
  /// 图片/文件原始文件缺失（如已被系统清理）时，该消息 content 保留原绝对路径，不加入包内。
  static Future<Uint8List> buildExportZip({
    required String characterName,
    required List<Message> messages,
  }) async {
    final archive = Archive();
    final exported = <Map<String, dynamic>>[];
    var imageIndex = 0;
    var fileIndex = 0;

    for (final m in messages) {
      final data = <String, dynamic>{
        'id': m.id,
        'is_from_user': m.isFromUser,
        'type': m.type.name, // text | image | file | system
        'content': m.content,
        'created_at': m.createdAt.toIso8601String(),
        'quote_content': m.quoteContent,
        'quote_sender': m.quoteSender,
        // 群聊专属：记录发送者角色，导入后可还原多角色发言
        'sender_character_id': m.senderCharacterId,
        'sender_name': m.senderName,
      };
      if (m.isForwardCard) {
        data['forwarded_items'] =
            m.forwardedItems.map((e) => e.toJson()).toList();
      }

      if (m.type == MessageType.image) {
        final file = File(m.content);
        if (file.existsSync()) {
          final ext = _extensionOf(m.content);
          final name = 'image_${imageIndex++}.$ext';
          archive.addFile(ArchiveFile.bytes('images/$name', file.readAsBytesSync()));
          data['content'] = 'images/$name';
        }
      } else if (m.type == MessageType.file) {
        final file = File(m.content);
        if (file.existsSync()) {
          var name = m.content.split(RegExp(r'[/\\]')).last;
          if (name.isEmpty) name = 'file_${fileIndex++}.dat';
          archive.addFile(ArchiveFile.bytes('files/$name', file.readAsBytesSync()));
          data['content'] = 'files/$name';
        }
      }
      exported.add(data);
    }

    final root = <String, dynamic>{
      'app': 'AiChat',
      'app_version': await _appVersion(),
      'character_name': characterName,
      'export_time': DateTime.now().toIso8601String(),
      'message_count': exported.length,
      'messages': exported,
    };
    archive.addFile(ArchiveFile.string(
      'chat.json',
      const JsonEncoder.withIndent('    ').convert(root),
    ));

    final zipBytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipBytes);
  }

  /// 解析导出的聊天记录 zip：提取图片/文件到应用文档目录，
  /// 返回可直接追加进会话的 [Message] 列表。
  static Future<List<Message>> importZip({
    required String zipPath,
    required String conversationId,
  }) async {
    final bytes = File(zipPath).readAsBytesSync();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('无法解析 zip 文件，请确认选择的是聊天记录包');
    }

    // 修复文件名（GBK 乱码）并建立 包内路径 -> 文件 的映射
    ArchiveFile? chatFile;
    final fileMap = <String, ArchiveFile>{};
    for (final file in archive) {
      if (!file.isFile) continue;
      final name = _fixFileName(file.name.replaceAll('\\', '/'));
      file.name = name;
      fileMap[name] = file;
      if (name.toLowerCase() == 'chat.json') chatFile = file;
    }
    if (chatFile == null) {
      throw const FormatException('压缩包中未找到 chat.json，请确认是聊天记录包');
    }

    final root = jsonDecode(_decodeText(chatFile.content)) as Map<String, dynamic>;
    final rawMessages = root['messages'] as List<dynamic>? ?? [];

    // 提取目录：应用文档目录/chat_import_{时间戳}/
    final docDir = await getApplicationDocumentsDirectory();
    final importDir = Directory(
      '${docDir.path}/chat_import_${DateTime.now().millisecondsSinceEpoch}',
    );
    await importDir.create(recursive: true);

    final messages = <Message>[];
    for (final raw in rawMessages) {
      final map = raw as Map<String, dynamic>;
      final typeStr = map['type'] as String? ?? 'text';
      var content = map['content'] as String? ?? '';

      final type = switch (typeStr) {
        'image' => MessageType.image,
        'file' => MessageType.file,
        'system' => MessageType.system,
        _ => MessageType.text,
      };

      // 包内图片/文件：提取到应用目录，content 改为绝对路径
      if ((type == MessageType.image || type == MessageType.file) &&
          content.isNotEmpty) {
        final entry = fileMap[content];
        if (entry != null) {
          final safeName = _safeFileName(content.split('/').last);
          final targetFile = File('${importDir.path}/$safeName');
          await targetFile.writeAsBytes(
            entry.content as List<int>,
            flush: true,
          );
          content = targetFile.path;
        }
      }

      final forwarded = (map['forwarded_items'] as List<dynamic>? ?? [])
          .map((e) => ForwardItem.fromJson(e as Map<String, dynamic>))
          .toList();

      messages.add(Message(
        id: const Uuid().v4(),
        conversationId: conversationId,
        content: content,
        type: type,
        sender: (map['is_from_user'] as bool? ?? false)
            ? MessageSender.user
            : MessageSender.character,
        createdAt:
            DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
        quoteContent: map['quote_content'] as String? ?? '',
        quoteSender: map['quote_sender'] as String? ?? '',
        senderCharacterId: map['sender_character_id'] as String? ?? '',
        senderName: map['sender_name'] as String? ?? '',
        forwardedItems: forwarded,
      ));
    }
    return messages;
  }

  static Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return 'unknown';
    }
  }

  /// 从路径中提取扩展名（小写，不带点）；无扩展名返回 'jpg'
  static String _extensionOf(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return 'jpg';
    final ext = name.substring(dot + 1).toLowerCase();
    return ext.isEmpty ? 'jpg' : ext;
  }

  /// 防止导入时出现空名 / '.' / '..' 等非法文件名
  static String _safeFileName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == '.' || trimmed == '..') {
      return 'file_${DateTime.now().millisecondsSinceEpoch}';
    }
    return trimmed;
  }

  /// 解码文本内容：优先严格 UTF-8，失败尝试 GBK（Windows 中文系统常见），最后按原始字节
  static String _decodeText(List<int>? bytes) {
    if (bytes == null) return '';
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {}
    try {
      return gbk_bytes.decode(bytes);
    } catch (_) {}
    return String.fromCharCodes(bytes);
  }

  /// 修复 zip 文件名的 GBK 乱码（archive 包按 UTF-8/latin1 解码导致）
  static String _fixFileName(String name) {
    if (name.isEmpty || !_looksMojibake(name)) return name;
    final bytes = name.codeUnits.map((c) => c & 0xFF).toList();
    try {
      final decoded = gbk_bytes.decode(bytes);
      if (decoded.isNotEmpty) return decoded;
    } catch (_) {}
    return name;
  }

  /// 判断字符串是否为 GBK 被逐字节 latin1 转换产生的乱码
  static bool _looksMojibake(String s) {
    if (s.contains('\uFFFD')) return true;
    var nonAscii = 0;
    var cjk = 0;
    for (final c in s.codeUnits) {
      if (c >= 0x80) {
        nonAscii++;
        if (c >= 0x2E80 && c <= 0x9FFF) cjk++;
      }
    }
    return nonAscii >= 2 && nonAscii * 2 >= s.length && cjk < nonAscii ~/ 2;
  }
}

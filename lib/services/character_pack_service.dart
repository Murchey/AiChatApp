import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:gbk_codec/gbk_codec.dart';
import 'package:path_provider/path_provider.dart';
import '../models/character.dart';
import '../models/character_pack_entry.dart';

/// 角色包（.zip）解析与导出服务
///
/// 角色包目录结构（与 CharactersImport 示例一致）：
///   Sample1/
///     ├── 角色A/
///     │   ├── Profile.json     角色资料（name/location/gender/signature 或完整字段）
///     │   ├── Prompt.txt       角色提示词（systemPrompt）
///     │   └── ProfilePicture.jpg  角色头像
///     └── 角色B/
///         └── ...
class CharacterPackService {
  /// 解析 zip 角色包，返回所有可导入的角色条目（无合法 Profile.json 的目录会被过滤）
  static Future<List<CharacterPackEntry>> parsePack(String zipPath) async {
    final bytes = File(zipPath).readAsBytesSync();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('无法解析 zip 文件，请确认选择的是正确的角色包');
    }

    // 目录 -> 该目录下的文件（相对该目录的路径）
    final dirFiles = <String, List<ArchiveFile>>{};
    for (final file in archive) {
      if (!file.isFile) continue;
      // 修复 Windows 中文系统打包时 GBK 编码的文件名乱码
      final name = _fixFileName(file.name.replaceAll('\\', '/'));
      file.name = name;
      final idx = name.lastIndexOf('/');
      if (idx < 0) continue; // 忽略根目录文件
      final dir = name.substring(0, idx);
      dirFiles.putIfAbsent(dir, () => []).add(file);
    }

    final result = <CharacterPackEntry>[];
    final seenFolders = <String>{};
    for (final entry in dirFiles.entries) {
      // 角色目录 = 包含 Profile.json 的目录
      final profileFile = entry.value
          .where((f) => f.name.split('/').last.toLowerCase() == 'profile.json')
          .firstOrNull;
      if (profileFile == null) continue;
      final folderName = entry.key.split('/').last;
      if (folderName.isEmpty || !seenFolders.add(folderName)) continue;

      try {
        final character = _parseCharacter(entry.key, entry.value, profileFile);
        result.add(CharacterPackEntry(folderName: folderName, character: character));
      } catch (e) {
        result.add(CharacterPackEntry(
          folderName: folderName,
          character: Character(id: 'invalid', name: folderName),
          error: '$e',
        ));
      }
    }
    return result;
  }

  /// 解析单个角色目录
  static Character _parseCharacter(
    String dir,
    List<ArchiveFile> files,
    ArchiveFile profileFile,
  ) {
    final profileJson = _decodeUtf8(profileFile.content);
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(profileJson) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('Profile.json 不是有效的 JSON');
    }

    String str(String key, [String def = '']) =>
        (data[key] as String?)?.trim() ?? def;

    // 头像：优先 Profile.json 中内嵌的 avatar，其次目录内的图片文件
    var avatar = str('avatar');
    if (avatar.isEmpty) {
      for (final f in files) {
        final name = f.name.split('/').last.toLowerCase();
        if (name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.png') ||
            name.endsWith('.webp') ||
            name.endsWith('.gif') ||
            name.endsWith('.bmp')) {
          avatar = base64Encode(f.content as List<int>);
          break;
        }
      }
    }

    // 提示词：优先 Profile.json 中的 system_prompt，其次 Prompt.txt
    var systemPrompt = str('system_prompt');
    if (systemPrompt.isEmpty) {
      for (final f in files) {
        if (f.name.split('/').last.toLowerCase() == 'prompt.txt') {
          systemPrompt = _decodeUtf8(f.content).trim();
          break;
        }
      }
    }

    return Character(
      id: 'import_${DateTime.now().microsecondsSinceEpoch}',
      name: str('name', dir.split('/').last),
      remark: str('remark'),
      signature: str('signature'),
      region: str('region', str('location')),
      avatar: avatar,
      description: str('description'),
      personality: str('personality'),
      greeting: str('greeting'),
      systemPrompt: systemPrompt,
      customPersona: str('custom_persona'),
      userRelationship: str('user_relationship'),
      tags: (data['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  /// 将选中的角色导出为 zip 角色包（保存到下载目录），返回保存路径
  static Future<String> exportPack(
    List<Character> characters, {
    String? saveDirectory,
  }) async {
    final archive = Archive();
    for (final c in characters) {
      final folder = 'Sample1/${c.displayName}';
      final data = <String, dynamic>{
        'name': c.name,
        'location': c.region,
        'signature': c.signature,
        'remark': c.remark,
        'description': c.description,
        'personality': c.personality,
        'greeting': c.greeting,
        'system_prompt': c.systemPrompt,
        'custom_persona': c.customPersona,
        'user_relationship': c.userRelationship,
        'tags': c.tags,
      };
      archive.addFile(ArchiveFile.string(
        '$folder/Profile.json',
        const JsonEncoder.withIndent('    ').convert(data),
      ));
      if (c.systemPrompt.trim().isNotEmpty) {
        archive.addFile(ArchiveFile.string('$folder/Prompt.txt', c.systemPrompt));
      }
      if (c.avatar.isNotEmpty) {
        archive.addFile(ArchiveFile.bytes(
          '$folder/ProfilePicture.jpg',
          Uint8List.fromList(base64Decode(c.avatar)),
        ));
      }
    }

    final zipBytes = ZipEncoder().encode(archive);

    final dir = saveDirectory ?? await _defaultSaveDirectory();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final fileName = '角色包_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}.zip';
    final file = File('$dir/$fileName');
    await file.writeAsBytes(zipBytes);
    return file.path;
  }

  static Future<String> _defaultSaveDirectory() async {
    try {
      final dir = await getDownloadsDirectory();
      if (dir != null) return dir.path;
    } catch (_) {}
    try {
      final doc = await getApplicationDocumentsDirectory();
      return doc.path;
    } catch (_) {}
    return Directory.systemTemp.path;
  }

  /// 解码文本内容：优先严格 UTF-8，失败尝试 GBK（Windows 中文系统常见），最后按原始字节
  static String _decodeUtf8(List<int>? bytes) {
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
    // 乱码字符的码位即原始字节值，还原字节后用 GBK 重新解码
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
        // CJK 汉字区块，正常中文名会大量命中
        if (c >= 0x2E80 && c <= 0x9FFF) cjk++;
      }
    }
    // 大量非 ASCII 字符却几乎没有 CJK 中文 → 疑似乱码
    return nonAscii >= 2 && nonAscii * 2 >= s.length && cjk < nonAscii ~/ 2;
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:gbk_codec/gbk_codec.dart';
import 'package:path_provider/path_provider.dart';
import '../models/character.dart';
import '../models/character_pack_entry.dart';
import '../models/memory_point.dart';
import '../models/moment.dart';
import '../models/moments_pack_entry.dart';

/// 角色包（.zip）解析与导出服务
///
/// 角色包目录结构（与 CharactersImport 示例一致）：
///   Sample1/
///     ├── 角色A/
///     │   ├── Profile.json     角色资料（name/location/gender/signature 或完整字段）
///     │   ├── Prompt.txt       角色提示词（systemPrompt）
///     │   ├── ProfilePicture.jpg  角色头像
///     │   └── moments/         角色朋友圈（可选）
///     │       ├── moments.json 朋友圈记录（character_name + moments 数组）
///     │       └── files/       朋友圈引用的图片（images 相对路径引用）
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

      // 收集该角色目录下的全部文件（含子目录 moments/、files/ 等嵌套文件）
      final allFiles = <ArchiveFile>[
        ...entry.value,
        for (final other in dirFiles.entries)
          if (other.key.startsWith('${entry.key}/')) ...other.value,
      ];

      try {
        final parsed = await _parseCharacter(entry.key, allFiles, profileFile);
        result.add(CharacterPackEntry(
          folderName: folderName,
          character: parsed.character,
          memoryPoints: parsed.memoryPoints,
        ));
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

  /// 解析单个角色目录，返回角色数据与其随包的持久化记忆点。
  static Future<({Character character, List<MemoryPoint> memoryPoints})>
      _parseCharacter(
    String dir,
    List<ArchiveFile> files,
    ArchiveFile profileFile,
  ) async {
    final profileJson = _decodeUtf8(profileFile.content);
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(profileJson) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('Profile.json 不是有效的 JSON');
    }

    String str(String key, [String def = '']) =>
        (data[key] as String?)?.trim() ?? def;

    // 角色目录内「直接子文件」的相对路径（不含子目录，如 moments/ 下的图片）
    bool isImage(String name) =>
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp') ||
        name.endsWith('.gif') ||
        name.endsWith('.bmp');

    // 头像：优先 Profile.json 中内嵌的 avatar，其次 ProfilePicture.*（不限制扩展名），
    // 再其次角色目录内任意图片（仅直接子文件，避免误取 moments 图片）
    var avatar = str('avatar');
    if (avatar.isEmpty) {
      for (final f in files) {
        final fileName = f.name.split('/').last.toLowerCase();
        if (fileName.startsWith('profilepicture.') && isImage(fileName)) {
          avatar = base64Encode(f.content as List<int>);
          break;
        }
      }
    }
    if (avatar.isEmpty) {
      for (final f in files) {
        if (f.name.startsWith('$dir/') && !f.name.substring(dir.length + 1).contains('/') &&
            isImage(f.name.split('/').last.toLowerCase())) {
          avatar = base64Encode(f.content as List<int>);
          break;
        }
      }
    }

    // 背景图：优先 Profile.json 中内嵌的 background，其次 ProfileBackground.*（不限制扩展名）
    var background = str('background');
    if (background.isEmpty) {
      for (final f in files) {
        final fileName = f.name.split('/').last.toLowerCase();
        if (fileName.startsWith('profilebackground.') && isImage(fileName)) {
          background = base64Encode(f.content as List<int>);
          break;
        }
      }
    }

    // 提示词：仅从 Prompt.txt 读取（Profile.json 不再支持 system_prompt 键）
    var systemPrompt = '';
    for (final f in files) {
      if (f.name.split('/').last.toLowerCase() == 'prompt.txt') {
        systemPrompt = _decodeUtf8(f.content).trim();
        break;
      }
    }

    final moments = await _extractMoments(dir, files);

    // 持久化记忆点：Profile.json 的 memory_points 数组
    // [{"content": "...", "created_at": "..."}]
    final memoryPoints = <MemoryPoint>[];
    final rawMemory = data['memory_points'];
    if (rawMemory is List) {
      for (final m in rawMemory) {
        if (m is! Map<String, dynamic>) continue;
        final content = (m['content'] as String? ?? '').trim();
        if (content.isEmpty) continue;
        memoryPoints.add(MemoryPoint(
          content: content,
          createdAt: DateTime.tryParse(m['created_at'] as String? ?? ''),
        ));
      }
    }

    final character = Character(
      id: 'import_${DateTime.now().microsecondsSinceEpoch}',
      name: str('name', dir.split('/').last),
      remark: str('remark'),
      signature: str('signature'),
      region: str('region', str('location')),
      avatar: avatar,
      background: background,
      description: str('description'),
      personality: str('personality'),
      greeting: str('greeting'),
      systemPrompt: systemPrompt,
      userRelationship: str('user_relationship'),
      activeStart: str('active_start'),
      activeEnd: str('active_end'),
      modelId: str('model_id'),
      defaultModelId: str('default_model_id'),
      tags: (data['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      moments: moments,
    );
    return (character: character, memoryPoints: memoryPoints);
  }

  /// 解析角色目录下的朋友圈（`moments/moments.json` 或目录内直接放置的
  /// `moments.json`），并把引用的图片提取到应用文档目录，返回 [Moment] 列表。
  ///
  /// [charDir] 为 zip 内角色目录的完整路径（如 `Sample1/爱弥斯`）。兼容两种布局：
  ///   - `角色目录/moments/moments.json` + `角色目录/moments/files/`（角色包内布局）
  ///   - `角色目录/moments.json` + `角色目录/files/`（朋友圈数据包布局）
  /// 图片缺失或提取失败时保留原相对路径字符串（如 `files/01.jpg`），
  /// 由展示层做容错，不中断整个角色的导入。
  static Future<List<Moment>> _extractMoments(
    String charDir,
    List<ArchiveFile> files,
  ) async {
    final normDir = charDir.replaceAll('\\', '/');
    final fileMap = <String, ArchiveFile>{};
    ArchiveFile? jsonFile;
    String? baseDir; // 包含 moments.json 的目录（图片相对路径的基准目录）
    for (final f in files) {
      final name = f.name.replaceAll('\\', '/');
      fileMap[name] = f;
      if (name == '$normDir/moments/moments.json') {
        jsonFile = f;
        baseDir = '$normDir/moments';
      } else if (name == '$normDir/moments.json' && jsonFile == null) {
        jsonFile = f;
        baseDir = normDir;
      }
    }
    if (jsonFile == null || baseDir == null) return const [];

    final Map<String, dynamic> root;
    try {
      root = jsonDecode(_decodeUtf8(jsonFile.content)) as Map<String, dynamic>;
    } catch (_) {
      return const [];
    }
    final rawMoments = root['moments'] as List<dynamic>? ?? [];
    if (rawMoments.isEmpty) return const [];

    // 提取目录：应用文档目录/moment_import_{时间戳}/
    final docDir = await getApplicationDocumentsDirectory();
    final importDir = Directory(
      '${docDir.path}/moment_import_${DateTime.now().microsecondsSinceEpoch}',
    );
    await importDir.create(recursive: true);

    final result = <Moment>[];
    // 保证导入的动态 id 唯一：数据包中可能重复/缺失 id（会导致
    // 点赞、编辑等"按 id 更新"操作时多条动态互相覆盖），重复时自动重新生成
    final seenIds = <String>{};
    for (final raw in rawMoments) {
      final map = raw as Map<String, dynamic>;
      var momentId = map['id'] as String? ?? '';
      if (momentId.isEmpty || !seenIds.add(momentId)) {
        momentId =
            'import_${DateTime.now().microsecondsSinceEpoch}_${result.length}';
        seenIds.add(momentId);
      }
      final localImages = <String>[];
      for (final rel in (map['images'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ??
          <String>[]) {
        final norm = rel.replaceAll('\\', '/');
        final entry = fileMap['$baseDir/$norm'] ?? fileMap[norm];
        if (entry != null) {
          try {
            final safeName = _safeFileName(norm.split('/').last);
            final target = File('${importDir.path}/$safeName');
            await target.writeAsBytes(entry.content as List<int>, flush: true);
            localImages.add(target.path);
          } catch (_) {
            localImages.add(rel);
          }
        } else {
          localImages.add(rel);
        }
      }
      result.add(Moment(
        id: momentId,
        content: map['content'] as String? ?? '',
        location: map['location'] as String? ?? '',
        visibility: map['visibility'] as String? ?? 'all',
        images: localImages,
        likes: (map['likes'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        comments: (map['comments'] as List<dynamic>?)
                ?.map((e) => MomentComment.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? ''),
      ));
    }
    return result;
  }

  /// 解析朋友圈数据包 zip，返回各角色的朋友圈条目。
  ///
  /// 兼容两种目录结构（是否带顶层总包名均可）：
  ///   - `总包名/角色名/moments.json` + `角色名/files/` 图片文件夹（标准导出结构）
  ///   - `角色名/moments.json` + `角色名/files/` 图片文件夹
  /// 角色名取角色文件夹名；同名角色文件夹被去重，zip 中无任何
  /// moments.json 时抛出异常。
  static Future<List<MomentsPackEntry>> parseMomentsPack(String zipPath) async {
    final bytes = File(zipPath).readAsBytesSync();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('无法解析 zip 文件，请确认选择的是正确的朋友圈数据包');
    }

    // 修复文件名乱码并收集所有文件
    final allFiles = <ArchiveFile>[];
    for (final file in archive) {
      if (!file.isFile) continue;
      final name = _fixFileName(file.name.replaceAll('\\', '/'));
      file.name = name;
      allFiles.add(file);
    }

    // 定位每个包含 moments.json 的角色目录（moments.json 直接位于角色文件夹内）
    final charDirs = <String>{};
    for (final f in allFiles) {
      final segs = f.name.split('/');
      if (segs.last.toLowerCase() != 'moments.json') continue;
      // moments.json 必须直接位于角色文件夹内：
      //   - 布局一：总包名/角色名/moments.json（3 段）
      //   - 布局二：角色名/moments.json（2 段）
      // 嵌套子目录（如角色包内的「角色名/moments/moments.json」，≥4 段）
      // 不属于朋友圈数据包结构，跳过，避免把 moments 子文件夹误识别为一个角色
      if (segs.length < 2 || segs.length > 3) continue;
      // .../角色名/moments.json
      charDirs.add(segs.sublist(0, segs.length - 1).join('/'));
    }
    if (charDirs.isEmpty) {
      throw const FormatException('该 zip 中没有找到朋友圈数据（需包含 moments.json 的角色文件夹）');
    }

    // 所有角色目录位于同一父目录下时，把该层视为总包名并去掉
    final parents = charDirs.map((d) {
      final i = d.lastIndexOf('/');
      return i < 0 ? '' : d.substring(0, i);
    }).toSet();
    final stripTop = parents.length == 1 && parents.first.isNotEmpty;

    final result = <MomentsPackEntry>[];
    final seenNames = <String>{};
    for (final dir in charDirs) {
      final path = stripTop && dir.contains('/')
          ? dir.substring(dir.indexOf('/') + 1)
          : dir;
      final charName = path.split('/').last;
      if (charName.isEmpty || !seenNames.add(charName)) continue;
      try {
        final moments = await _extractMoments(dir, allFiles);
        result.add(MomentsPackEntry(characterName: charName, moments: moments));
      } catch (e) {
        result.add(MomentsPackEntry(
          characterName: charName,
          moments: const [],
          error: '$e',
        ));
      }
    }
    return result;
  }

  /// 将选中的角色导出为 zip 角色包（保存到下载目录），返回保存路径。
  ///
  /// [memoryByCharacter]：角色 id → 该角色的持久化记忆点。提供时会把记忆点
  /// 一并写入角色包 `Profile.json` 的 `memory_points` 字段，随角色包导入 / 分享。
  static Future<String> exportPack(
    List<Character> characters, {
    String? saveDirectory,
    Map<String, List<MemoryPoint>>? memoryByCharacter,
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
        'user_relationship': c.userRelationship,
        'tags': c.tags,
        // 活跃时段（"HH:mm"，仅写入已设置的字段）
        if (c.activeStart.isNotEmpty) 'active_start': c.activeStart,
        if (c.activeEnd.isNotEmpty) 'active_end': c.activeEnd,
        // 角色独立使用的模型（空表示跟随全局聊天模型）
        if (c.modelId.isNotEmpty) 'model_id': c.modelId,
        // 缺省模型（全局模型未配置时的兜底）
        if (c.defaultModelId.isNotEmpty) 'default_model_id': c.defaultModelId,
      };
      // 持久化记忆点：写入 memory_points（[{content, created_at}]）
      final memory = memoryByCharacter?[c.id] ?? const <MemoryPoint>[];
      if (memory.isNotEmpty) {
        data['memory_points'] = [
          for (final p in memory)
            {
              'content': p.content,
              'created_at': p.createdAt.toIso8601String(),
            },
        ];
      }
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
      // 背景图：ProfileBackground.jpg
      if (c.background.isNotEmpty) {
        archive.addFile(ArchiveFile.bytes(
          '$folder/ProfileBackground.jpg',
          Uint8List.fromList(base64Decode(c.background)),
        ));
      }
      // 朋友圈：moments/moments.json + 引用的图片文件（相对路径引用）
      if (c.moments.isNotEmpty) {
        final exported = <Map<String, dynamic>>[];
        for (final m in c.moments) {
          final images = <String>[];
          for (final img in m.images) {
            final name = img.split(RegExp(r'[/\\]')).last;
            if (name.isEmpty) continue;
            final file = File(img);
            if (file.existsSync()) {
              archive.addFile(ArchiveFile.bytes(
                '$folder/moments/files/$name',
                file.readAsBytesSync(),
              ));
              images.add('files/$name');
            } else {
              // 本地图片缺失：保留原字符串（可能是导入时未提取成功的相对路径）
              images.add(img);
            }
          }
          exported.add({
            'id': m.id,
            'content': m.content,
            'location': m.location,
            'visibility': m.visibility,
            'images': images,
            'likes': m.likes,
            'comments': m.comments.map((e) => e.toJson()).toList(),
            'created_at': m.createdAt?.toIso8601String(),
          });
        }
        archive.addFile(ArchiveFile.string(
          '$folder/moments/moments.json',
          const JsonEncoder.withIndent('    ').convert({
            'character_name': c.displayName,
            'moments': exported,
          }),
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

  /// 将选中的角色导出为 zip 朋友圈数据包（保存到下载目录），返回保存路径。
  ///
  /// 导出结构与导入兼容（可回环导入）：
  ///   `总包名/角色名/moments.json` + `角色名/files/` 图片文件夹
  static Future<String> exportMomentsPack(
    List<Character> characters, {
    String? saveDirectory,
  }) async {
    const packageFolder = 'Moments';
    final archive = Archive();
    for (final c in characters) {
      if (c.moments.isEmpty) continue;
      final folder = '$packageFolder/${c.displayName}';
      final exported = <Map<String, dynamic>>[];
      for (final m in c.moments) {
        final images = <String>[];
        for (final img in m.images) {
          final name = img.split(RegExp(r'[/\\]')).last;
          if (name.isEmpty) continue;
          final file = File(img);
          if (file.existsSync()) {
            archive.addFile(ArchiveFile.bytes(
              '$folder/files/$name',
              file.readAsBytesSync(),
            ));
            images.add('files/$name');
          } else {
            // 本地图片缺失：保留原字符串（可能是导入时未提取成功的相对路径）
            images.add(img);
          }
        }
        exported.add({
          'id': m.id,
          'content': m.content,
          'location': m.location,
          'visibility': m.visibility,
          'images': images,
          'likes': m.likes,
          'comments': m.comments.map((e) => e.toJson()).toList(),
          'created_at': m.createdAt?.toIso8601String(),
        });
      }
      archive.addFile(ArchiveFile.string(
        '$folder/moments.json',
        const JsonEncoder.withIndent('    ').convert({
          'character_name': c.displayName,
          'moments': exported,
        }),
      ));
    }

    final zipBytes = ZipEncoder().encode(archive);

    final dir = saveDirectory ?? await _defaultSaveDirectory();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final fileName = '朋友圈_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}.zip';
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

  /// 防止导入时出现空名 / '.' / '..' 等非法文件名
  static String _safeFileName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == '.' || trimmed == '..') {
      return 'file_${DateTime.now().millisecondsSinceEpoch}';
    }
    return trimmed;
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

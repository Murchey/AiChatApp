import '../models/character_pack_entry.dart';
import '../services/character_pack_service.dart';
import 'file_picker_helper.dart';

/// 选择 .zip 角色包并解析的结果
typedef CharacterPackPickResult = ({
  String name,
  List<CharacterPackEntry> entries,
});

/// 选择 .zip 角色包并解析
///
/// 用户取消选择返回 null；非 zip 文件或解析失败时抛出异常。
Future<CharacterPackPickResult?> pickAndParseCharacterPack() async {
  final file = await FilePickerHelper.pickFile();
  if (file == null) return null;
  if (!file.name.toLowerCase().endsWith('.zip')) {
    throw const FormatException('请选择 .zip 格式的角色包文件');
  }
  final entries = await CharacterPackService.parsePack(file.path);
  return (name: file.name, entries: entries);
}

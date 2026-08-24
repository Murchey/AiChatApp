import 'dart:io';
import 'package:path_provider/path_provider.dart';

class StickerPathHelper {
  static Future<Directory> root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/stickers');
    await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> customDirectory() async {
    final dir = Directory('${(await root()).path}/custom');
    await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> packDirectory(String packId) async {
    final dir = Directory('${(await root()).path}/packs/$packId');
    await dir.create(recursive: true);
    return dir;
  }
}

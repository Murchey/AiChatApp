import 'dart:convert';
import 'dart:io';
import 'package:ai_chat/services/sticker_pack_service.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 1x1 红色 PNG（有效图片字节，用于测试 zip 解析）。
  const pngBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAA'
      'ARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAdSURBVDhPY'
      '/jPwPCfEsyALkAqHjVg1IBRAwaLAQAwxP4Q7zYsrwAAAABJRU5ErkJggg==';

  test('parses zip images and matching txt labels', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('1.png', base64Decode(pngBase64)))
      ..addFile(ArchiveFile.bytes('1.txt', utf8.encode('熊猫头无语\n第二行忽略')))
      ..addFile(ArchiveFile.bytes('2.jpg', base64Decode(pngBase64)));
    final zipBytes = ZipEncoder().encode(archive);
    expect(zipBytes, isNotNull);

    final root = Directory.systemTemp.createTempSync('sticker_pack_test');
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });
    final zipPath = '${root.path}/pack.zip';
    File(zipPath).writeAsBytesSync(zipBytes);

    final pack = await StickerPackService.parseStickerPackZip(
      zipPath,
      name: '上班日常',
      author: '测试作者',
      targetDirectory: Directory('${root.path}/out'),
    );

    expect(pack, isNotNull);
    expect(pack!.imagePaths.length, 2);
    expect(pack.labels[0], '熊猫头无语'); // 同名 txt 首行作为备注
    expect(pack.coverImagePath, contains('out'));
    expect(File(pack.imagePaths.first).existsSync(), isTrue);
  });

  test('returns null when zip has no images', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('readme.txt', utf8.encode('没有图片')));
    final zipBytes = ZipEncoder().encode(archive);
    expect(zipBytes, isNotNull);

    final root = Directory.systemTemp.createTempSync('sticker_pack_empty');
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });
    final zipPath = '${root.path}/empty.zip';
    File(zipPath).writeAsBytesSync(zipBytes);

    final pack = await StickerPackService.parseStickerPackZip(
      zipPath,
      name: '空包',
      author: '测试',
    );
    expect(pack, isNull);
  });
}

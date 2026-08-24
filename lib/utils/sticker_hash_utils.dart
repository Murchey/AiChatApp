import 'dart:typed_data';
import 'package:crypto/crypto.dart';

String stickerSha256(Uint8List bytes) => sha256.convert(bytes).toString();

String stickerFileName(String hash, String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  final extension = dot > 0 ? name.substring(dot + 1).toLowerCase() : 'jpg';
  return '${hash.substring(0, 16)}.$extension';
}

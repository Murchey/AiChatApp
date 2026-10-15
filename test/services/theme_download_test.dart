import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// Isolate the theme download directory from real user files.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:ai_chat/services/cos_auth.dart';
import 'package:ai_chat/services/workshop_service.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'signed theme GET bypasses proxy, force replaces cache and failure cleans partial',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('aichat_theme_get_');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    try {
      final old = File('${directory.path}/workshop/theme.zip');
      await old.parent.create(recursive: true);
      await old.writeAsBytes([1]);
      var requests = 0;
      final path = await http.runWithClient(
          () => WorkshopService.downloadZip(
              downloadUrl:
                  'https://demo.cos.ap-guangzhou.myqcloud.com/Theme/theme.zip',
              proxyUrl: 'https://proxy.example/',
              auth: const CosAuth(
                  enabled: true, accessKeyId: 'key', secretAccessKey: 'secret'),
              force: true,
              maxBytes: 10),
          () => MockClient((request) async {
                requests++;
                expect(request.url.host, 'demo.cos.ap-guangzhou.myqcloud.com');
                expect(request.url.path, '/Theme/theme.zip');
                expect(request.headers.keys.map((key) => key.toLowerCase()),
                    contains('authorization'));
                return http.Response.bytes([2, 3, 4], 200);
              }));
      expect(requests, 1);
      expect(await File(path!).readAsBytes(), [2, 3, 4]);
      final failed = await http.runWithClient(
          () => WorkshopService.downloadZip(
              downloadUrl: 'https://example.com/theme.zip',
              force: true,
              maxBytes: 2),
          () => MockClient.streaming((request, body) async =>
              http.StreamedResponse(Stream.value([1, 2, 3]), 200)));
      expect(failed, isNull);
      expect(await old.readAsBytes(), [2, 3, 4]);
      expect(await File('${old.path}.part').exists(), false);
    } finally {
      PathProviderPlatform.instance = previous;
      await directory.delete(recursive: true);
    }
  });
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ai_chat/services/backend_token_store.dart';

class MemoryTokenStore implements BackendTokenStore {
  String? value;
  bool unavailable = false;
  @override
  Future<String?> read() async { if (unavailable) throw StateError('unavailable'); return value; }
  @override
  Future<void> write(String session) async { if (unavailable) throw StateError('unavailable'); value = session; }
  @override
  Future<void> clear() async { if (unavailable) throw StateError('unavailable'); value = null; }
}
http.Response jsonResponse(Object data, {int status = 200}) => http.Response(
  jsonEncode(data), status, headers: {'content-type': 'application/json; charset=utf-8'});
Map<String, Object> tokens(String suffix) => {'data': {
  'accessToken': 'access-$suffix', 'refreshToken': 'refresh-$suffix',
  'accessExpiresAt': DateTime.now().toUtc().add(const Duration(minutes: 15)).toIso8601String(),
  'refreshExpiresAt': DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String(),
}};
Map<String, Object> version({String api = 'v1', bool stories = true, String minimum = '1.6.0'}) => {
  'data': {'serverVersion': 'test', 'apiVersion': api, 'minClientVersion': minimum, 'features': {'stories': stories}}
};
Map<String, Object> catalogEntry(String id) => {'storyId': id, 'version': 1,
  'title': id, 'author': '测试', 'summary': 'description', 'tags': ['demo'], 'file': '$id.json'};
Map<String, Object> package(String id) => {...catalogEntry(id), 'schemaVersion': 1,
  'chapters': [{'id': 'c1', 'order': 1, 'title': '章节', 'memories': [{'id': 'm1', 'order': 1, 'content': '设定'}]}]};

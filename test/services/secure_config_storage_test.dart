import 'dart:convert';
import 'package:ai_chat/services/secure_config_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });
  test(
      'legacy credentials migrate without loss; preferences contain no secrets',
      () async {
    final original = jsonEncode([
      {'id': 'model-a', 'api_key': 'sample-key', 'title': 'Model'}
    ]);
    SharedPreferences.setMockInitialValues({'models': original});
    final prefs = await SharedPreferences.getInstance();
    expect(await SecureConfigStorage.readJson(prefs, 'models'), original);
    expect(prefs.getString('models'), isNot(contains('sample-key')));
    expect(await SecureConfigStorage.readJson(prefs, 'models'), original);
  });
  test('changing order retains credentials associated with each model',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final value = [
      {'id': 'a', 'api_key': 'one'},
      {'id': 'b', 'api_key': 'two'}
    ];
    await SecureConfigStorage.writeJson(prefs, 'models', jsonEncode(value));
    final metadata =
        (jsonDecode(prefs.getString('models')!) as List).reversed.toList();
    await prefs.setString('models', jsonEncode(metadata));
    expect(jsonDecode((await SecureConfigStorage.readJson(prefs, 'models'))!),
        value.reversed.toList());
  });
  test('clearing credentials clears vault values', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await SecureConfigStorage.writeSecret(prefs, 'secret', 'value');
    expect(prefs.containsKey('secret'), false);
    expect(await SecureConfigStorage.readSecret(prefs, 'secret'), 'value');
    await SecureConfigStorage.writeSecret(prefs, 'secret', '');
    expect(await SecureConfigStorage.readSecret(prefs, 'secret'), '');
  });
}

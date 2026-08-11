import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  String _apiKey = '';

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;
  String get apiKey => _apiKey;

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final nickname = prefs.getString('user_nickname');
    final avatar = prefs.getString('user_avatar') ?? '';
    final region = prefs.getString('user_region') ?? '';
    final signature = prefs.getString('user_signature') ?? '';
    final gender = prefs.getString('user_gender') ?? '';
    _apiKey = prefs.getString('api_key') ?? '';

    if (userId != null && nickname != null) {
      _user = User(
        id: userId,
        nickname: nickname,
        avatar: avatar,
        region: region,
        signature: signature,
        gender: gender,
      );
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> login(String nickname) async {
    _isLoading = true;
    notifyListeners();

    // 先用本地模拟登录，后续可接入真实后端
    final prefs = await SharedPreferences.getInstance();
    final userId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString('user_id', userId);
    await prefs.setString('user_nickname', nickname);

    _user = User(id: userId, nickname: nickname);
    _isLoading = false;
    notifyListeners();
  }

  /// 更新用户资料（昵称/头像/地区/签名/性别），任一字段传 null 表示不修改
  Future<void> updateProfile({
    String? nickname,
    String? avatar,
    String? region,
    String? signature,
    String? gender,
  }) async {
    if (_user == null) return;
    final trimmed = nickname?.trim();
    if (trimmed != null && trimmed.isEmpty) return;
    _user = _user!.copyWith(
      nickname: trimmed,
      avatar: avatar,
      region: region,
      signature: signature,
      gender: gender,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_nickname', _user!.nickname);
    if (avatar != null) await prefs.setString('user_avatar', avatar);
    if (region != null) await prefs.setString('user_region', region);
    if (signature != null) await prefs.setString('user_signature', signature);
    if (gender != null) await prefs.setString('user_gender', gender);
    notifyListeners();
  }

  Future<void> setApiKey(String apiKey) async {
    _apiKey = apiKey.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key', _apiKey);
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _user = null;
    _apiKey = '';
    notifyListeners();
  }
}

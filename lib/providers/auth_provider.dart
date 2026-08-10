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
    _apiKey = prefs.getString('api_key') ?? '';

    if (userId != null && nickname != null) {
      _user = User(id: userId, nickname: nickname, avatar: avatar);
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

  Future<void> updateAvatar(String avatar) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_avatar', avatar);
    _user = _user == null
        ? null
        : User(
            id: _user!.id,
            nickname: _user!.nickname,
            avatar: avatar,
            createdAt: _user!.createdAt,
          );
    notifyListeners();
  }

  Future<void> updateNickname(String nickname) async {
    if (nickname.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_nickname', nickname.trim());
    _user = _user == null
        ? null
        : User(
            id: _user!.id,
            nickname: nickname.trim(),
            avatar: _user!.avatar,
            createdAt: _user!.createdAt,
          );
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

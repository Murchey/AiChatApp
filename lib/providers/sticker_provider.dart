import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/sticker_pack.dart';
import '../utils/sticker_hash_utils.dart';
import '../utils/sticker_path_helper.dart';
import '../services/sticker_search_service.dart';

class StickerProvider extends ChangeNotifier {
  static const _packsKey = 'sticker_packs_v1';
  static const _userStickersKey = 'user_stickers_v1';
  List<StickerPack> _packs = [];
  List<UserSticker> _userStickers = [];

  List<StickerPack> get packs => List.unmodifiable(_packs);
  List<UserSticker> get userStickers => List.unmodifiable(_userStickers);

  List<StickerEntry> get availableStickers {
    final result = <StickerEntry>[];
    final users = [..._userStickers]
      ..sort((a, b) => b.useCount.compareTo(a.useCount));
    result.addAll(users.map((s) => StickerEntry(
          imagePath: s.imagePath,
          label: s.label,
          stickerId: s.id,
        )));
    final packs = [..._packs]
      ..sort((a, b) => b.importedAt.compareTo(a.importedAt));
    for (final pack in packs) {
      for (var i = 0; i < pack.imagePaths.length; i++) {
        result.add(StickerEntry(
          imagePath: pack.imagePaths[i],
          label: pack.labels[i],
          packId: pack.id,
          source: '${pack.author}:${pack.name}',
        ));
      }
    }
    return result;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      _packs = _decodeList(prefs.getString(_packsKey), StickerPack.fromJson);
      _userStickers =
          _decodeList(prefs.getString(_userStickersKey), UserSticker.fromJson);
    } catch (_) {
      _packs = [];
      _userStickers = [];
    }
    notifyListeners();
  }

  Future<void> importStickerPack(StickerPack pack) async {
    _packs.removeWhere((item) => item.id == pack.id);
    _packs.add(pack);
    await _persist();
    notifyListeners();
  }

  Future<void> removeStickerPack(String packId) async {
    _packs.removeWhere((pack) => pack.id == packId);
    await _persist();
    notifyListeners();
  }

  Future<UserSticker> addUserSticker({
    required String imagePath,
    required String label,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    final hash = stickerSha256(bytes);
    final existing = _findByHash(hash);
    if (existing != null) {
      final normalizedLabel = label.trim();
      if (normalizedLabel.isNotEmpty && existing.label != normalizedLabel) {
        final index =
            _userStickers.indexWhere((item) => item.id == existing.id);
        if (index != -1) {
          _userStickers[index] = existing.copyWith(label: normalizedLabel);
          await _persist();
          notifyListeners();
          return _userStickers[index];
        }
      }
      return existing;
    }
    final dir = await StickerPathHelper.customDirectory();
    final target = File('${dir.path}/${stickerFileName(hash, imagePath)}');
    if (!target.existsSync()) await target.writeAsBytes(bytes, flush: true);
    final sticker = UserSticker(
      id: const Uuid().v4(),
      sha256: hash,
      imagePath: target.path,
      label: label.trim(),
      createdAt: DateTime.now(),
    );
    _userStickers.add(sticker);
    await _persist();
    notifyListeners();
    return sticker;
  }

  Future<void> removeUserSticker(String stickerId) async {
    _userStickers.removeWhere((sticker) => sticker.id == stickerId);
    await _persist();
    notifyListeners();
  }

  Future<void> updateUserStickerLabel(String stickerId, String label) async {
    final index =
        _userStickers.indexWhere((sticker) => sticker.id == stickerId);
    if (index == -1) return;
    _userStickers[index] = _userStickers[index].copyWith(label: label.trim());
    await _persist();
    notifyListeners();
  }

  Future<void> updateUserStickerMetadata({
    required String stickerId,
    required String label,
    required String description,
    required List<String> keywords,
    required List<String> emotionTags,
  }) async {
    final index =
        _userStickers.indexWhere((sticker) => sticker.id == stickerId);
    if (index == -1) return;
    _userStickers[index] = _userStickers[index].copyWith(
      label: label.trim(),
      description: description.trim(),
      keywords: _normalizeTags(keywords),
      emotionTags: _normalizeTags(emotionTags),
    );
    await _persist();
    notifyListeners();
  }

  /// 供角色回复流程调用：只返回少量候选，永远不会把完整表情包清单交给模型。
  List<UserSticker> searchUserStickers(String query, {int limit = 5}) =>
      StickerSearchService.search(_userStickers, query, limit: limit);

  static List<String> _normalizeTags(Iterable<String> values) => values
      .expand((value) => value.split(RegExp(r'[,，、\n]')))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .take(12)
      .toList();

  Future<void> removePackSticker(StickerEntry entry) async {
    final packId = entry.packId;
    if (packId == null) return;
    final packIndex = _packs.indexWhere((pack) => pack.id == packId);
    if (packIndex == -1) return;
    final pack = _packs[packIndex];
    final imageIndex = pack.imagePaths.indexOf(entry.imagePath);
    if (imageIndex == -1) return;
    final paths = [...pack.imagePaths]..removeAt(imageIndex);
    final labels = <int, String>{};
    for (var i = 0; i < paths.length; i++) {
      final oldIndex = pack.imagePaths.indexOf(paths[i]);
      final label = pack.labels[oldIndex];
      if (label != null) labels[i] = label;
    }
    _packs[packIndex] = pack.copyWith(imagePaths: paths, labels: labels);
    await _persist();
    notifyListeners();
  }

  Future<void> incrementUseCount(String stickerId) async {
    final index = _userStickers.indexWhere((s) => s.id == stickerId);
    if (index == -1) return;
    _userStickers[index] = _userStickers[index]
        .copyWith(useCount: _userStickers[index].useCount + 1);
    await _persist();
    notifyListeners();
  }

  Future<void> moveToFront(StickerEntry entry) async {
    if (entry.stickerId != null) {
      final index = _userStickers.indexWhere((s) => s.id == entry.stickerId);
      if (index > 0) {
        final sticker = _userStickers.removeAt(index);
        _userStickers.insert(0, sticker);
      }
    } else if (entry.packId != null) {
      final packIndex = _packs.indexWhere((p) => p.id == entry.packId);
      if (packIndex != -1) {
        final pack = _packs[packIndex];
        final imageIndex = pack.imagePaths.indexOf(entry.imagePath);
        if (imageIndex > 0) {
          final paths = [...pack.imagePaths]..removeAt(imageIndex);
          paths.insert(0, entry.imagePath);
          final labels = <int, String>{};
          for (var i = 0; i < paths.length; i++) {
            final oldIndex = pack.imagePaths.indexOf(paths[i]);
            final label = pack.labels[oldIndex];
            if (label != null) labels[i] = label;
          }
          _packs[packIndex] = pack.copyWith(imagePaths: paths, labels: labels);
        }
      }
    }
    await _persist();
    notifyListeners();
  }

  Future<UserSticker?> findByHash(String hash) async => _findByHash(hash);

  UserSticker? _findByHash(String hash) {
    for (final sticker in _userStickers) {
      if (sticker.sha256 == hash) return sticker;
    }
    return null;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _packsKey, jsonEncode(_packs.map((e) => e.toJson()).toList()));
    await prefs.setString(_userStickersKey,
        jsonEncode(_userStickers.map((e) => e.toJson()).toList()));
  }

  static List<T> _decodeList<T>(
      String? raw, T Function(Map<String, dynamic>) decode) {
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((item) => decode(item as Map<String, dynamic>))
        .toList();
  }
}

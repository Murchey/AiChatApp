import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/api_provider.dart';
import 'tts_service.dart';

enum TtsPlaybackPhase { idle, synthesizing, playing, error }

/// 单次朗读请求。同 messageId 可多次入队，实现「点击三次播三次」。
class TtsPlaybackEntry {
  static int _seq = 0;

  TtsPlaybackEntry({
    required this.messageId,
    required this.model,
    required this.text,
    this.voice = '',
    this.instructions = '',
    String? requestId,
  }) : requestId = requestId ??
            '${DateTime.now().microsecondsSinceEpoch}_${_seq++}_$messageId';

  final String messageId;
  final String requestId;
  final ApiModel model;
  final String text;
  final String voice;
  final String instructions;
}

class TtsPlaybackSnapshot {
  const TtsPlaybackSnapshot({
    required this.phase,
    this.activeMessageId,
    this.activeRequestId,
    this.queuedCount = 0,
    this.errorMessage,
  });

  final TtsPlaybackPhase phase;
  final String? activeMessageId;
  final String? activeRequestId;
  final int queuedCount;
  final String? errorMessage;
}

/// 全局播放状态机：FIFO 排队、逐次播放、按消息取消。
class TtsPlaybackController extends ChangeNotifier {
  TtsPlaybackController._();

  static final TtsPlaybackController instance = TtsPlaybackController._();

  AudioPlayer? _player;
  final Queue<TtsPlaybackEntry> _queue = Queue<TtsPlaybackEntry>();
  TtsPlaybackPhase _phase = TtsPlaybackPhase.idle;
  String? _activeMessageId;
  String? _activeRequestId;
  String? _errorMessage;
  String? _currentFile;
  bool _processing = false;
  bool _cancelled = false;

  AudioPlayer get _audioPlayer => _player ??= AudioPlayer();

  TtsPlaybackSnapshot get snapshot => TtsPlaybackSnapshot(
        phase: _phase,
        activeMessageId: _activeMessageId,
        activeRequestId: _activeRequestId,
        queuedCount: _queue.length,
        errorMessage: _errorMessage,
      );

  /// 指定消息当前应显示的 UI 状态。
  TtsPlaybackPhase phaseFor(String messageId) {
    if (_phase == TtsPlaybackPhase.error && _activeMessageId == messageId) {
      return TtsPlaybackPhase.error;
    }
    if (_phase == TtsPlaybackPhase.synthesizing &&
        _activeMessageId == messageId) {
      return TtsPlaybackPhase.synthesizing;
    }
    if (_phase == TtsPlaybackPhase.playing && _activeMessageId == messageId) {
      return TtsPlaybackPhase.playing;
    }
    if (_queue.any((entry) => entry.messageId == messageId)) {
      return TtsPlaybackPhase.idle; // 排队中由 queuedCount 角标表达
    }
    return TtsPlaybackPhase.idle;
  }

  /// 指定消息在队列中的排队次数（不含正在播放/合成的那一次）。
  int queuedCountFor(String messageId) {
    var count = 0;
    for (final entry in _queue) {
      if (entry.messageId == messageId) count++;
    }
    return count;
  }

  /// 追加一次朗读。同 messageId 可重复入队，逐次播放。
  void enqueue(TtsPlaybackEntry entry) {
    _queue.add(entry);
    _errorMessage = null;
    _notify();
    unawaited(_drain());
  }

  /// 整轮连续播：替换剩余队列并立即打断当前播放。
  Future<void> playSequence(List<TtsPlaybackEntry> entries) async {
    _queue
      ..clear()
      ..addAll(entries);
    _errorMessage = null;
    _cancelled = true;
    if (_player != null) {
      await _audioPlayer.stop();
    }
    _notify();
    await _restartDrain();
  }

  /// 取消指定消息的所有排队 entry；若正在处理该消息则停止并跳到下一条。
  Future<void> cancelMessage(String messageId) async {
    _queue.removeWhere((entry) => entry.messageId == messageId);
    if (_activeMessageId == messageId) {
      _cancelled = true;
      if (_player != null) {
        await _audioPlayer.stop();
      }
    }
    _notify();
  }

  Future<void> stopAll() async {
    _queue.clear();
    _cancelled = true;
    if (_player != null) {
      await _audioPlayer.stop();
    }
    _activeMessageId = null;
    _activeRequestId = null;
    _phase = TtsPlaybackPhase.idle;
    _notify();
  }

  Future<void> _restartDrain() async {
    // 等待当前处理循环退出后重新开始
    while (_processing) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    _cancelled = false;
    await _drain();
  }

  Future<void> _drain() async {
    if (_processing) return;
    _processing = true;
    try {
      while (_queue.isNotEmpty) {
        if (_cancelled) {
          _cancelled = false;
          if (_queue.isEmpty) break;
        }
        final entry = _queue.removeFirst();
        _activeMessageId = entry.messageId;
        _activeRequestId = entry.requestId;
        _phase = TtsPlaybackPhase.synthesizing;
        _errorMessage = null;
        _notify();
        try {
          final audio = await TtsService.synthesize(
            model: entry.model,
            text: entry.text,
            voice: entry.voice,
            instructions: entry.instructions,
          );
          if (_cancelled) {
            _cancelled = false;
            continue;
          }
          await _playBytes(audio.bytes, extension: audio.extension);
          if (_cancelled) {
            _cancelled = false;
            await _audioPlayer.stop();
          }
        } catch (error) {
          _phase = TtsPlaybackPhase.error;
          _errorMessage = error.toString();
          _notify();
          await Future<void>.delayed(const Duration(milliseconds: 900));
          _cancelled = false;
        }
      }
    } finally {
      _processing = false;
      _activeMessageId = null;
      _activeRequestId = null;
      if (_phase != TtsPlaybackPhase.error) {
        _phase = TtsPlaybackPhase.idle;
      } else {
        // 错误态短暂保留后回到 idle
        unawaited(
            Future<void>.delayed(const Duration(milliseconds: 1200)).then((_) {
          if (_phase == TtsPlaybackPhase.error) {
            _phase = TtsPlaybackPhase.idle;
            _errorMessage = null;
            _notify();
          }
        }));
      }
      _notify();
    }
  }

  /// 直接播放已合成的音频（工作台试听用）。
  Future<void> playAudio(TtsAudioData audio, {String messageId = 'preview'}) {
    return _playBytes(audio.bytes, extension: audio.extension);
  }

  StreamSubscription<PlayerState>? _playerSub;

  Future<void> _playBytes(Uint8List data, {required String extension}) async {
    if (data.isEmpty) {
      throw const TtsException('语音模型返回了空音频');
    }
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/aichat_tts_${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(data, flush: true);
    await _audioPlayer.stop();
    final previous = _currentFile;
    _currentFile = file.path;
    if (previous != null && previous != file.path) {
      try {
        await File(previous).delete();
      } catch (_) {}
    }
    _phase = TtsPlaybackPhase.playing;
    _notify();
    final completion = Completer<void>();
    await _playerSub?.cancel();
    _playerSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.completed || state == PlayerState.stopped) {
        if (!completion.isCompleted) completion.complete();
      }
    });
    await _audioPlayer.play(DeviceFileSource(file.path));
    await completion.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {},
    );
    await _playerSub?.cancel();
    _playerSub = null;
  }

  void _notify() => notifyListeners();
}

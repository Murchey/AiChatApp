import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../models/character.dart';
import '../providers/api_provider.dart';
import '../providers/character_provider.dart';
import '../services/tts_playback_controller.dart';
import '../services/tts_service.dart';

/// 【我】→ 声音工作台：音色设计、声音克隆、已保存声音管理。
class VoiceWorkbenchScreen extends StatefulWidget {
  const VoiceWorkbenchScreen({super.key});

  @override
  State<VoiceWorkbenchScreen> createState() => _VoiceWorkbenchScreenState();
}

class _VoiceWorkbenchScreenState extends State<VoiceWorkbenchScreen> {
  final _designPromptCtrl = TextEditingController();
  final _designTextCtrl = TextEditingController();
  final _cloneTextCtrl = TextEditingController();
  String? _samplePath;
  String? _sampleMime;
  int _sampleSize = 0;
  bool _busy = false;
  String? _status;
  String? _designModelId;
  String? _cloneModelId;

  @override
  void dispose() {
    _designPromptCtrl.dispose();
    _designTextCtrl.dispose();
    _cloneTextCtrl.dispose();
    super.dispose();
  }

  /// 可选的语音模型列表（含 TTS 标识的模型 + 当前已选语音模型）。
  List<ApiModel> get _availableModels {
    final api = context.read<ApiProvider>();
    final models = <ApiModel>[
      for (final m in api.models)
        if (TtsService.isSupportedModel(m)) m,
    ];
    return models;
  }

  ApiModel? _selectedModel(String? id) {
    final models = _availableModels;
    if (id != null) {
      for (final m in models) {
        if (m.id == id) return m;
      }
    }
    return models.firstOrNull;
  }

  Future<void> _pickModel({required bool forClone}) async {
    final models = _availableModels;
    if (models.isEmpty) {
      setState(() => _status = '请先在 API 设置中添加语音模型');
      return;
    }
    final selected = await showCupertinoModalPopup<ApiModel>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.5,
          ),
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: ctx.scaffoldColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final m in models)
                CupertinoListTile(
                  title: Text(m.displayName),
                  subtitle: Text(
                    m.modelName,
                    style:
                        TextStyle(fontSize: 12, color: ctx.textSecondaryColor),
                  ),
                  trailing: (forClone ? _cloneModelId : _designModelId) == m.id
                      ? Icon(CupertinoIcons.check_mark, color: ctx.accentColor)
                      : null,
                  onTap: () => Navigator.pop(ctx, m),
                ),
              CupertinoButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    setState(() {
      if (forClone) {
        _cloneModelId = selected.id;
      } else {
        _designModelId = selected.id;
      }
    });
  }

  Future<void> _pickSample() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final file = File(path);
    final size = await file.length();
    final mime =
        path.toLowerCase().endsWith('.wav') ? 'audio/wav' : 'audio/mpeg';
    setState(() {
      _samplePath = path;
      _sampleMime = mime;
      _sampleSize = size;
      _status = null;
    });
  }

  Future<void> _previewDesign() async {
    final model = _selectedModel(_designModelId);
    final prompt = _designPromptCtrl.text.trim();
    final text = _designTextCtrl.text.trim();
    if (model == null) {
      setState(() => _status = '请先选择音色设计模型');
      return;
    }
    if (prompt.isEmpty || text.isEmpty) {
      setState(() => _status = '请填写音色描述和试听文本');
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在生成试听…';
    });
    try {
      final audio = await TtsService.synthesize(
        model: model,
        text: text,
        voice: '',
        instructions: prompt,
      );
      _enqueuePreview(audio, messageId: 'design_preview');
      setState(() => _status = '试听已生成，正在播放');
    } catch (e) {
      setState(() => _status = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _previewClone() async {
    final model = _selectedModel(_cloneModelId);
    final text = _cloneTextCtrl.text.trim();
    final samplePath = _samplePath;
    if (model == null) {
      setState(() => _status = '请先选择声音克隆模型');
      return;
    }
    if (samplePath == null || text.isEmpty) {
      setState(() => _status = '请选择音频样本并填写试听文本');
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在克隆试听…';
    });
    try {
      final bytes = await File(samplePath).readAsBytes();
      final dataUri = 'data:$_sampleMime;base64,${base64Encode(bytes)}';
      final audio = await TtsService.synthesize(
        model: model,
        text: text,
        voice: dataUri,
        instructions: '',
      );
      _enqueuePreview(audio, messageId: 'clone_preview');
      setState(() => _status = '克隆试听已生成，正在播放');
    } catch (e) {
      setState(() => _status = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  void _enqueuePreview(TtsAudioData audio, {required String messageId}) {
    TtsPlaybackController.instance.playAudio(audio, messageId: messageId);
  }

  Future<void> _saveAudioAs() async {
    final playback = TtsPlaybackController.instance;
    final path = playback.currentAudioPath;
    if (path == null) return;
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '另存为测试音频',
        fileName: 'voice_preview_${DateTime.now().millisecondsSinceEpoch}'
            '.${path.split('.').last}',
      );
      if (result == null) return;
      final ok = await playback.saveCurrentAudio(result);
      setState(() {
        _status = ok ? '已另存到 $result' : '另存失败';
      });
    } catch (e) {
      setState(() => _status = '另存失败：$e');
    }
  }

  Future<void> _saveToCharacter() async {
    final samplePath = _samplePath;
    if (samplePath == null) {
      setState(() => _status = '请先选择克隆样本');
      return;
    }
    final characters = context.read<CharacterProvider>().characters;
    if (characters.isEmpty) {
      setState(() => _status = '暂无角色可保存');
      return;
    }
    final selected = await showCupertinoModalPopup<Character>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.5,
          ),
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: ctx.scaffoldColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in characters)
                CupertinoListTile(
                  title: Text(c.displayName),
                  subtitle: const Text('保存克隆样本到此角色'),
                  onTap: () => Navigator.pop(ctx, c),
                ),
              CupertinoButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final provider = context.read<CharacterProvider>();
    final sampleFile = File(samplePath);
    final sampleName =
        'voice_${selected.id}_${DateTime.now().millisecondsSinceEpoch}'
        '${samplePath.toLowerCase().endsWith('.wav') ? '.wav' : '.mp3'}';
    final storageDir = await _voiceStorageDir();
    final destPath = '${storageDir.path}/$sampleName';
    await sampleFile.copy(destPath);

    final updated = selected.copyWith(
      voiceType: 'clone',
      voiceSampleFile: destPath,
      voiceMimeType: _sampleMime ?? 'audio/mpeg',
    );
    provider.updateCharacterInfo(
      selected.id,
      voiceType: updated.voiceType,
      voiceSampleFile: updated.voiceSampleFile,
      voiceMimeType: updated.voiceMimeType,
    );
    setState(() => _status = '已保存到角色「${selected.displayName}」');
  }

  Future<Directory> _voiceStorageDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/voice_samples');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  @override
  Widget build(BuildContext context) {
    final characters = context.watch<CharacterProvider>().characters;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('声音工作台'),
      ),
      child: ListView(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '选择 TTS 模型设计音色或复刻声音，并保存到角色卡。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: context.textSecondaryColor,
              ),
            ),
          ),
          // ── 音色设计 ──
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('音色设计'),
            children: [
              CupertinoListTile(
                title: Text(
                    _selectedModel(_designModelId)?.displayName ?? '选择设计模型'),
                subtitle: Text(
                  _selectedModel(_designModelId)?.modelName ??
                      '点击选择用于音色设计的 TTS 模型',
                  style: TextStyle(
                      fontSize: 12, color: context.textSecondaryColor),
                ),
                trailing: Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: context.textSecondaryColor,
                ),
                onTap: _busy ? null : () => _pickModel(forClone: false),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CupertinoTextField(
                      controller: _designPromptCtrl,
                      placeholder: '音色描述，如：温柔清澈的年轻女声，语速稍慢…',
                      maxLines: 3,
                      decoration: BoxDecoration(
                        color: context.scaffoldColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CupertinoTextField(
                      controller: _designTextCtrl,
                      placeholder: '试听文本',
                      maxLines: 2,
                      decoration: BoxDecoration(
                        color: context.scaffoldColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CupertinoButton.filled(
                      onPressed: _busy ? null : _previewDesign,
                      child: const Text('生成试听'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // ── 声音克隆 ──
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('声音克隆'),
            children: [
              CupertinoListTile(
                title: Text(
                    _selectedModel(_cloneModelId)?.displayName ?? '选择克隆模型'),
                subtitle: Text(
                  _selectedModel(_cloneModelId)?.modelName ??
                      '点击选择用于声音克隆的 TTS 模型',
                  style: TextStyle(
                      fontSize: 12, color: context.textSecondaryColor),
                ),
                trailing: Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: context.textSecondaryColor,
                ),
                onTap: _busy ? null : () => _pickModel(forClone: true),
              ),
              CupertinoListTile(
                title: Text(_samplePath == null
                    ? '选择音频样本（mp3 / wav）'
                    : _samplePath!.split('/').last),
                subtitle: Text(
                  _samplePath == null
                      ? '样本建议 10–20 秒清晰人声'
                      : '${(_sampleSize / 1024).toStringAsFixed(0)} KB · $_sampleMime',
                  style: TextStyle(
                      fontSize: 12, color: context.textSecondaryColor),
                ),
                trailing: Icon(
                  CupertinoIcons.folder,
                  color: context.accentColor,
                ),
                onTap: _busy ? null : _pickSample,
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CupertinoTextField(
                      controller: _cloneTextCtrl,
                      placeholder: '克隆试听文本',
                      maxLines: 2,
                      decoration: BoxDecoration(
                        color: context.scaffoldColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CupertinoButton.filled(
                      onPressed: _busy ? null : _previewClone,
                      child: const Text('克隆试听'),
                    ),
                    const SizedBox(height: 4),
                    CupertinoButton(
                      onPressed: _busy ? null : _saveToCharacter,
                      child: const Text('保存到角色…'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // ── 试听播放器 ──
          ListenableBuilder(
            listenable: TtsPlaybackController.instance,
            builder: (context, _) {
              final playback = TtsPlaybackController.instance;
              final hasAudio = playback.currentAudioPath != null;
              final isPlaying =
                  playback.snapshot.phase == TtsPlaybackPhase.playing;
              final isPaused = playback.isPaused;
              return CupertinoListSection.insetGrouped(
                backgroundColor: context.scaffoldColor,
                decoration: BoxDecoration(
                  color: context.listBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                header: const Text('试听播放器'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(44, 44),
                          onPressed: !hasAudio
                              ? null
                              : () {
                                  if (isPaused) {
                                    playback.resume();
                                  } else if (isPlaying) {
                                    playback.pause();
                                  } else {
                                    // 播放结束后重新播放当前文件
                                    final path = playback.currentAudioPath;
                                    if (path != null) {
                                      playback.playAudio(
                                        TtsAudioData(
                                          File(path).readAsBytesSync(),
                                          path.split('.').last,
                                        ),
                                      );
                                    }
                                  }
                                },
                          child: Icon(
                            isPaused || !isPlaying
                                ? CupertinoIcons.play_fill
                                : CupertinoIcons.pause_fill,
                            size: 32,
                            color: hasAudio
                                ? context.accentColor
                                : context.textSecondaryColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            hasAudio
                                ? (isPlaying
                                    ? (isPaused ? '已暂停' : '播放中…')
                                    : '播放结束')
                                : '暂无音频，请先生成试听',
                            style: TextStyle(
                              fontSize: 13,
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: !hasAudio ? null : () => _saveAudioAs(),
                          child: Icon(
                            CupertinoIcons.square_arrow_down,
                            size: 24,
                            color: hasAudio
                                ? context.accentColor
                                : context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          // ── 已保存声音 ──
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('已保存声音'),
            children: characters.isEmpty
                ? [const CupertinoListTile(title: Text('暂无角色'))]
                : [
                    for (final c in characters)
                      CupertinoListTile(
                        title: Text(c.displayName),
                        subtitle: Text(
                          switch (c.voiceType) {
                            'clone' =>
                              '克隆样本 · ${c.voiceSampleFile.split('/').last}',
                            'design' => '文本设计',
                            _ =>
                              c.voiceId.isEmpty ? '未设置' : '预置音色 · ${c.voiceId}',
                          },
                          style: TextStyle(
                              fontSize: 12, color: context.textSecondaryColor),
                        ),
                      ),
                  ],
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _status!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: context.textSecondaryColor,
                ),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

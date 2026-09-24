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

  @override
  void dispose() {
    _designPromptCtrl.dispose();
    _designTextCtrl.dispose();
    _cloneTextCtrl.dispose();
    super.dispose();
  }

  ApiModel? get _mimoTtsModel {
    final api = context.read<ApiProvider>();
    for (final m in api.models) {
      if (m.modelName.toLowerCase().contains('mimo') &&
          m.modelName.toLowerCase().contains('tts')) {
        return m;
      }
    }
    return api.getModelById(api.ttsModelId);
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
    final model = _mimoTtsModel;
    final prompt = _designPromptCtrl.text.trim();
    final text = _designTextCtrl.text.trim();
    if (model == null) {
      setState(() => _status = '请先在 API 设置中配置 MiMo TTS 模型');
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
        model: model.copyWith(modelName: 'mimo-v2.5-tts-voicedesign'),
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
    final model = _mimoTtsModel;
    final text = _cloneTextCtrl.text.trim();
    final samplePath = _samplePath;
    if (model == null) {
      setState(() => _status = '请先在 API 设置中配置 MiMo TTS 模型');
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
        model: model.copyWith(modelName: 'mimo-v2.5-tts-voiceclone'),
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
              '使用 MiMo TTS 设计音色或复刻声音，并保存到角色卡。',
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

import 'dart:async';
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
import '../widgets/settings/settings_ui.dart';

/// 【我】→ 声音工作台：音色设计、声音克隆、已保存声音管理。
class VoiceWorkbenchScreen extends StatefulWidget {
  const VoiceWorkbenchScreen({super.key});

  @override
  State<VoiceWorkbenchScreen> createState() => _VoiceWorkbenchScreenState();
}

class _VoiceWorkbenchScreenState extends State<VoiceWorkbenchScreen> {
  final _scrollController = ScrollController();
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
  void initState() {
    super.initState();
    final api = context.read<ApiProvider>();
    _designModelId = api.ttsDesignModelId;
    _cloneModelId = api.ttsCloneModelId;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _designPromptCtrl.dispose();
    _designTextCtrl.dispose();
    _cloneTextCtrl.dispose();
    super.dispose();
  }

  List<ApiModel> _modelsFor(String capability) => context
      .read<ApiProvider>()
      .models
      .where((m) => TtsService.supportsCapability(m, capability))
      .toList(growable: false);

  ApiModel? _modelFor(String? id, String capability) {
    if (id == null) return null;
    final models = _modelsFor(capability);
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }

  String _protocolLabel(ApiModel model) =>
      switch (TtsService.protocolFor(model)) {
        TtsProtocol.openAi => 'OpenAI',
        TtsProtocol.mimo => 'MiMo',
        TtsProtocol.minimax => 'MiniMax',
        TtsProtocol.qwen => 'Qwen',
        null => '禁用',
      };

  String _modelSubtitle(ApiModel model) {
    final caps = TtsService.capabilitiesFor(model)
        .map((cap) {
          return switch (cap) {
            TtsCapabilities.speech => '朗读',
            TtsCapabilities.design => '设计',
            TtsCapabilities.clone => '克隆',
            _ => cap,
          };
        })
        .join(' · ');
    return '${model.modelName} · ${_protocolLabel(model)}${caps.isEmpty ? '' : ' · $caps'}';
  }

  List<SettingsChoiceOption<String?>> _modelOptions(String capability) => [
    const SettingsChoiceOption<String?>(value: null, label: '未设置'),
    for (final model in _modelsFor(capability))
      SettingsChoiceOption<String?>(
        value: model.id,
        label: model.displayName,
        subtitle: _modelSubtitle(model),
      ),
  ];

  Future<void> _pickSample() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    final lower = path.toLowerCase();
    if (!lower.endsWith('.mp3') && !lower.endsWith('.wav')) {
      setState(() => _status = '只支持 mp3 或 wav 音频样本');
      return;
    }
    final size = await File(path).length();
    if (size > 10 * 1024 * 1024) {
      setState(() => _status = '音频样本不能超过 10 MB');
      return;
    }
    setState(() {
      _samplePath = path;
      _sampleMime = lower.endsWith('.wav') ? 'audio/wav' : 'audio/mpeg';
      _sampleSize = size;
      _status = null;
    });
  }

  Future<void> _previewDesign() async {
    final model = _modelFor(_designModelId, TtsCapabilities.design);
    final prompt = _designPromptCtrl.text.trim();
    final text = _designTextCtrl.text.trim();
    if (model == null) {
      setState(() => _status = '暂无支持音色设计的模型，请先在 API 设置中配置');
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
      unawaited(_enqueuePreview(audio, messageId: 'design_preview'));
      if (mounted) setState(() => _status = '试听已生成，正在播放');
    } catch (e) {
      if (mounted) setState(() => _status = _readableError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewClone() async {
    final model = _modelFor(_cloneModelId, TtsCapabilities.clone);
    final text = _cloneTextCtrl.text.trim();
    final source = _samplePath;
    if (model == null) {
      setState(() => _status = '暂无支持声音克隆的模型，请配置 MiMo voiceclone 能力');
      return;
    }
    if (source == null || text.isEmpty) {
      setState(() => _status = '请选择音频样本并填写试听文本');
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在克隆试听…';
    });
    try {
      final bytes = await File(source).readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        throw const TtsException('音频样本不能超过 10 MB');
      }
      final audio = await TtsService.synthesize(
        model: model,
        text: text,
        voice: 'data:$_sampleMime;base64,${base64Encode(bytes)}',
      );
      unawaited(_enqueuePreview(audio, messageId: 'clone_preview'));
      if (mounted) setState(() => _status = '克隆试听已生成，正在播放');
    } catch (e) {
      if (mounted) setState(() => _status = _readableError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _readableError(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  Future<void> _enqueuePreview(
    TtsAudioData audio, {
    required String messageId,
  }) => TtsPlaybackController.instance.playAudio(audio, messageId: messageId);

  Future<void> _saveAudioAs() async {
    final path = TtsPlaybackController.instance.currentAudioPath;
    if (path == null) return;
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '另存为测试音频',
      fileName:
          'voice_preview_${DateTime.now().millisecondsSinceEpoch}.${path.split('.').last}',
    );
    if (result == null || !mounted) return;
    final ok = await TtsPlaybackController.instance.saveCurrentAudio(result);
    if (mounted) setState(() => _status = ok ? '已另存到 $result' : '另存失败');
  }

  Future<Directory> _voiceStorageDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/voice');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Character?> _chooseCharacter(String subtitle) async {
    final characters = context.read<CharacterProvider>().characters;
    if (characters.isEmpty) {
      setState(() => _status = '暂无角色可保存');
      return null;
    }
    return showCupertinoModalPopup<Character>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * .55,
          ),
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: ctx.scaffoldColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  subtitle,
                  style: TextStyle(color: ctx.textSecondaryColor),
                ),
              ),
              for (final c in characters)
                CupertinoListTile(
                  title: Text(c.displayName),
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
  }

  Future<void> _saveDesignToCharacter() async {
    final prompt = _designPromptCtrl.text.trim();
    if (prompt.isEmpty) {
      setState(() => _status = '请先填写音色描述');
      return;
    }
    final selected = await _chooseCharacter('将音色设计保存到角色');
    if (selected == null || !mounted) return;
    await context.read<CharacterProvider>().updateCharacterInfo(
      selected.id,
      voiceType: 'design',
      voiceId: '',
      voiceInstructions: prompt,
      voiceSampleFile: '',
      voiceTemplatePath: '',
      voiceMimeType: '',
    );
    if (mounted) setState(() => _status = '已应用到角色「${selected.displayName}」');
  }

  Future<void> _saveCloneToCharacter() async {
    final characterProvider = context.read<CharacterProvider>();
    final source = _samplePath;
    if (source == null) {
      setState(() => _status = '请先选择克隆样本');
      return;
    }
    final selected = await _chooseCharacter('将克隆样本保存到角色');
    if (selected == null || !mounted) return;
    final ext = source.toLowerCase().endsWith('.wav') ? 'wav' : 'mp3';
    final name =
        'voice_${selected.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final dir = await _voiceStorageDir();
    final destination = File('${dir.path}/$name');
    await File(source).copy(destination.path);
    await characterProvider.updateCharacterInfo(
      selected.id,
      voiceType: 'clone',
      voiceId: '',
      voiceInstructions: '',
      voiceSampleFile: 'voice/$name',
      voiceTemplatePath: destination.path,
      voiceMimeType: ext == 'wav' ? 'audio/wav' : 'audio/mpeg',
    );
    if (mounted) setState(() => _status = '已保存到角色「${selected.displayName}」');
  }

  Future<String?> _sampleForCharacter(Character character) async {
    final candidate = character.voiceTemplatePath.isNotEmpty
        ? character.voiceTemplatePath
        : character.voiceSampleFile;
    if (candidate.isEmpty) return null;
    final direct = File(candidate);
    if (await direct.exists()) return direct.path;
    final docs = await getApplicationDocumentsDirectory();
    final relative = candidate.replaceFirst(RegExp(r'^[/\\]+'), '');
    final fromDocs = File('${docs.path}/$relative');
    return await fromDocs.exists() ? fromDocs.path : null;
  }

  Future<void> _playSaved(Character character) async {
    try {
      final api = context.read<ApiProvider>();
      if (character.voiceType == 'clone') {
        final path = await _sampleForCharacter(character);
        final model = _modelFor(api.ttsCloneModelId, TtsCapabilities.clone);
        if (path == null) throw const TtsException('样本文件缺失，请重新编辑声音');
        if (model == null) throw const TtsException('请先配置声音克隆模型');
        final bytes = await File(path).readAsBytes();
        final mime = character.voiceMimeType.isNotEmpty
            ? character.voiceMimeType
            : (path.toLowerCase().endsWith('.wav')
                  ? 'audio/wav'
                  : 'audio/mpeg');
        final audio = await TtsService.synthesize(
          model: model,
          text: '这是保存声音的试听。',
          voice: 'data:$mime;base64,${base64Encode(bytes)}',
        );
        unawaited(_enqueuePreview(audio, messageId: 'saved_${character.id}'));
      } else if (character.voiceType == 'design') {
        final model = _modelFor(api.ttsDesignModelId, TtsCapabilities.design);
        if (model == null) throw const TtsException('请先配置音色设计模型');
        final audio = await TtsService.synthesize(
          model: model,
          text: '这是保存音色的试听。',
          instructions: character.voiceInstructions,
        );
        unawaited(_enqueuePreview(audio, messageId: 'saved_${character.id}'));
      } else {
        if (character.voiceId.isEmpty) {
          throw const TtsException('该角色尚未设置预置音色');
        }
        final model = _modelFor(api.ttsModelId, TtsCapabilities.speech);
        if (model == null) throw const TtsException('请先配置普通朗读模型');
        final audio = await TtsService.synthesize(
          model: model,
          text: '这是预置音色的试听。',
          voice: character.voiceId,
        );
        unawaited(_enqueuePreview(audio, messageId: 'saved_${character.id}'));
      }
      if (mounted) setState(() => _status = '正在播放「${character.displayName}」');
    } catch (e) {
      if (mounted) setState(() => _status = _readableError(e));
    }
  }

  Future<void> _editSaved(Character character) async {
    if (character.voiceType == 'clone') {
      final path = await _sampleForCharacter(character);
      if (path == null) {
        setState(() => _status = '样本文件缺失，请重新选择音频样本');
        return;
      }
      final size = await File(path).length();
      setState(() {
        _samplePath = path;
        _sampleSize = size;
        _sampleMime = character.voiceMimeType.isNotEmpty
            ? character.voiceMimeType
            : (path.toLowerCase().endsWith('.wav')
                  ? 'audio/wav'
                  : 'audio/mpeg');
        _status = '已载入「${character.displayName}」的样本，可重新试听';
      });
    } else if (character.voiceType == 'design') {
      _designPromptCtrl.text = character.voiceInstructions;
      setState(() => _status = '已载入「${character.displayName}」的音色描述');
    }
  }

  Future<void> _clearSaved(Character character) async {
    final characterProvider = context.read<CharacterProvider>();
    final path = await _sampleForCharacter(character);
    await characterProvider.updateCharacterInfo(character.id, clearVoice: true);
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {
        // 文件已被用户删除时仍然完成配置清理。
      }
    }
    if (mounted) {
      setState(() => _status = '已清除「${character.displayName}」的角色音频配置');
    }
  }

  Widget _modelPicker({required bool clone}) {
    final capability = clone ? TtsCapabilities.clone : TtsCapabilities.design;
    final current = clone ? _cloneModelId : _designModelId;
    final model = _modelFor(current, capability);
    return SettingsInlinePicker<String?>(
      value: current,
      options: _modelOptions(capability),
      panelKey: clone
          ? 'voice-workbench-clone-model'
          : 'voice-workbench-design-model',
      onChanged: (value) {
        setState(() {
          if (clone) {
            _cloneModelId = value;
          } else {
            _designModelId = value;
          }
        });
        final api = context.read<ApiProvider>();
        if (clone) {
          api.setTtsCloneModel(value);
        } else {
          api.setTtsDesignModel(value);
        }
      },
      rowBuilder: (context, toggle) => SettingsRow(
        icon: clone
            ? CupertinoIcons.waveform_path_ecg
            : CupertinoIcons.sparkles,
        title: Text(clone ? '克隆模型' : '设计模型'),
        subtitle: Text(
          model == null
              ? '暂无具备${clone ? '克隆' : '设计'}能力的模型'
              : _modelSubtitle(model),
        ),
        showChevron: true,
        onTap: _busy ? null : toggle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 订阅 API Provider，使模型删除或能力编辑后工作台立即刷新。
    context.watch<ApiProvider>();
    final characters = context.watch<CharacterProvider>().characters;
    return CupertinoPageScaffold(
      navigationBar: settingsNavigationBar(context, '声音工作台'),
      backgroundColor: context.scaffoldColor,
      child: ListView(
        key: const PageStorageKey<String>('voice-workbench-list'),
        controller: _scrollController,
        padding: settingsPageContentPadding(context),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              '为角色设计音色或复刻声音，试听后即可保存。模型选择会自动保留。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: context.textSecondaryColor,
              ),
            ),
          ),
          SettingsSection(
            title: '音色设计',
            children: [
              _modelPicker(clone: false),
              SettingsRow(
                icon: CupertinoIcons.text_quote,
                title: const Text('音色描述'),
                subtitle: Text(
                  _designPromptCtrl.text.isEmpty
                      ? '描述音色、语气和语速'
                      : _designPromptCtrl.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: _busy
                    ? null
                    : () => _editText(
                        _designPromptCtrl,
                        '音色描述',
                        '温柔清澈的年轻女声，语速稍慢',
                      ),
              ),
              SettingsRow(
                icon: CupertinoIcons.text_bubble,
                title: const Text('试听文本'),
                subtitle: Text(
                  _designTextCtrl.text.isEmpty
                      ? '输入一段用于试听的文字'
                      : _designTextCtrl.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: _busy
                    ? null
                    : () => _editText(_designTextCtrl, '试听文本', '你好，这是一段音色试听。'),
              ),
              SettingsRow(
                icon: CupertinoIcons.play_circle,
                iconColor: context.accentColor,
                title: Text(
                  '生成试听',
                  style: TextStyle(
                    color: context.accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: _busy ? null : _previewDesign,
              ),
              SettingsRow(
                icon: CupertinoIcons.person_crop_circle_badge_plus,
                title: const Text('应用到角色'),
                onTap: _busy ? null : _saveDesignToCharacter,
              ),
            ],
          ),
          SettingsSection(
            title: '声音克隆',
            children: [
              _modelPicker(clone: true),
              SettingsRow(
                icon: CupertinoIcons.folder,
                title: Text(
                  _samplePath == null
                      ? '选择音频样本'
                      : _samplePath!.split(RegExp(r'[/\\]')).last,
                ),
                subtitle: Text(
                  _samplePath == null
                      ? '支持 mp3 / wav，最大 10 MB'
                      : '${(_sampleSize / 1024).toStringAsFixed(0)} KB · $_sampleMime',
                ),
                onTap: _busy ? null : _pickSample,
              ),
              SettingsRow(
                icon: CupertinoIcons.text_bubble,
                title: const Text('克隆试听文本'),
                subtitle: Text(
                  _cloneTextCtrl.text.isEmpty
                      ? '输入一段用于试听的文字'
                      : _cloneTextCtrl.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: _busy
                    ? null
                    : () => _editText(_cloneTextCtrl, '克隆试听文本', '你好，这是克隆声音试听。'),
              ),
              SettingsRow(
                icon: CupertinoIcons.play_circle,
                iconColor: context.accentColor,
                title: Text(
                  '生成克隆试听',
                  style: TextStyle(
                    color: context.accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: _busy ? null : _previewClone,
              ),
              SettingsRow(
                icon: CupertinoIcons.person_crop_circle_badge_plus,
                title: const Text('应用到角色'),
                onTap: _busy ? null : _saveCloneToCharacter,
              ),
            ],
          ),
          _buildPlayer(),
          SettingsSection(
            title: '已保存声音',
            children: characters.isEmpty
                ? [
                    const SettingsRow(
                      icon: CupertinoIcons.info,
                      title: Text('暂无角色'),
                    ),
                  ]
                : [
                    for (final character in characters)
                      SettingsRow(
                        icon: character.voiceType == 'clone'
                            ? CupertinoIcons.waveform
                            : CupertinoIcons.person_crop_circle,
                        title: Text(character.displayName),
                        subtitle: Text(_voiceLabel(character)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => _playSaved(character),
                              child: const Icon(CupertinoIcons.play, size: 19),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => _editSaved(character),
                              child: const Icon(
                                CupertinoIcons.pencil,
                                size: 18,
                              ),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => _clearSaved(character),
                              child: const Icon(
                                CupertinoIcons.delete,
                                size: 18,
                                color: CupertinoColors.systemRed,
                              ),
                            ),
                          ],
                        ),
                        trailingWidth: 144,
                      ),
                  ],
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                _status!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: context.textSecondaryColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _voiceLabel(Character character) => switch (character.voiceType) {
    'clone' =>
      character.voiceSampleFile.isEmpty
          ? '克隆样本（缺失）'
          : '克隆样本 · ${character.voiceSampleFile.split('/').last}',
    'design' =>
      character.voiceInstructions.isEmpty
          ? '音色设计'
          : '音色设计 · ${character.voiceInstructions}',
    _ => character.voiceId.isEmpty ? '预置音色未设置' : '预置音色 · ${character.voiceId}',
  };

  Widget _buildPlayer() {
    return ListenableBuilder(
      listenable: TtsPlaybackController.instance,
      builder: (context, _) {
        final playback = TtsPlaybackController.instance;
        final hasAudio = playback.currentAudioPath != null;
        final playing = playback.snapshot.phase == TtsPlaybackPhase.playing;
        final paused = playback.isPaused;
        return SettingsSection(
          title: '试听播放器',
          children: [
            SettingsRow(
              icon: paused || !playing
                  ? CupertinoIcons.play_fill
                  : CupertinoIcons.pause_fill,
              iconColor: hasAudio ? context.accentColor : null,
              title: Text(
                hasAudio
                    ? (playing ? (paused ? '已暂停' : '播放中…') : '播放结束')
                    : '暂无试听音频',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: !hasAudio
                        ? null
                        : () {
                            if (paused) {
                              playback.resume();
                            } else if (playing) {
                              playback.pause();
                            } else {
                              _replayCurrent();
                            }
                          },
                    child: Icon(
                      paused || !playing
                          ? CupertinoIcons.play_fill
                          : CupertinoIcons.pause_fill,
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: !hasAudio ? null : _replayCurrent,
                    child: const Icon(CupertinoIcons.gobackward),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: !hasAudio ? null : _saveAudioAs,
                    child: const Icon(CupertinoIcons.square_arrow_down),
                  ),
                ],
              ),
              trailingWidth: 132,
            ),
          ],
        );
      },
    );
  }

  Future<void> _replayCurrent() async {
    final path = TtsPlaybackController.instance.currentAudioPath;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    await TtsPlaybackController.instance.playAudio(
      TtsAudioData(bytes, path.split('.').last),
      messageId: 'replay',
    );
  }

  Future<void> _editText(
    TextEditingController controller,
    String title,
    String hint,
  ) async {
    final field = TextEditingController(text: controller.text);
    final value = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: field,
            placeholder: hint,
            maxLines: 4,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, field.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    field.dispose();
    if (value != null && mounted) setState(() => controller.text = value);
  }
}

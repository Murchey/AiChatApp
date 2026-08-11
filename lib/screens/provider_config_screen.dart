import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/provider_preset.dart';
import '../providers/api_provider.dart';
import '../services/llm_service.dart';

/// 厂商设置二级页面：填写请求地址与 API Key，
/// 勾选本地推荐模型（或【检测可用模型】在线拉取）后点击底部「保存」批量添加。
class ProviderConfigScreen extends StatefulWidget {
  final ProviderPreset preset;

  const ProviderConfigScreen({super.key, required this.preset});

  @override
  State<ProviderConfigScreen> createState() => _ProviderConfigScreenState();
}

class _ProviderConfigScreenState extends State<ProviderConfigScreen> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;

  // 模型勾选列表（本地推荐 + 手动添加 + 在线检测），以 modelName 为唯一标识
  final List<({String displayName, String modelName})> _modelEntries = [];
  final Set<String> _checked = {};
  bool _detecting = false; // 检测可用模型中

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: widget.preset.baseUrl);
    _apiKeyController = TextEditingController();
    _modelEntries.addAll(widget.preset.models);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  /// 手动输入模型名称加入勾选列表
  Future<void> _addManualModel() async {
    final controller = TextEditingController();
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('添加模型'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('输入模型名称（API 调用使用的 ID）'),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              placeholder: '如 gpt-4o-mini',
              decoration: BoxDecoration(
                border: Border.all(color: context.separatorColor),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    setState(() {
      if (!_modelEntries.any((m) => m.modelName == name)) {
        _modelEntries.add((displayName: name, modelName: name));
      }
      _checked.add(name);
    });
  }

  /// 在线拉取该服务商全部可用模型，并入勾选列表（新获取的自动勾选）
  Future<void> _detectModels() async {
    if (_detecting) return;
    setState(() => _detecting = true);
    try {
      final ids = await LLMService.fetchAvailableModels(
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
      );
      if (!mounted) return;
      var added = 0;
      setState(() {
        for (final id in ids) {
          if (!_modelEntries.any((m) => m.modelName == id)) {
            _modelEntries.add((displayName: id, modelName: id));
            added++;
          }
          _checked.add(id);
        }
      });
      _showDialog(
        '检测完成',
        '共获取 ${ids.length} 个模型（新增 $added 个），已全部勾选。\n请取消不需要的模型后点击底部「保存」。',
      );
    } catch (e) {
      if (!mounted) return;
      _showDialog('检测失败', LLMService.describeException(e));
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  /// 保存勾选的模型：逐个写入 ApiProvider，上下文长度由本地注册表补全
  Future<void> _save() async {
    final api = context.read<ApiProvider>();
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final selected =
        _modelEntries.where((m) => _checked.contains(m.modelName)).toList();
    if (selected.isEmpty) {
      _showDialog('提示', '请先勾选要添加的模型');
      return;
    }
    final added = <ApiModel>[];
    for (final m in selected) {
      final contextLength =
          LLMService.localContextLength(m.modelName) ?? 8000;
      added.add(await api.addModel(
        displayName: m.displayName,
        modelName: m.modelName,
        baseUrl: baseUrl,
        apiKey: apiKey,
        contextLength: contextLength,
      ));
    }
    if (!mounted) return;
    _showDialog('添加成功', '已添加 ${added.length} 个模型。', thenPop: true);
    // 添加成功后后台自动检测上下文长度并保存：
    // 本地注册表未命中的模型联网探测 /models，探测成功自动更新
    for (final model in added) {
      unawaited(_autoDetectContext(api, model));
    }
  }

  /// 后台检测模型上下文长度并更新保存（失败静默，不影响使用）
  Future<void> _autoDetectContext(ApiProvider api, ApiModel model) async {
    final length = await LLMService.detectContextLength(model);
    if (length == null || length == model.contextLength) return;
    await api.updateModel(model.copyWith(contextLength: length));
    debugPrint('[ProviderConfig] ${model.modelName} 上下文长度自动更新为 $length');
  }

  void _showDialog(String title, String message, {bool thenPop = false}) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              if (thenPop && context.mounted) Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 区块右上角的小按钮（添加 / 检测可用模型）
  Widget _buildHeaderButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool loading = false,
  }) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: context.accentColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CupertinoActivityIndicator(),
              )
            else
              Icon(icon, size: 14, color: context.accentColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 列表样式输入项
  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String placeholder,
    bool obscureText = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: context.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 4),
          CupertinoTextField(
            controller: controller,
            placeholder: placeholder,
            obscureText: obscureText,
            autocorrect: false,
            style: TextStyle(
              fontSize: 16,
              color: context.textPrimaryColor,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: context.separatorColor,
                  width: 0.5,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.preset.name),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                const SizedBox(height: 12),
                // 连接配置：请求地址 + API Key
                CupertinoListSection.insetGrouped(
                  backgroundColor: context.scaffoldColor,
                  decoration: BoxDecoration(
                    color: context.listBgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  header: const Text('连接配置'),
                  children: [
                    _buildField(
                      controller: _baseUrlController,
                      label: 'API 请求地址',
                      placeholder: widget.preset.baseUrl,
                    ),
                    _buildField(
                      controller: _apiKeyController,
                      label: 'API Key',
                      placeholder: '输入你的 API Key',
                      obscureText: true,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 可用模型：本地推荐 + 手动添加 + 在线检测，勾选后保存
                CupertinoListSection.insetGrouped(
                  backgroundColor: context.scaffoldColor,
                  decoration: BoxDecoration(
                    color: context.listBgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  header: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text('可用模型（${_modelEntries.length}）'),
                        const Spacer(),
                        _buildHeaderButton(
                          icon: CupertinoIcons.plus,
                          label: '添加',
                          onTap: _addManualModel,
                        ),
                        const SizedBox(width: 10),
                        _buildHeaderButton(
                          icon: CupertinoIcons.arrow_down_circle,
                          label: '检测可用模型',
                          onTap: _detectModels,
                          loading: _detecting,
                        ),
                      ],
                    ),
                  ),
                  children: [
                    if (_modelEntries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '暂无模型，可点击右上角「检测可用模型」在线获取，或「添加」手动输入。',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ),
                    for (final m in _modelEntries)
                      CupertinoListTile(
                        onTap: () => setState(() {
                          if (!_checked.remove(m.modelName)) {
                            _checked.add(m.modelName);
                          }
                        }),
                        leading: Icon(
                          _checked.contains(m.modelName)
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.circle,
                          size: 22,
                          color: _checked.contains(m.modelName)
                              ? context.accentColor
                              : context.separatorColor,
                        ),
                        title: Text(
                          m.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        subtitle: Text(
                          m.modelName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '勾选模型后点击底部「保存并添加」；上下文长度由本地注册表自动补全，未匹配的模型可用默认值并在「添加模型」中手动修改。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          // 底部保存栏
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: 8 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: context.scaffoldColor,
              border: Border(
                top: BorderSide(
                  color: context.separatorColor,
                  width: 0.5,
                ),
              ),
            ),
            child: CupertinoButton.filled(
              color: context.accentColor,
              onPressed: _save,
              child: const Text(
                '保存并添加',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

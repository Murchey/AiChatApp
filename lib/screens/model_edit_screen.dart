import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/api_provider.dart';
import '../services/llm_service.dart';

/// 模型编辑二级页面（添加 / 编辑模型）
class ModelEditScreen extends StatefulWidget {
  /// 传入模型则为编辑模式，为 null 则为添加模式
  final ApiModel? model;

  const ModelEditScreen({super.key, this.model});

  @override
  State<ModelEditScreen> createState() => _ModelEditScreenState();
}

class _ModelEditScreenState extends State<ModelEditScreen> {
  late final TextEditingController _displayController;
  late final TextEditingController _modelNameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _contextController;
  bool _detecting = false; // 上下文长度自动检测中

  bool get _isEdit => widget.model != null;

  @override
  void initState() {
    super.initState();
    _displayController =
        TextEditingController(text: widget.model?.displayName ?? '');
    _modelNameController =
        TextEditingController(text: widget.model?.modelName ?? '');
    _baseUrlController =
        TextEditingController(text: widget.model?.baseUrl ?? '');
    _apiKeyController =
        TextEditingController(text: widget.model?.apiKey ?? '');
    _contextController = TextEditingController(
      text: (widget.model?.contextLength ?? 8000).toString(),
    );
  }

  @override
  void dispose() {
    _displayController.dispose();
    _modelNameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _contextController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final api = context.read<ApiProvider>();
    final displayName = _displayController.text.trim();
    final modelName = _modelNameController.text.trim();
    if (displayName.isEmpty || modelName.isEmpty) {
      // 必填字段为空时提示
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('提示'),
          content: const Text('请填写展示名称和模型名称'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return;
    }
    // 上下文长度：解析失败用默认 8000，限制在 1000~1000000 之间
    final parsedContext = int.tryParse(_contextController.text.trim()) ?? 8000;
    final contextLength = parsedContext.clamp(1000, 1000000);
    if (_isEdit) {
      await api.updateModel(widget.model!.copyWith(
        displayName: displayName,
        modelName: modelName,
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        contextLength: contextLength,
      ));
    } else {
      await api.addModel(
        displayName: displayName,
        modelName: modelName,
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        contextLength: contextLength,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  /// 一键填入 DeepSeek 官方配置（仅填充空白字段）
  void _applyDeepSeekPreset() {
    setState(() {
      if (_displayController.text.trim().isEmpty) {
        _displayController.text = 'DeepSeek Chat';
      }
      if (_modelNameController.text.trim().isEmpty) {
        _modelNameController.text = 'deepseek-chat';
      }
      if (_baseUrlController.text.trim().isEmpty) {
        _baseUrlController.text = 'https://api.deepseek.com';
      }
      // 上下文长度仍是默认值 8000 时，填入官方 64K 上下文
      if (_contextController.text.trim() == '8000') {
        _contextController.text = '65536';
      }
    });
  }

  /// 自动检测模型上下文长度：请求 /models 接口，失败时按模型名启发式估算；
  /// 检测到结果后回填到上下文长度输入框。
  Future<void> _detectContext() async {
    if (_detecting) return;
    final modelName = _modelNameController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    if (modelName.isEmpty) {
      _showDetectDialog('提示', '请先填写模型名称，再进行自动检测');
      return;
    }
    setState(() => _detecting = true);
    try {
      final length = await LLMService.detectContextLength(ApiModel(
        id: 'detect',
        displayName: '',
        modelName: modelName,
        baseUrl: baseUrl,
        apiKey: apiKey,
      ));
      if (!mounted) return;
      if (length != null) {
        setState(() {
          _contextController.text = length.toString();
        });
        _showDetectDialog(
          '检测成功',
          '「$modelName」的上下文长度约为 $length token，已自动填入。\n\n如与官方文档不一致，可手动修改。',
        );
      } else {
        _showDetectDialog(
          '未能检测到',
          '无法从接口或模型名判断上下文长度，请根据模型官方文档手动填写。',
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showDetectDialog('检测失败', LLMService.describeException(e));
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  void _showDetectDialog(String title, String message) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(_isEdit ? '编辑模型' : '添加模型'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _save,
          child: Text(
            '保存',
            style: TextStyle(
              color: context.accentColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      child: ListView(
        children: [
          const SizedBox(height: 12),
          // DeepSeek 官方一键预设
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('快捷预设'),
            children: [
              CupertinoListTile(
                leading: Icon(
                  CupertinoIcons.sparkles,
                  color: context.accentColor,
                ),
                title: Text(
                  'DeepSeek 官方配置',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: context.textPrimaryColor,
                  ),
                ),
                subtitle: Text(
                  '自动填入官方接口地址与 deepseek-chat 模型，仅需补充 API Key',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
                trailing: Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: context.textSecondaryColor,
                ),
                onTap: _applyDeepSeekPreset,
              ),
            ],
          ),
          const SizedBox(height: 12),
          CupertinoListSection.insetGrouped(
            backgroundColor: context.scaffoldColor,
            decoration: BoxDecoration(
              color: context.listBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            header: const Text('基本信息'),
            children: [
              _buildField(
                controller: _displayController,
                label: '展示名称',
                placeholder: '用于界面显示，如 DeepSeek Chat',
              ),
              _buildField(
                controller: _modelNameController,
                label: '模型名称',
                placeholder: 'API 调用使用，如 deepseek-chat / deepseek-reasoner',
              ),
              _buildField(
                controller: _contextController,
                label: '上下文长度（token）',
                placeholder: '如 65536，用于会话压缩 70% 阈值',
                keyboardType: TextInputType.number,
                trailing: _buildDetectButton(),
              ),
            ],
          ),
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
                placeholder: 'DeepSeek 官方为 https://api.deepseek.com，留空则使用官方默认',
              ),
              _buildField(
                controller: _apiKeyController,
                label: 'API Key',
                placeholder: '输入你的 API Key（DeepSeek 在 platform.deepseek.com 申请）',
                obscureText: true,
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 上下文长度输入框右侧的「自动检测」按钮
  Widget _buildDetectButton() {
    return GestureDetector(
      onTap: _detecting ? null : _detectContext,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: context.accentColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: _detecting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CupertinoActivityIndicator(),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.wand_stars,
                    size: 14,
                    color: context.accentColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '自动检测',
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

  /// 列表样式输入项（无边框背景，贴近 iOS 原生设置页）
  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String placeholder,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textSecondaryColor,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 4),
          CupertinoTextField(
            controller: controller,
            placeholder: placeholder,
            obscureText: obscureText,
            autocorrect: false,
            keyboardType: keyboardType,
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
}

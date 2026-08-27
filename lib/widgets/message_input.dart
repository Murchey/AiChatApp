import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../config/theme.dart';
import '../screens/sticker_picker_screen.dart';
import 'chat_send_button.dart';

enum _InputPanel { none, grid, sticker }

class MessageInput extends StatefulWidget {
  final Function(String) onSend;
  final Function(String)? onPickImage;
  final Function(String, String)? onPickFile; // (文件路径, 文件名)
  final VoidCallback? onSettings; // 打开聊天设置
  final VoidCallback? onExport; // 导出聊天记录
  final VoidCallback? onImport; // 导入聊天记录（zip）
  final Future<bool> Function()? onFeatureDetect; // 功能检测：测试当前模型是否支持图片（返回是否通过）
  final Future<void> Function(StickerSelection selection)? onStickerSelected;
  final bool showStickerButton;
  final VoidCallback? onRoleplayNarration;
  final bool isRoleplayMode;
  final List<String> roleplayChoices;
  final ValueChanged<String>? onRoleplayChoice;
  final VoidCallback? onRequestReply; // 请求角色回复（对号按钮触发）
  final bool replyEnabled; // 对号按钮是否可点：上一条消息是用户发送时才可点
  /// 外部可通过此 key 调用 setText / focus
  final GlobalKey<MessageInputState>? inputKey;

  const MessageInput({
    super.key,
    this.inputKey,
    required this.onSend,
    this.onPickImage,
    this.onPickFile,
    this.onSettings,
    this.onExport,
    this.onImport,
    this.onFeatureDetect,
    this.onStickerSelected,
    this.showStickerButton = true,
    this.onRoleplayNarration,
    this.isRoleplayMode = false,
    this.roleplayChoices = const [],
    this.onRoleplayChoice,
    this.onRequestReply,
    this.replyEnabled = true,
  });

  @override
  MessageInputState createState() => MessageInputState();
}

class MessageInputState extends State<MessageInput>
    with WidgetsBindingObserver {
  // 原生系统文件选择（MainActivity 中实现，Android 专用）
  static const MethodChannel _fileChannel =
      MethodChannel('com.aichat.ai_chat/files');

  final TextEditingController _controller = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final FocusNode _inputFocusNode = FocusNode();
  bool _hasText = false;
  _InputPanel _panel = _InputPanel.none;
  _InputPanel? _pendingPanel;
  final PageController _roleplayPanelController = PageController();
  double? _lastKeyboardHeight;

  /// 外部可直接设置输入框内容
  void setText(String text) {
    _controller.text = text;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: text.length),
    );
    setState(() {
      _hasText = text.trim().isNotEmpty;
    });
  }

  /// 聚焦输入框
  void focus() {
    FocusScope.of(context).requestFocus(_inputFocusNode);
  }

  /// 切换网格菜单显示
  void toggleGrid() {
    setState(() {
      _panel = _panel == _InputPanel.grid ? _InputPanel.none : _InputPanel.grid;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(() {
      setState(() {
        _hasText = _controller.text.trim().isNotEmpty;
      });
    });
    // 点击（聚焦）输入框时自动折叠面板
    _inputFocusNode.addListener(() {
      if (_inputFocusNode.hasFocus) {
        _pendingPanel = null;
      }
      if (_inputFocusNode.hasFocus && _panel != _InputPanel.none) {
        setState(() {
          _panel = _InputPanel.none;
        });
      }
    });
  }

  @override
  void didChangeMetrics() {
    // 显式延迟逻辑负责等待 IME 最后一帧，避免 metrics 先归零时抢先展示 Panel。
  }

  @override
  void didUpdateWidget(covariant MessageInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.showStickerButton && _panel == _InputPanel.sticker) {
      _panel = _InputPanel.none;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _inputFocusNode.dispose();
    _roleplayPanelController.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSend(text);
      _controller.clear();
    }
  }

  void _requestPanelAfterKeyboardDismissal(_InputPanel panel) {
    // 不依赖当前 viewInsets 判定“键盘是否已经退场”：部分 Android 输入法会先
    // 报告 inset=0、再完成最后几帧绘制。统一先请求隐藏，再延迟接管底部区域。
    _pendingPanel = panel;
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (!mounted || _pendingPanel != panel) return;
      if (MediaQuery.viewInsetsOf(context).bottom == 0) {
        setState(() {
          _panel = panel;
          _pendingPanel = null;
        });
      }
    });
  }

  void _handleToggleGrid() {
    if (_panel == _InputPanel.grid) {
      // 面板已打开：点击加号关闭面板，恢复键盘（聚焦输入框）
      FocusScope.of(context).requestFocus(_inputFocusNode);
      setState(() {
        _panel = _InputPanel.none;
      });
    } else {
      // 先完全收起键盘，再插入等高面板，避免两者同时占用布局造成上冲。
      _requestPanelAfterKeyboardDismissal(_InputPanel.grid);
    }
  }

  void _handleStickerTap() {
    // 表情包面板和加号面板共用输入栏状态，互相排斥。
    if (_panel == _InputPanel.sticker) {
      FocusScope.of(context).requestFocus(_inputFocusNode);
      setState(() => _panel = _InputPanel.none);
      return;
    }
    _requestPanelAfterKeyboardDismissal(_InputPanel.sticker);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboardInset > 0) _lastKeyboardHeight = keyboardInset;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 输入栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: context.navBarColor,
            border: Border(
              top: BorderSide(color: context.separatorColor),
            ),
          ),
          child: SafeArea(
            top: false,
            // 加号/表情面板在输入栏下方时，底部安全区只由面板负责；
            // 否则输入栏和面板会重复占用导航栏高度，导致与键盘顶端不齐。
            bottom: _panel == _InputPanel.none,
            child: Row(
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _handleToggleGrid,
                  child: Icon(
                    _panel == _InputPanel.grid
                        ? CupertinoIcons.keyboard
                        : CupertinoIcons.add_circled,
                    color: context.textSecondaryColor,
                  ),
                ),
                if (widget.showStickerButton)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _handleStickerTap,
                    child: Icon(
                      CupertinoIcons.smiley,
                      color: context.accentColor,
                    ),
                  ),
                Expanded(
                  child: CupertinoTextField(
                    controller: _controller,
                    focusNode: _inputFocusNode,
                    placeholder: '输入消息...',
                    maxLines: 4,
                    minLines: 1,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    style: TextStyle(
                      fontSize: 16,
                      color: context.textPrimaryColor,
                    ),
                    decoration: BoxDecoration(
                      color: context.fieldBgColor,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                // 右侧按钮：有输入内容时显示"发送"，无内容时显示"对号"（点击请求角色回复）
                if (_hasText) ...[
                  // 发送按钮：经典主题色实底 / zmd 终末地深底金边（64×40，圆角 10px）
                  ChatSendButton(onPressed: _handleSend),
                ] else if (widget.onRequestReply != null) ...[
                  CupertinoButton(
                    padding: const EdgeInsets.all(4),
                    onPressed:
                        widget.replyEnabled ? widget.onRequestReply : null,
                    child: Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      size: 30,
                      color: widget.replyEnabled
                          ? context.accentColor
                          : context.textSecondaryColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // 网格菜单面板（位于输入框下方，将输入框抬起）
        if (_panel == _InputPanel.grid)
          widget.isRoleplayMode
              ? _buildRoleplayPanel(context)
              : _buildGridPanel(context),
        if (_panel == _InputPanel.sticker)
          SizedBox(
            height: _panelHeight(context),
            child: StickerPickerScreen.embedded(
              onSelected: (selection) async {
                await widget.onStickerSelected?.call(selection);
                if (mounted) setState(() => _panel = _InputPanel.none);
              },
              onClose: () => setState(() => _panel = _InputPanel.none),
            ),
          ),
      ],
    );
  }

  Widget _buildRoleplayPanel(BuildContext context) {
    return SizedBox(
      height: _panelHeight(context),
      child: PageView(
        controller: _roleplayPanelController,
        children: [
          _buildRoleplayChoicesPage(context),
          _buildGridPanel(context),
        ],
      ),
    );
  }

  Widget _buildRoleplayChoicesPage(BuildContext context) {
    final choices = widget.roleplayChoices;
    return Container(
      color: context.navBarColor,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              choices.isEmpty ? '等待角色回复后生成候选行动' : '候选行动',
              style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: choices.isEmpty
                  ? Center(
                      child: Text(
                        '角色回复后，这里会提供 4 个可继续推进剧情的选项',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: choices.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final choice = choices[index];
                        return CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          color: context.fieldBgColor,
                          borderRadius: BorderRadius.circular(10),
                          alignment: Alignment.centerLeft,
                          onPressed: () {
                            widget.onRoleplayChoice?.call(choice);
                            setState(() => _panel = _InputPanel.none);
                          },
                          child: Text(
                            '${index + 1}. $choice',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: context.textPrimaryColor,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Center(
              child: Text(
                '左划查看更多功能',
                style:
                    TextStyle(fontSize: 12, color: context.textSecondaryColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridPanel(BuildContext context) {
    final items = [
      // 【相册】【拍照】不主动禁用：是否支持图片由发送时的模型能力决定，
      // 用户可随时通过【功能检测】测试当前模型对图片的支持情况
      _GridItem(
        icon: CupertinoIcons.photo,
        label: '相册',
        onTap: () async {
          setState(() => _panel = _InputPanel.none);
          final file = await _picker.pickImage(source: ImageSource.gallery);
          if (file != null && widget.onPickImage != null) {
            widget.onPickImage!(file.path);
          }
        },
      ),
      _GridItem(
        icon: CupertinoIcons.camera,
        label: '拍照',
        onTap: () async {
          setState(() => _panel = _InputPanel.none);
          final file = await _picker.pickImage(source: ImageSource.camera);
          if (file != null && widget.onPickImage != null) {
            widget.onPickImage!(file.path);
          }
        },
      ),
      _GridItem(
        icon: CupertinoIcons.doc,
        label: '文件',
        onTap: () async {
          setState(() => _panel = _InputPanel.none);
          try {
            final result = await _fileChannel.invokeMethod('pickFile');
            if (result != null && widget.onPickFile != null) {
              final map = Map<String, dynamic>.from(result as Map);
              widget.onPickFile!(
                map['path'] as String,
                map['name'] as String,
              );
            }
          } on PlatformException catch (e) {
            if (mounted) _showPickError(e.message ?? '选择文件失败');
          } catch (_) {
            if (mounted) _showPickError('选择文件失败，请重试');
          }
        },
      ),
      _GridItem(
        icon: CupertinoIcons.arrow_down_doc,
        label: '导入记录',
        onTap: () {
          setState(() => _panel = _InputPanel.none);
          widget.onImport?.call();
        },
      ),
      // ── 第二行：原右上角菜单功能 ──
      _GridItem(
        icon: CupertinoIcons.settings,
        label: '聊天设置',
        onTap: () {
          setState(() => _panel = _InputPanel.none);
          widget.onSettings?.call();
        },
      ),
      _GridItem(
        icon: CupertinoIcons.share_up,
        label: '导出聊天',
        onTap: () {
          setState(() => _panel = _InputPanel.none);
          widget.onExport?.call();
        },
      ),
      _GridItem(
        icon: CupertinoIcons.wrench,
        label: '功能检测',
        onTap: () {
          setState(() => _panel = _InputPanel.none);
          // 检测结果由调用方弹窗提示（不依赖返回值做按钮禁用）
          widget.onFeatureDetect?.call();
        },
      ),
      if (widget.onRoleplayNarration != null)
        _GridItem(
          icon: CupertinoIcons.book,
          label: '剧情行动',
          onTap: () {
            setState(() => _panel = _InputPanel.none);
            widget.onRoleplayNarration!.call();
          },
        ),
    ];

    final panelHeight = _panelHeight(context);

    return SizedBox(
      height: panelHeight,
      child: Container(
        color: context.navBarColor,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: SafeArea(
          top: false,
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 16,
            children:
                items.map((item) => _buildGridTile(context, item)).toList(),
          ),
        ),
      ),
    );
  }

  double _panelHeight(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final keyboardHeight = _lastKeyboardHeight;
    if (keyboardHeight == null) {
      return (MediaQuery.sizeOf(context).height * 0.4).clamp(280.0, 420.0);
    }
    // SafeArea 会在键盘收起后额外加入底部系统安全区，面板外层先扣除，
    // 使「面板 + SafeArea」的总高度严格等于键盘实际占用高度。
    return (keyboardHeight - safeBottom).clamp(0.0, keyboardHeight);
  }

  Widget _buildGridTile(BuildContext context, _GridItem item) {
    return GestureDetector(
      onTap: item.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: context.fieldBgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              item.icon,
              size: 28,
              color: context.textPrimaryColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondaryColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showPickError(String message) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('提示'),
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
}

class _GridItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GridItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

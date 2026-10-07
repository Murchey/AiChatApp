import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/theme.dart';
import '../../config/ui_spec.dart';
import '../chat_send_button.dart';

/// 群聊底部输入框：与私聊输入框视觉一致（方形 5px 圆角 + 加号面板 + 发送/对号）。
/// 加号面板含【相册】【拍照】【文件】【功能检测】【导出记录】【导入记录】；
/// 输入 @ 触发成员选择（onMentionRequest）；对号触发群聊回复。
class GroupMessageInput extends StatefulWidget {
  final Color? backdropColor;
  final ValueChanged<String> onSend;
  final VoidCallback onRequestReply;
  final bool replyEnabled;
  final ValueChanged<String>? onPickImage;
  final void Function(String, String)? onPickFile;
  final Future<bool> Function()? onFeatureDetect;

  /// 输入 @ 时回调（由外层弹出成员选择）
  final VoidCallback? onMentionRequest;
  final VoidCallback? onExport;
  final VoidCallback? onImport;

  /// 打开群聊上下文设置（加号面板入口）
  final VoidCallback? onContextSettings;

  /// 剧情建议：询问补充后生成可填入输入框的建议（语C/短信通用）
  final VoidCallback? onPlotSuggestion;

  const GroupMessageInput({
    super.key,
    this.backdropColor,
    required this.onSend,
    required this.onRequestReply,
    required this.replyEnabled,
    this.onPickImage,
    this.onPickFile,
    this.onFeatureDetect,
    this.onMentionRequest,
    this.onExport,
    this.onImport,
    this.onContextSettings,
    this.onPlotSuggestion,
  });

  @override
  State<GroupMessageInput> createState() => GroupMessageInputState();
}

class GroupMessageInputState extends State<GroupMessageInput>
    with WidgetsBindingObserver {
  // 原生系统文件选择（MainActivity 中实现，Android 专用）
  static const MethodChannel _fileChannel = MethodChannel(
    'com.aichat.ai_chat/files',
  );

  final TextEditingController _controller = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final FocusNode _inputFocusNode = FocusNode();
  bool _showGrid = false;
  bool _pendingGrid = false;
  double? _lastKeyboardHeight;
  bool _prevEndsAt = false; // @ 边沿检测：上一次文本是否以 @ 结尾

  /// 外部（撤回消息）可回填输入框内容
  void setText(String text) {
    _controller.text = text;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: text.length),
    );
  }

  /// 输入 @ 选中成员后插入「@名字 」（替换文本末尾孤立的 @）。
  void appendMention(String name) {
    var text = _controller.text;
    if (text.endsWith('@')) {
      text = text.substring(0, text.length - 1);
    }
    final offset = _controller.selection.isValid
        ? _controller.selection.baseOffset.clamp(0, text.length)
        : text.length;
    final insert = '@$name ';
    final newText = text.substring(0, offset) + insert + text.substring(offset);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: offset + insert.length),
    );
  }

  void focus() {
    FocusScope.of(context).requestFocus(_inputFocusNode);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 点击（聚焦）输入框时自动折叠面板
    _inputFocusNode.addListener(() {
      if (_inputFocusNode.hasFocus) _pendingGrid = false;
      if (_inputFocusNode.hasFocus && _showGrid) {
        setState(() => _showGrid = false);
      }
    });
  }

  @override
  void didChangeMetrics() {
    if (!_pendingGrid) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pendingGrid) return;
      if (MediaQuery.viewInsetsOf(context).bottom == 0) {
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          if (!mounted || !_pendingGrid) return;
          if (MediaQuery.viewInsetsOf(context).bottom == 0) {
            setState(() {
              _showGrid = true;
              _pendingGrid = false;
            });
          }
        });
      }
    });
  }

  /// 文本变化（用户输入）处理：检测「刚输入 @」边沿，触发成员选择。
  /// 用 onChanged（仅用户编辑触发）而非原始 controller 监听，
  /// 并通过微任务延迟 push 弹层，避免同步 push 路由导致的触发失败。
  void _handleInputChanged(String text) {
    final endsWithAt = text.endsWith('@');
    final justTypedAt = endsWithAt && !_prevEndsAt;
    _prevEndsAt = endsWithAt;
    if (justTypedAt) {
      Future.microtask(() => widget.onMentionRequest?.call());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  void _handleToggleGrid() {
    if (_showGrid) {
      // 面板已打开：点击加号关闭面板，恢复键盘（聚焦输入框）
      FocusScope.of(context).requestFocus(_inputFocusNode);
      setState(() => _showGrid = false);
    } else {
      // 键盘仍在收起动画期间不能插入面板，否则两者会叠加把输入栏顶过高。
      if (MediaQuery.viewInsetsOf(context).bottom == 0) {
        setState(() => _showGrid = true);
      } else {
        _pendingGrid = true;
        FocusManager.instance.primaryFocus?.unfocus();
        SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboardInset > 0) _lastKeyboardHeight = keyboardInset;
    return Container(
      color: widget.backdropColor ?? context.navBarColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showGrid) _buildGridPanel(context),
          // 输入栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: widget.backdropColor ?? context.navBarColor,
              border: Border(top: BorderSide(color: context.separatorColor)),
            ),
            child: SafeArea(
              top: false,
              // 面板位于下方时，输入栏不重复保留导航栏安全区；
              // 与键盘展开时一致，避免两种状态的输入栏顶端产生高度差。
              bottom: !_showGrid,
              child: Row(
                children: [
                  // 左侧加号：展开功能面板（相册/拍照/文件/功能检测）
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(28, 28),
                    onPressed: _handleToggleGrid,
                    child: Icon(
                      _showGrid
                          ? CupertinoIcons.keyboard
                          : CupertinoIcons.add_circled,
                      size: 26,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: CupertinoTextField(
                      controller: _controller,
                      focusNode: _inputFocusNode,
                      onChanged: _handleInputChanged,
                      placeholder: '输入消息...',
                      maxLines: 4,
                      minLines: 1,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      style: TextStyle(
                        fontSize: 16,
                        color: context.textPrimaryColor,
                      ),
                      decoration: BoxDecoration(
                        color: context.fieldBgColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  // 右侧按钮只订阅文本值，避免输入时重建整个输入栏。
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, _) {
                      final hasText = value.text.trim().isNotEmpty;
                      if (hasText) {
                        return Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: ChatSendButton(onPressed: _handleSend),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(36, 36),
                          onPressed: widget.replyEnabled
                              ? widget.onRequestReply
                              : null,
                          child: Icon(
                            CupertinoIcons.checkmark_circle_fill,
                            size: 30,
                            color: widget.replyEnabled
                                ? context.accentColor
                                : context.textSecondaryColor,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridPanel(BuildContext context) {
    final items = [
      // 【相册】【拍照】不主动禁用：是否支持图片由发送时的模型能力决定
      GroupGridItem(
        icon: CupertinoIcons.photo,
        label: '相册',
        onTap: () async {
          setState(() => _showGrid = false);
          final file = await _picker.pickImage(source: ImageSource.gallery);
          if (file != null && widget.onPickImage != null) {
            widget.onPickImage!(file.path);
          }
        },
      ),
      GroupGridItem(
        icon: CupertinoIcons.camera,
        label: '拍照',
        onTap: () async {
          setState(() => _showGrid = false);
          final file = await _picker.pickImage(source: ImageSource.camera);
          if (file != null && widget.onPickImage != null) {
            widget.onPickImage!(file.path);
          }
        },
      ),
      GroupGridItem(
        icon: CupertinoIcons.doc,
        label: '文件',
        onTap: () async {
          setState(() => _showGrid = false);
          try {
            final result = await _fileChannel.invokeMethod('pickFile');
            if (result != null && widget.onPickFile != null) {
              final map = Map<String, dynamic>.from(result as Map);
              widget.onPickFile!(map['path'] as String, map['name'] as String);
            }
          } on PlatformException catch (e) {
            if (mounted) _showPickError(e.message ?? '选择文件失败');
          } catch (_) {
            if (mounted) _showPickError('选择文件失败，请重试');
          }
        },
      ),
      GroupGridItem(
        icon: CupertinoIcons.wrench,
        label: '功能检测',
        onTap: () {
          setState(() => _showGrid = false);
          // 检测结果由外层弹窗提示（不依赖返回值做按钮禁用）
          widget.onFeatureDetect?.call();
        },
      ),
      if (widget.onPlotSuggestion != null)
        GroupGridItem(
          icon: CupertinoIcons.sparkles,
          label: '剧情建议',
          onTap: () {
            setState(() => _showGrid = false);
            widget.onPlotSuggestion!.call();
          },
        ),
      GroupGridItem(
        icon: CupertinoIcons.arrow_down_circle,
        label: '导出记录',
        onTap: () {
          setState(() => _showGrid = false);
          widget.onExport?.call();
        },
      ),
      GroupGridItem(
        icon: CupertinoIcons.arrow_up_circle,
        label: '导入记录',
        onTap: () {
          setState(() => _showGrid = false);
          widget.onImport?.call();
        },
      ),
      GroupGridItem(
        icon: CupertinoIcons.slider_horizontal_3,
        label: '上下文',
        onTap: () {
          setState(() => _showGrid = false);
          widget.onContextSettings?.call();
        },
      ),
    ];

    final keyboardHeight = _lastKeyboardHeight;
    final panelHeight = keyboardHeight == null
        ? (MediaQuery.sizeOf(context).height * 0.30).clamp(200.0, 320.0)
        : (keyboardHeight - MediaQuery.viewPaddingOf(context).bottom).clamp(
            0.0,
            keyboardHeight,
          );

    return SizedBox(
      height: panelHeight,
      child: Container(
        color: widget.backdropColor ?? context.navBarColor,
        padding: const EdgeInsets.fromLTRB(
          16,
          UiSpec.inputPanelTopPadding,
          16,
          UiSpec.inputPanelBottomPadding,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Container(
                width: UiSpec.inputPanelHandleWidth,
                height: UiSpec.inputPanelHandleHeight,
                decoration: BoxDecoration(
                  color: context.textSecondaryColor.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: UiSpec.inputPanelHandleGap),
              Expanded(
                child: GridView.count(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  crossAxisCount: 4,
                  mainAxisSpacing: UiSpec.inputPanelRowGap,
                  crossAxisSpacing: 16,
                  children: items
                      .map((item) => _buildGridTile(context, item))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridTile(BuildContext context, GroupGridItem item) {
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
            child: Icon(item.icon, size: 28, color: context.textPrimaryColor),
          ),
          const SizedBox(height: 6),
          Text(
            item.label,
            style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
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

class GroupGridItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const GroupGridItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

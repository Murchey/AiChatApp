import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../config/theme.dart';

class MessageInput extends StatefulWidget {
  final Function(String) onSend;
  final Function(String)? onPickImage;
  final Function(String, String)? onPickFile; // (文件路径, 文件名)
  /// 外部可通过此 key 调用 setText / focus
  final GlobalKey<MessageInputState>? inputKey;

  const MessageInput({
    super.key,
    this.inputKey,
    required this.onSend,
    this.onPickImage,
    this.onPickFile,
  });

  @override
  MessageInputState createState() => MessageInputState();
}

class MessageInputState extends State<MessageInput> {
  // 原生系统文件选择（MainActivity 中实现，Android 专用）
  static const MethodChannel _fileChannel =
      MethodChannel('com.aichat.ai_chat/files');

  final TextEditingController _controller = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final FocusNode _inputFocusNode = FocusNode();
  bool _hasText = false;
  bool _showGrid = false;

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
      _showGrid = !_showGrid;
    });
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _hasText = _controller.text.trim().isNotEmpty;
      });
    });
    // 点击（聚焦）输入框时自动折叠面板
    _inputFocusNode.addListener(() {
      if (_inputFocusNode.hasFocus && _showGrid) {
        setState(() {
          _showGrid = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSend(text);
      _controller.clear();
    }
  }

  void _handleToggleGrid() {
    if (_showGrid) {
      // 面板已打开：点击加号关闭面板，恢复键盘（聚焦输入框）
      FocusScope.of(context).requestFocus(_inputFocusNode);
      setState(() {
        _showGrid = false;
      });
    } else {
      // 面板未打开：点击加号，收起软键盘，只展示面板
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _showGrid = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
            child: Row(
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _handleToggleGrid,
                  child: Icon(
                    _showGrid
                        ? CupertinoIcons.keyboard
                        : CupertinoIcons.add_circled,
                    color: context.textSecondaryColor,
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
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                // 发送按钮：输入内容后才显示
                if (_hasText) ...[
                  CupertinoButton.filled(
                    onPressed: _handleSend,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    borderRadius: BorderRadius.circular(20),
                    child: const Text(
                      '发送',
                      style: TextStyle(
                        color: CupertinoColors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // 网格菜单面板（位于输入框下方，将输入框抬起）
        if (_showGrid) _buildGridPanel(context),
      ],
    );
  }

  Widget _buildGridPanel(BuildContext context) {
    final items = [
      _GridItem(
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
      _GridItem(
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
      _GridItem(
        icon: CupertinoIcons.doc,
        label: '文件',
        onTap: () async {
          setState(() => _showGrid = false);
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
        icon: CupertinoIcons.money_dollar_circle,
        label: '转账',
        onTap: () {
          setState(() => _showGrid = false);
        },
      ),
    ];

    return Container(
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
          children: items
              .map((item) => _buildGridTile(context, item))
              .toList(),
        ),
      ),
    );
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
            child: Icon(item.icon, size: 28, color: context.textPrimaryColor),
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

import 'package:flutter/cupertino.dart';

import '../config/theme.dart';

/// 备份密码输入页：创建备份时可设密，恢复加密包时校验密码。
///
/// pop 返回密码字符串；取消返回 null。
/// [requireConfirm] 为 true 时要求两次输入一致（创建备份）。
class BackupPasswordScreen extends StatefulWidget {
  final String title;
  final String message;
  final bool requireConfirm;
  final String confirmLabel;

  const BackupPasswordScreen({
    super.key,
    required this.title,
    required this.message,
    this.requireConfirm = false,
    this.confirmLabel = '确定',
  });

  @override
  State<BackupPasswordScreen> createState() => _BackupPasswordScreenState();
}

class _BackupPasswordScreenState extends State<BackupPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final pwd = _password.text;
    if (widget.requireConfirm && pwd != _confirm.text) {
      setState(() => _error = '两次输入的密码不一致');
      return;
    }
    Navigator.pop(context, pwd);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.title),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            Text(
              widget.message,
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondaryColor,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            _label('密码'),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: _password,
              placeholder: '备份密码（可留空）',
              obscureText: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: context.fieldBgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            if (widget.requireConfirm) ...[
              const SizedBox(height: 16),
              _label('确认密码'),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _confirm,
                placeholder: '再次输入密码',
                obscureText: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: context.fieldBgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.destructiveRed,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              widget.requireConfirm
                  ? '留空表示不加密。加密使用 AES-256，忘记密码将无法恢复备份。'
                  : '若备份已加密请输入密码；未加密可留空。',
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: context.textSecondaryColor,
      ),
    );
  }
}

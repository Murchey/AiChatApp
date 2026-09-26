import 'package:flutter/cupertino.dart';

import '../config/theme.dart';
import '../services/cloud_backup_service.dart';

/// 对象储存设置页（腾讯云 COS / 阿里云 OSS）。
///
/// 从「数据备份 → 对象储存设置」进入；保存后 pop 返回 [CloudBackupConfig]。
class BackupCloudSettingsScreen extends StatefulWidget {
  final CloudBackupConfig initial;

  const BackupCloudSettingsScreen({super.key, required this.initial});

  @override
  State<BackupCloudSettingsScreen> createState() =>
      _BackupCloudSettingsScreenState();
}

class _BackupCloudSettingsScreenState
    extends State<BackupCloudSettingsScreen> {
  late final TextEditingController _secretId;
  late final TextEditingController _secretKey;
  late final TextEditingController _bucketUrl;
  late final TextEditingController _prefix;

  @override
  void initState() {
    super.initState();
    _secretId = TextEditingController(text: widget.initial.secretId);
    _secretKey = TextEditingController(text: widget.initial.secretKey);
    _bucketUrl = TextEditingController(text: widget.initial.bucketUrl);
    _prefix = TextEditingController(text: widget.initial.prefix);
  }

  @override
  void dispose() {
    _secretId.dispose();
    _secretKey.dispose();
    _bucketUrl.dispose();
    _prefix.dispose();
    super.dispose();
  }

  void _save() {
    final url = CloudBackupService.normalizeBucketUrl(_bucketUrl.text);
    Navigator.pop(
      context,
      CloudBackupConfig(
        secretId: _secretId.text.trim(),
        secretKey: _secretKey.text.trim(),
        bucketUrl: url,
        prefix: _prefix.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('对象储存设置'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _save,
          child: const Text('保存'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              '私有读写需要访问密钥。密钥仅保存在本机，请使用子账号并仅授权该存储桶。'
              '支持腾讯云 COS 与阿里云 OSS。',
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondaryColor,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            _section(
              title: '访问密钥',
              children: [
                _field(
                  controller: _secretId,
                  placeholder: 'SecretId / AccessKey ID',
                ),
                _divider(),
                _field(
                  controller: _secretKey,
                  placeholder: 'SecretKey / AccessKey Secret',
                  obscure: true,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _section(
              title: '存储桶',
              children: [
                _field(
                  controller: _bucketUrl,
                  placeholder:
                      'https://xxx-1250000000.cos.ap-guangzhou.myqcloud.com',
                  keyboardType: TextInputType.url,
                ),
                _divider(),
                _field(
                  controller: _prefix,
                  placeholder: '对象前缀（默认 backups/v1）',
                  keyboardType: TextInputType.url,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '存储桶 URL 可从控制台复制默认访问域名，无需单独填地域。'
              '对象前缀用于隔离备份目录，例如 backups/v1。',
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '示例：\n'
              '腾讯云 COS：https://demo-1250000000.cos.ap-guangzhou.myqcloud.com\n'
              '阿里云 OSS：https://my-bucket.oss-cn-hangzhou.aliyuncs.com',
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: context.textSecondaryColor,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.listBgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String placeholder,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      obscureText: obscure,
      keyboardType: keyboardType,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(),
    );
  }

  Widget _divider() {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: context.separatorColor,
    );
  }
}

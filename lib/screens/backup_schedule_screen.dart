import 'package:flutter/cupertino.dart';

import '../config/theme.dart';
import '../services/backup_schedule_service.dart';

/// 定时备份设置页（本地 / 云端各自独立进入）。
///
/// 从「数据备份 → 本地/云端定时备份」进入；保存后 pop 返回 [BackupScheduleConfig]。
class BackupScheduleScreen extends StatefulWidget {
  final String title;
  final BackupScheduleConfig initial;

  const BackupScheduleScreen({
    super.key,
    required this.title,
    required this.initial,
  });

  @override
  State<BackupScheduleScreen> createState() => _BackupScheduleScreenState();
}

class _BackupScheduleScreenState extends State<BackupScheduleScreen> {
  late BackupScheduleMode _mode;
  late int _weeklyDay;
  late int _monthlyDay;
  late bool _deletePrevious;
  late final TextEditingController _password;

  @override
  void initState() {
    super.initState();
    _mode = widget.initial.mode;
    _weeklyDay = widget.initial.weeklyDay;
    _monthlyDay = widget.initial.monthlyDay;
    _deletePrevious = widget.initial.deletePrevious;
    _password = TextEditingController(text: widget.initial.password);
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.pop(
      context,
      BackupScheduleConfig(
        mode: _mode,
        weeklyDay: _weeklyDay,
        monthlyDay: _monthlyDay,
        deletePrevious: _deletePrevious,
        password: _password.text,
      ),
    );
  }

  String _modeLabel(BackupScheduleMode m) => switch (m) {
        BackupScheduleMode.disabled => '关闭',
        BackupScheduleMode.onAppOpen => '打开 APP 时备份',
        BackupScheduleMode.daily => '每天备份',
        BackupScheduleMode.weekly => '每周备份',
        BackupScheduleMode.monthly => '每月备份',
      };

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.title),
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
              '定时任务在打开 APP 时触发。自动备份文件名以 aichat_auto 开头，'
              '与手动备份区分。',
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondaryColor,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            _section(
              title: '触发方式',
              children: [
                for (final m in [
                  BackupScheduleMode.onAppOpen,
                  BackupScheduleMode.daily,
                  BackupScheduleMode.weekly,
                  BackupScheduleMode.monthly,
                  BackupScheduleMode.disabled,
                ])
                  _radioTile(
                    label: _modeLabel(m),
                    selected: _mode == m,
                    onTap: () => setState(() => _mode = m),
                  ),
              ],
            ),
            if (_mode == BackupScheduleMode.weekly) ...[
              const SizedBox(height: 16),
              _section(
                title: '每周',
                children: [
                  for (var d = 1; d <= 7; d++)
                    _radioTile(
                      label: weekdayName(d),
                      selected: _weeklyDay == d,
                      onTap: () => setState(() => _weeklyDay = d),
                    ),
                ],
              ),
            ],
            if (_mode == BackupScheduleMode.monthly) ...[
              const SizedBox(height: 16),
              _section(
                title: '每月日期（超出当月天数按月末）',
                children: [
                  SizedBox(
                    height: 220,
                    child: CupertinoPicker(
                      itemExtent: 36,
                      scrollController: FixedExtentScrollController(
                        initialItem: (_monthlyDay - 1).clamp(0, 30),
                      ),
                      onSelectedItemChanged: (i) {
                        setState(() => _monthlyDay = i + 1);
                      },
                      children: [
                        for (var d = 1; d <= 31; d++)
                          Center(
                            child: Text(
                              '$d 日',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            _section(
              title: '自动备份选项',
              children: [
                _switchTile(
                  label: '自动备份时删除上次的自动备份',
                  subtitle: '仅删除同前缀自动备份，不影响手动备份',
                  value: _deletePrevious,
                  onChanged: (v) => setState(() => _deletePrevious = v),
                ),
                _divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '自动备份密码（可留空 = 不加密）',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: CupertinoTextField(
                    controller: _password,
                    placeholder: '预设加密密码',
                    obscureText: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: context.fieldBgColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '密码仅保存在本机。忘记密码将无法恢复加密的自动备份；'
              '手动备份仍可另行设置密码。',
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

  Widget _radioTile({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return CupertinoListTile(
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: selected
          ? Icon(
              CupertinoIcons.checkmark_alt,
              size: 20,
              color: context.accentColor,
            )
          : null,
      onTap: onTap,
    );
  }

  Widget _switchTile({
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return CupertinoListTile(
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: context.textSecondaryColor,
        ),
      ),
      trailing: CupertinoSwitch(
        value: value,
        onChanged: onChanged,
      ),
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

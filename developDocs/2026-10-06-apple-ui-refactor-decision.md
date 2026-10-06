# AiChatApp UI 重构决策摘要（2026-10-06）

- 保留现有聊天、角色、朋友圈和备份业务，仅调整公共主题 token 与高频容器，降低跨页面视觉漂移。
- 视觉采用 iMessage / ChatGPT / X 的克制 Apple 方向：`#F5F5F7` 级页面底、白色内容面、18 dp 卡片、12–14 dp 输入框、蓝色语义操作色；深色对应 `#0B0B0F` / `#111318`。
- 用户自定义气泡颜色、角色主题和现有四种气泡样式优先级高于默认 token，重构不能覆盖这些个性化设置。
- 所有新 token 只在 `lib/config/theme.dart` 与 `ui_spec.dart` 定义，页面继续通过 `BuildContext` 扩展读取，避免新增硬编码颜色。

## 本轮实现

- 更新应用壳层亮/暗背景为 Apple system background 语义，输入框和分组面使用 system fill。
- 统一卡片、输入框、按钮、气泡和面板圆角为 18/12/14/20 dp token。
- 默认主题色切换为 Apple Blue，保留用户自定义气泡与气泡主题优先级；现有备份、COS/OSS 和业务页面不改动。
- 经典气泡的默认发送方颜色改为 iMessage 蓝（`#0A84FF`），接收方继续使用 system gray；用户已经保存的自定义颜色和 SR/WW/ZMD 主题不被迁移覆盖。
- 已用 Android 模拟器构建、安装并检查首页与聊天页；启动后的异步初始化会在首屏后完成，聊天空状态、输入栏和深色壳层均可正常显示。

## 验证

- `flutter analyze lib` 通过（仅保留既有 lint info）。
- `flutter test` 全部通过（82 项）。
- `flutter build apk --debug` 成功，APK 已安装到 `emulator-5554`。

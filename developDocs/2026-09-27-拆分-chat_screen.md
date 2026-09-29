# chat_screen 拆分记录

## 2026-09-27 · 菜单 UI

| 项 | 内容 |
|----|------|
| 原文件 | `lib/screens/chat_screen.dart` |
| 新文件 | `lib/widgets/chat/chat_bubble_menu.dart` |
| 职责 | 长按菜单网格面板 `ChatBubbleMenuPanel` 与单格 `ChatBubbleMenuItem` |

## 2026-09-27 · 聊天记录导入导出

| 项 | 内容 |
|----|------|
| 原文件 | `lib/screens/chat_screen.dart` |
| 新文件 | `lib/screens/chat/chat_import_export.dart` |
| 职责 | 会话聊天记录 zip 导出 / 导入（`ChatImportExport`） |

`chat_screen` 仅保留 `_exportChat` / `_importChat` 薄委托。
`flutter analyze` 通过。

## 2026-09-27 · 角色回复触发

| 项 | 内容 |
|----|------|
| 原文件 | `lib/screens/chat_screen.dart` |
| 新文件 | `lib/screens/chat/chat_proactive_reply.dart` |
| 职责 | `ChatProactiveReply.trigger`：Prompt/记忆池组装、流式与非流式回复、自动朗读、语C候选 |

chat_screen 约 109KB → **93KB**（菜单 + 导入导出 + 回复触发已外置）。
`flutter analyze` 通过。

## 2026-09-27 · 多选 / 转发 / 记忆点

| 项 | 内容 |
|----|------|
| 原文件 | `lib/screens/chat_screen.dart` |
| 新文件 | `lib/screens/chat/chat_select_forward.dart` |
| 职责 | `ChatSelectForward`：存记忆点（含总结压缩）、逐条/合并转发、目标会话选择 |

chat_screen 约 93KB → **~81KB**。`flutter analyze` 通过。

## 2026-09-27 · 消息操作 / 剧情建议 / 时间与思考标签

| 原文件 | 新文件 | 职责 |
|--------|--------|------|
| chat_screen.dart | chat/chat_message_actions.dart | 查看思考、选择文本、编辑、撤回、重回、分支 |
| chat_screen.dart | chat/chat_plot_suggestion.dart | 剧情建议生成与回填 |
| chat_screen.dart | widgets/chat/chat_message_chrome.dart | 时间标签、思考时长标签 |

chat_screen：**109KB → 63KB**（仍 >800 行，继续拆 build 消息列表）。
lutter analyze 通过。

## 拆分标准（2026-09-27 调整）

**必须拆：>800 行 或 >40KB**（不再要求 20KB）。

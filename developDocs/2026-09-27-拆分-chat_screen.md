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

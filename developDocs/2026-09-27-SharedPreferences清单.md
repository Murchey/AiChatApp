# SharedPreferences 全量清单（存储迁移 · 步骤 1.1）

扫描范围：`lib/**/*.dart`（不含纯注释）
生成日期：2026-09-27

图例：`R` 读 / `W` 写 / `D` 删除

---

## 一、业务数据（迁移候选 · 步骤 1 优先）

### 1. 聊天 / 会话 / 消息  ← 首批迁移

| Key | 类型 | 读写 | 文件 |
|-----|------|------|------|
| `chat_conversations_v1` | String(JSON) | R/W/D | `providers/chat_provider.dart` |
| `chat_messages_v1` | String(JSON) | R/W/D | `providers/chat_provider.dart` |
| `chat_context_tokens_v1` | String(JSON) | R/W/D | `providers/chat_provider.dart` |
| `chat_system_tokens_v1` | String(JSON) | R/W/D | `providers/chat_provider.dart` |
| `chat_roleplay_choices_v1` | String(JSON) | R/W/D | `providers/chat_provider.dart` |

### 2. 角色列表  ← 首批迁移

| Key | 类型 | 读写 | 文件 |
|-----|------|------|------|
| `characters_v1` | String(JSON) | R/W | `providers/character_provider.dart` |
| `characters_deleted_v1` | StringList | R/W | `providers/character_provider.dart` |
| `visibility_groups_v1` | String(JSON) | R/W | `providers/character_provider.dart` |

### 3. 群聊

| Key | 类型 | 读写 | 文件 |
|-----|------|------|------|
| `group_chats_v1` | String(JSON) | R/W | `providers/group_chat_provider.dart` |
| `group_chat_messages_v1` | String(JSON) | R/W | `providers/group_chat_provider.dart` |

### 4. 记忆点（动态 key）

| Key | 类型 | 读写 | 文件 |
|-----|------|------|------|
| `memory_points_v1_{characterId}` | String(JSON) | R/W/D | `providers/memory_point_provider.dart`（前缀扫描 `getKeys`） |

### 5. Token 统计

| Key | 类型 | 读写 | 文件 |
|-----|------|------|------|
| `chat_token_usage_v1` | String(JSON) | R/W | `providers/token_usage_provider.dart` |

---

## 二、角色 / 互动配置

| Key | 类型 | 读写 | 文件 |
|-----|------|------|------|
| `proactive_greeting_configs_v1` | String(JSON) | R/W | `providers/proactive_greeting_provider.dart` |
| `auto_moment_configs_v1` | String(JSON) | R/W | `providers/auto_moment_provider.dart` |
| `moment_notifications_v1` | String(JSON) | R/W/D | `providers/moment_notification_provider.dart` |
| `moment_interaction_breakpoint_v1` | String(JSON) | R/W/D | `services/moment_ai_service.dart` |

---

## 三、表情包

| Key | 类型 | 读写 | 文件 |
|-----|------|------|------|
| `sticker_packs_v1` | String(JSON) | R/W | `providers/sticker_provider.dart` |
| `user_stickers_v1` | String(JSON) | R/W | `providers/sticker_provider.dart` |

---

## 四、聊天设置

| Key | 类型 | 读写 | 文件 |
|-----|------|------|------|
| `chat_context_count` | int | R/W | `providers/chat_settings_provider.dart` |
| `chat_selected_model` | String | R/W/D | 同上 |
| `chat_compress_enabled` | bool | R/W | 同上 |
| `chat_compress_threshold` | double | R/W | 同上 |
| `chat_moment_memory_count` | int | R/W | 同上 |
| `chat_memory_pool_disabled_sections` | String(JSON) | R/W | 同上 |
| `chat_message_mode` | String | R/W | 同上 |
| `chat_sticker_button_enabled` | bool | R/W | 同上 |
| `chat_roleplay_stream_enabled` | bool | R/W | 同上 |
| `chat_roleplay_progression_style` | String | R/W | 同上 |
| `chat_roleplay_choices_enabled` | bool | R/W | 同上 |
| `chat_thinking_level` | String | R/W | 同上 |
| `chat_show_thinking_duration` | bool | R/W | 同上 |

---

## 五、聊天背景（动态 key）

| Key | 类型 | 读写 | 文件 |
|-----|------|------|------|
| `chat_bg_image_{chatId}` | String(路径) | R/W | `providers/chat_background_provider.dart` |
| `chat_bg_blur_{chatId}` | double | R/W | `providers/chat_background_provider.dart` |

---

## 六、API / 模型

| Key | 类型 | 读写 | 文件 |
|-----|------|------|------|
| `api_models_v1` | String(JSON) | R/W | `providers/api_provider.dart` |
| `api_compress_model` | String | R/W/D | 同上 |
| `api_moment_model` | String | R/W/D | 同上 |
| `api_tts_model` | String | R/W/D | 同上 |
| `model_vision_v1` | String(JSON) | R/W | 同上 |

---

## 七、用户资料 / 外观设置

| Key | 类型 | 读写 | 文件 |
|-----|------|------|------|
| `user_id` | String | R/W | `providers/auth_provider.dart` |
| `user_nickname` | String | R/W | 同上 |
| `user_avatar` | String(base64) | R/W/D | 同上 |
| `user_region` | String | R/W/D | 同上 |
| `user_signature` | String | R/W/D | 同上 |
| `user_gender` | String | R/W/D | 同上 |
| `api_key` | String | R/W | 同上（敏感） |
| `theme_mode` | String | R/W | `providers/settings_provider.dart` |
| `accent_color` | int | R/W | 同上 |
| `bubble_color_self_light` / `other_light` / `self_dark` / `other_dark` | int | R/W/D | 同上 |
| `bubble_text_self_light` / `other_light` / `self_dark` / `other_dark` | int | R/W/D | 同上 |
| `avatar_frame_style` | String | R/W | 同上 |
| `bubble_style` | String | R/W | 同上 |
| `ui_style` | String | R/W | 同上 |
| `bubble_font_self` / `bubble_font_other` | String | R/W/D | 同上 |
| `bubble_font_size` | double | R/W | 同上 |
| `splash_icon_path` | String | R/W/D | 同上 |
| `auto_check_update` | bool | R/W | 同上 |
| `update_proxy_url` | String | R/W | 同上 |
| `update_gitee_repo_url` | String | R/W | 同上 |
| `update_github_repo_url` | String | R/W | 同上 |
| `unread_notify` | bool | R/W | 同上 / `services/notification_service.dart` |
| `developer_mode` | bool | R/W | 同上 |
| `allow_sticker_send` | bool | R/W | 同上 |

---

## 八、创意工坊 / 备份 / 同步 / 其它

| Key | 类型 | 读写 | 文件 |
|-----|------|------|------|
| `workshop_repositories_v1` | String(JSON) | R/W | `providers/workshop_provider.dart` |
| `workshop_notify_enabled_v1` | bool | R/W | 同上 |
| `workshop_notify_repo_id_v1` | String | R/W/D | 同上 |
| `workshop_last_notify_hash_v2` | String(JSON) | R/W | 同上 |
| `workshop_last_notify_body_v1` | String（兼容） | R | 同上 |
| `backup_schedule_local_v1` | String(JSON) | R/W | `services/backup_schedule_service.dart` |
| `backup_schedule_cloud_v1` | String(JSON) | R/W | 同上 |
| `backup_schedule_last_local_v1` | String(ISO) | R/W | 同上 |
| `backup_schedule_last_cloud_v1` | String(ISO) | R/W | 同上 |
| `cloud_backup_secret_id` / `secret_key` / `bucket_url` / `prefix` | String | R/W/D | `services/cloud_backup_service.dart`（敏感） |
| `desktop_sync_pair_code` | String | R/W | `services/desktop_sync_server.dart` |
| `desktop_sync_port` | int | R/W | 同上 |
| `update_ignored_version_v1` | String | R/W | `services/update_service.dart` |
| `widget_data_token_*` / `widget_data_token_last_update` | int | W | `services/widget_sync_service.dart` |
| `widget_conversations` | String(JSON) | W | 同上 |
| `widget_conversations_last_update` | int | W | 同上 |

---

## 九、全量扫描类（不绑定固定 key）

| 用途 | 文件 | 行为 |
|------|------|------|
| 备份导出 | `services/backup_service.dart` | `getKeys()` 全量读，脱敏后写 zip |
| 备份恢复 | 同上 | `clear()` 后按备份回写 |
| 占用统计 | `services/storage_manager_service.dart` | `getKeys()` 分类统计字节 |
| 记忆点 | `providers/memory_point_provider.dart` | 按前缀 `memory_points_v1_*` 枚举 |

---

## 统计摘要

| 分类 | 固定 key 约 | 动态 key |
|------|-------------|----------|
| 首批迁移（角色+会话+消息） | 8 | — |
| 群聊 / 记忆点 / Token | 4 | `memory_points_v1_*` |
| 互动 / 表情 / 聊天设置 | ~20 | `chat_bg_image_*` `chat_bg_blur_*` |
| 用户 / 外观 / API | ~30 | — |
| 工坊 / 备份 / 桌面同步 | ~15 | — |
| **合计固定 key** | **约 80** | **3 类前缀** |

---

## 迁移范围建议（待确认）

**第一步首批只迁（你指定的三块）：**

1. **角色列表** → `characters` 表（含 deleted_ids、visibility_groups 可先留 prefs 或一并入库）
2. **会话列表** → `conversations` 表
3. **消息** → `messages` 表

**本阶段仍留 SharedPreferences：** 其余设置 / 备份 / 同步 / 群聊 / 记忆点等（等跑通后再分批）。

**推荐方案：** `drift`（类型安全 + 迁移版本管理比手写 sqflite DAO 省事）；消息/角色可按「结构化列 + `extra_json`」存放，避免一次性把所有字段都表化。

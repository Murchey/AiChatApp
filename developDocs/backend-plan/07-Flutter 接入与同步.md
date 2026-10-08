# 07 Flutter 接入与同步

## 1. 接入顺序

先添加独立的 `BackendClient`，再逐步给页面增加入口；不要把 HTTP 调用塞进现有页面或修改所有 Provider 的持久化逻辑。

建议新增：

```text
lib/models/backend_config.dart
lib/models/backend_capabilities.dart
lib/services/backend_http_client.dart
lib/services/device_auth_service.dart
lib/services/story_backend_service.dart
lib/services/sync_service.dart
lib/providers/backend_provider.dart
lib/providers/sync_provider.dart
```

`BackendProvider` 只负责服务器地址、连接状态、feature flags、设备状态和错误；`StoryProvider` 继续负责故事目录，使用策略对象选择静态或服务器实现。

## 2. HTTP 客户端规则

- 所有请求统一超时、取消、JSON 编码、requestId 和错误映射。
- URL 规范化一次：补协议、移除重复 slash、校验端口；不要每个页面拼 URL。
- 401 只自动刷新一次；刷新失败清除令牌并显示重新配置入口。
- 429 使用服务端 `retryAfterSeconds`，不做无上限重试。
- 所有列表使用 cursor，不能用“当前页 + 1”应对删除和新增。
- App 退出页面时取消未完成请求，避免 `setState after dispose`。
- 服务器响应字段缺失时保留旧缓存并提示，而不是把列表清空成“没有内容”。

## 3. 本地优先同步

现有 `ChatProvider`、`CharacterProvider`、`MemoryPointProvider` 继续以本地数据为准。同步采用 outbox：

```text
本地变更
  -> 写本地数据库
  -> 写 sync_outbox(domain, objectId, revision, payloadHash)
  -> 后台有网络时上传加密块
  -> 服务端返回 accepted/rejected/conflict
  -> 更新 manifest
```

- 本地写入不能等待网络。
- 同一对象多次修改可合并，只保留最新 revision 和必要的删除 tombstone。
- 服务端不接受客户端直接覆盖版本；使用 `baseRevision` 检测冲突。
- 冲突策略按域声明：设置使用 last-write-wins，角色/记忆使用字段级或用户选择，聊天消息使用 append-only + message ID 去重。
- 加密同步包的密钥从用户密码或设备密钥派生，服务端只保存密文和哈希。

## 4. 与现有本地数据的映射

| 现有 Provider | 首版处理 | 未来同步域 |
|---|---|---|
| `ChatProvider` | 继续本地 | `conversations`、`messages` |
| `GroupChatProvider` | 继续本地 | `groups`、`group_messages` |
| `CharacterProvider` | 继续本地 | `characters` |
| `MemoryPointProvider` | 继续本地 | `memories`、`story_installations` |
| `SettingsProvider` | 仅服务器配置本地保存 | `settings`（可选） |
| `StoryProvider` | 静态/服务端目录均可 | 已安装故事元数据 |
| `MomentNotificationProvider` | 不上传 | 未来单独开关 |

不要把 API Key、语音样本绝对路径和本地文件 URI 放入同步包。路径需要相对化，文件需要显式加密或由用户另行导出。

## 5. 服务器配置持久化

本地保存：`baseUrl`、`port`、`scheme`、`deviceId`、token 状态、feature flags 缓存和最后成功时间。长期令牌放系统安全存储；如果平台不可用，降级为短期令牌并提示风险。

配置变化后：

1. 取消旧请求。
2. 清除服务端列表缓存，不清除本地聊天/角色数据。
3. 重新获取 `/api/version` 和 `/api/health`。
4. 只刷新受影响页面一次。

## 6. 客户端兼容策略

- API `apiVersion` 不支持时停用网络功能，但保留本地功能。
- 新字段只读可选；旧服务缺少字段时使用安全默认值。
- 服务端错误显示人类可读文本，同时保留内部 code 供日志和测试。
- 网络超时默认 8–15 秒，上传/下载使用独立长请求上限和取消按钮。

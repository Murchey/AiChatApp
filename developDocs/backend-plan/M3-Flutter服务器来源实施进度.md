# M3 Flutter 服务器来源实施进度

## 状态

M3 客户端服务器来源接入已完成本轮实现，当前工作区保持未提交状态，等待项目负责人审阅。实现范围是可选的故事服务器连接，不改变本地聊天、角色、记忆、朋友圈或气泡数据。

## 已完成

- 新增 `BackendProvider`，管理服务器地址、端口、协议、设备 ID、连接状态、能力缓存和错误状态。
- 新增 `BackendHttpClient`：统一 HTTP/HTTPS URL 校验、UTF-8/BOM JSON、超时、可取消请求、请求 ID、结构化错误、401 单次刷新和 429 冷却。
- 新增 `BackendRequestScope`，页面退出、切换来源、刷新查询和详情下载均可以取消未完成请求。
- 设备邀请码兑换、访问令牌刷新、设备撤销和安全存储接入完成。长期令牌写入系统安全存储；安全存储不可用时只保留当前进程的访问令牌并显示提示。
- `ApiModel` 等现有模型和本地故事源保持兼容；服务器配置普通偏好只保存元数据，不保存 access/refresh token。
- `BackendCapabilities` 校验 API 版本、最低客户端版本和 `stories` feature flag；旧服务或关闭故事功能时保留本地/静态来源。
- `StoryBackendService` 支持 cursor 分页、关键词、标签、版本固定下载和幂等键。
- `StoryProvider` 支持服务器、COS/OSS、GitHub、Gitee 的来源级配置缓存；切换来源不会覆盖其他来源配置。目录和已下载故事包写入有界本地缓存，网络失败或坏响应时保留旧内容并显示错误。
- 故事线主页面保留已有缓存内容，显示缓存模式提示；来源设置已在二级设置页中提供连接测试、绑定设备、清除会话、撤销设备、重新配置和静态回退入口。
- 故事详情下载支持取消和重试；页面退出会取消探测、目录和详情请求，避免 late response 更新已销毁页面。
- `main.dart` 在 `StoryProvider` 前注册 `BackendProvider`，生产树使用 `ChangeNotifierProxyProvider` 注入。

## 本地持久化与兼容

| 内容 | 存储 | 说明 |
|---|---|---|
| 服务器配置 | `aichat_backend_config_v1` | 地址、端口、设备 ID、能力和最后成功时间；不含 token |
| 长期 token | 系统安全存储 key `aichat_backend_session_v1` | 仅显式安全序列化写入 |
| 故事来源 | `story_community_source_v1`、`story_community_sources_v1` | 兼容旧配置，按来源保留草稿 |
| 故事目录缓存 | `story_catalog_cache_v1_*` | 按来源配置哈希隔离，最多 500 条 |
| 故事包缓存 | `story_package_cache_v1_*` | 单包有大小上限，损坏缓存不会阻塞启动 |

旧版曾把 token 写入故事来源普通偏好时，启动迁移会尝试绑定到安全会话，并立即清理普通偏好中的 token。无法解析的旧地址不会阻塞 App 启动。

## 自动化验证

已通过：

```text
server_project/gradlew.bat test bootJar
flutter test --no-pub                         # 137 tests passed（本轮新增来源隔离与 token 回归）
flutter test test/services/backend_http_client_test.dart \
  test/providers/backend_provider_test.dart \
  test/providers/story_backend_provider_test.dart \
  test/providers/story_provider_test.dart \
  test/screens/story_community_screen_test.dart --no-pub
flutter analyze lib test integration_test --no-pub --no-fatal-infos
flutter test integration_test/m3_backend_test.dart -d emulator-5554 \
  --dart-define-from-file=server_project/build/m3-runtime/test-defines.json
```

Android 模拟器集成测试使用临时本地 Spring Boot JAR、真实 HTTP、SQLite、原生安全存储和 25 条故事夹具完成：设备绑定、刷新、重启恢复、cursor 分页、搜索/标签、故事下载、浅色/深色设置页均通过。临时令牌和夹具位于 `server_project/build/m3-runtime`，不应提交。

2026-10-08 复核使用当前工作区最新代码重新执行，测试通过后已停止临时服务并删除运行目录。

分析结果没有 error；当前工作区共有 32 条 info 级 lint（主要是旧文件的构造器 key、花括号和 const 建议），不影响构建和测试。

## 已知边界

- 本轮没有实现 M4 管理员草稿/审核 App 编辑器，也没有实现 M5 同步、评论和 LLM 中继。
- 当前只在 Windows 开发机和 Android 12 模拟器验证；Ubuntu、iOS、真实内网穿透和公网 HTTPS 仍需部署环境验收。
- token 刷新和服务器探测使用现有后端 v1 契约；如果部署端没有 `/api/version` 或 `stories` feature，会安全回退到静态/缓存来源。
- Android 模拟器截图通过 integration_test 的 screenshot 回调生成；截图是否导出到宿主机由 Flutter 测试运行器决定，未把截图作为源码资源写入仓库。

## 后续建议

1. 在一台 Ubuntu 或 Windows 内网穿透环境运行 `server_project` 的部署脚本，验证 HTTPS、端口和恢复备份。
2. 按 `10-测试与实施切片.md` 进入 M4 前，先由负责人确认 M3 API 契约和安全存储策略。
3. 修复或统一本轮新增文件的 info 级 lint 后，再执行一次不带 `--no-fatal-infos` 的分析检查。

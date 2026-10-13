# AiChat Backend

这是 AiChat 可选后端的 Spring Boot 3 / Java 21 / SQLite 实现。M0–M3基线已完成；当前增加管理员草稿发布、设备私有加密同步、四协议LLM中继和待审核评论。同步、中继、评论默认关闭；完整验收进度见 [实施进度](../developDocs/backend-plan/M4-M7-服务端实施进度.md)。

入门用户建议先看 [5 分钟快速开始](docs/快速开始.md)；完整部署步骤见 [部署指南](docs/部署指南.md)。新增模块配置与调用说明见 [模块部署指南](docs/optional-modules.md)，systemd/Caddy/Nginx 样例位于 `deploy/`。App管理员编辑器/评论UI尚未接入，不应把服务端接口测试理解为这些App功能已验收。

管理面板源码位于 `admin-panel/`，使用 React 和独立 CSS，支持故事表单编辑、草稿校验与发布、角色 ZIP 上传、邀请码和评论审核。登录先由服务端验证管理员令牌，令牌只保存在当前浏览器会话。服务定位是角色卡与故事线的内容社区：公开浏览下载，已认证设备可评论，管理员负责发布和审核；GitHub/COS 静态来源仍由 App 原有流程使用。

本次本地修复与接口说明见 [内容社区与本地验收](docs/内容社区与本地验收.md)。App 中的云角色卡目录和评论 UI 仍需后续接入，此处的验证覆盖服务端和浏览器管理台。

APP「故事线设置 → 自建服务器」现支持开放账户注册与登录，无需邀请码。服务端提供 `/api/auth/register`、`/api/auth/login`、`/api/auth/me`，以 `features.accountAuth` 声明能力（`AICHAT_FEATURE_ACCOUNT_AUTH` 默认开启）。旧设备认证保留在 APP 的「高级认证」中；服务器账号与本地昵称独立。构建 JAR 后可运行 `node scripts/account-smoke.cjs` 验证 Flutter 与本地后端的完整账号流程。

## 环境

- Java 21 LTS。
- Node.js 20.19+ 或 22.12+（构建管理面板）；运行已打包的 JAR 不需要 Node.js。
- 不要求全局 Gradle；使用仓库内 `gradlew`/`gradlew.bat`。
- Gradle Wrapper 默认从腾讯镜像下载 Gradle 发行版：`mirrors.cloud.tencent.com/gradle`。
- Gradle 依赖仓库优先使用腾讯 Maven 公共镜像。
- 项目同时提供等价的 `pom.xml`；如果使用 Maven 构建，必须传入 `config/maven-settings.xml`，其中所有 Maven 仓库请求通过腾讯公共镜像。

## 构建和测试

在 `server_project` 目录执行：

```powershell
.\scripts\build.ps1
```

Linux/macOS：

```bash
sh ./scripts/build.sh
```

输出 JAR：`build/libs/aichat-backend.jar`。

## 本地启动

最简单的方式：

```powershell
.\scripts\setup-local.ps1
.\scripts\start.ps1
```

Linux/macOS：

```bash
./scripts/start.sh
```

Windows 本地初始化脚本只在 `config/local.env` 不存在时生成随机管理令牌与 token pepper，并开启内容社区评论。该文件已排除出 Git。管理令牌可在文件中查看，勿提交或分享。启动脚本默认重建管理面板和 JAR，避免运行旧产物；已确认产物最新时可用 `-SkipBuild`（Linux 为 `SKIP_BUILD=1`）。脚本会创建数据目录，默认访问 `http://127.0.0.1:8080`，按 `Ctrl+C` 停止。

开发模式：

```powershell
$env:AICHAT_DATA_DIR = "$PWD\data"
$env:AICHAT_PORT = "8080"
New-Item -ItemType Directory -Force $env:AICHAT_DATA_DIR | Out-Null
.\gradlew.bat bootRun
```

或者：

```powershell
.\scripts\run.ps1
```

健康检查：

```text
GET http://127.0.0.1:8080/api/health
GET http://127.0.0.1:8080/api/version
```

M0 的默认 `AICHAT_REQUIRE_TOKEN_PEPPER=false` 只用于本地启动。部署前必须设置至少 32 字符的 `AICHAT_TOKEN_PEPPER`，并把 `AICHAT_REQUIRE_TOKEN_PEPPER=true`。

M1 认证配置还包括：

```text
AICHAT_BOOTSTRAP_ADMIN_TOKEN    首次生成邀请码和发布故事的管理令牌
AICHAT_ACCESS_TOKEN_MINUTES     access token 默认 15 分钟
AICHAT_REFRESH_TOKEN_DAYS       refresh token 默认 30 天
```

首次可以使用 bootstrap 管理令牌生成邀请码：

```powershell
.\scripts\generate-invite.ps1 -AdminToken $env:AICHAT_BOOTSTRAP_ADMIN_TOKEN
```

如果直接执行打包后的 JAR，也必须先创建 `AICHAT_DATA_DIR` 指向的目录；`run.ps1` 和 `run.sh` 会自动创建它。

## 腾讯镜像配置

Gradle 镜像配置位于 `settings.gradle` 和 `gradle/wrapper/gradle-wrapper.properties`。Maven 配置位于 `config/maven-settings.xml`：

```powershell
mvn -s config\maven-settings.xml test
```

Maven 作为等价构建选项，M0 的已验证构建入口是 Gradle Wrapper。若腾讯镜像暂时不可用，模型实现者应先记录错误和响应，再由项目负责人决定是否允许增加备用仓库；不要在每个模块中自行添加不同仓库。

## API 概览

```json
{
  "data": {
    "status": "UP",
    "service": "aichat-backend",
    "timestamp": "2026-10-08T00:00:00Z"
  },
  "requestId": "req_..."
}
```

`/api/version` 返回 `apiVersion`、`serverVersion`、`minClientVersion` 和 feature flags。

M1 设备认证：

```text
POST /api/invite/exchange
POST /api/auth/refresh
POST /api/auth/revoke
POST /api/admin/invites
POST /api/admin/devices/{deviceId}/revoke
```

M2 故事服务：

```text
GET  /api/stories?q=&tag=&cursor=&limit=20
GET  /api/stories/{storyId}
GET  /api/stories/{storyId}/versions/{version}
GET  /api/stories/{storyId}/download
POST /api/admin/stories/publish
```

`GET /api/stories` 保留顶层 `stories` 字段以兼容当前 Flutter 故事社区；下载接口直接返回故事包 JSON。故事发布前由服务端校验 schema、版本、章节和记忆点 ID。

## 目录

```text
config/                         镜像、示例配置、systemd
scripts/                        Windows/Linux 启动脚本
data/                           外部 SQLite 和故事数据目录
src/main/java/.../common        响应、错误、request ID
src/main/java/.../config        配置绑定和安全启动检查
src/main/java/.../system/web    health/version Controller
src/main/resources/db/migration Flyway V1/V2 迁移
src/test                        M0-M2 HTTP、认证和故事测试
```

## 下一步

按照 `developDocs/backend-plan/10-测试与实施切片.md` 进入 M3 Flutter 服务器来源接入。M1/M2 的详细进度见：

- `developDocs/backend-plan/M1-设备认证实施进度.md`
- `developDocs/backend-plan/M2-故事只读服务实施进度.md`

评论、聊天同步和 LLM 中继仍未启用。

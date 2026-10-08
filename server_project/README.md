# AiChat Backend M2

这是 AiChat 可选后端的 Spring Boot 3 / Java 21 / SQLite 实现。当前包含 M0 启动基线、M1 设备认证和 M2 故事只读服务；聊天同步、LLM 中继和评论仍保持可选关闭。

## 环境

- Java 21 LTS。
- 不要求全局 Gradle；使用仓库内 `gradlew`/`gradlew.bat`。
- Gradle Wrapper 默认从腾讯镜像下载 Gradle 发行版：`mirrors.cloud.tencent.com/gradle`。
- Gradle 依赖仓库优先使用腾讯 Maven 公共镜像。
- 项目同时提供等价的 `pom.xml`；如果使用 Maven 构建，必须传入 `config/maven-settings.xml`，其中所有 Maven 仓库请求通过腾讯公共镜像。

## 构建和测试

在 `server_project` 目录执行：

```powershell
.\gradlew.bat test
.\gradlew.bat bootJar
```

Linux/macOS：

```bash
./gradlew test
./gradlew bootJar
```

输出 JAR：`build/libs/aichat-backend.jar`。

## 本地启动

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

# 可选模块部署与运维

## 构建与开关

Java21。Windows在server_project执行 `./gradlew.bat test bootJar`，Ubuntu执行 `./gradlew test bootJar`；既有run.ps1/run.sh启动入口继续使用。Gradle与Maven均包含JSON Schema校验器，Maven构建仍需指定config/maven-settings.xml。

默认sync/comments/llm-relay关闭，stories/admin-publish保持原有默认。按需配置环境变量：

```text
AICHAT_FEATURE_SYNC=true
AICHAT_FEATURE_COMMENTS=true
AICHAT_FEATURE_LLM_RELAY=true
AICHAT_REQUIRE_TOKEN_PEPPER=true
AICHAT_TOKEN_PEPPER=<至少32字符随机密钥>
AICHAT_BOOTSTRAP_ADMIN_TOKEN=<独立随机管理密钥>
```

不要把真实密钥写入仓库或服务日志。反向代理必须限制请求体（建议4MB）、连接数和请求速率；LLM SSE禁用代理buffering。仅通过可信反向代理接入转发头，公网部署启用HTTPS，不能直接开放信任转发头的8080端口。

SQLite使用单连接串行事务。每个数据目录只运行一个服务实例；不要同时让第二个JAR或外部脚本写同一个库。不属于多节点高并发部署方案。

## 管理员故事发布

bootstrap令牌仅用于首次生成管理邀请码，随后使用ADMIN设备令牌。生成邀请码时请求 `/api/admin/invites`，body带 `role: ADMIN`；省略则USER。角色由服务端邀请码决定。

草稿创建 → 更新revision → validate → submit → publish（Idempotency-Key）→ archive。publish需要revision和baseVersion，发布版本必须为baseVersion+1。发生VERSION_CONFLICT重新读取草稿合并，不能盲重试覆盖。不可变旧发布版本保留。

精确DTO与路由见 [接口补充](../../developDocs/backend-plan/11-M4-M7接口补充.md)。App未来编辑器只调用API，不能直接写SQLite。

已有deviceId不能重新兑换邀请码覆盖身份，返回DEVICE_ID_EXISTS。令牌失效后需要重新生成设备ID并使用新邀请码；原设备可由管理员撤销。相同ID不得用于把普通邀请码兑换成既有管理员会话。

## 设备私有加密同步试点

服务端开启sync后，设备仍需显式PUT `/api/sync/scopes/settings` 开启域。App入口：故事线设置 → 自建服务器 → 设置同步（试点）。只同步主题模式与底部导航样式。

对象AES256GCM，密钥在本机安全存储；服务端不接收密钥和明文。基于baseRevision检查冲突，上传必须带稳定Idempotency-Key；ACK丢失重放原请求。409由用户明确选择恢复远端或保留本机。

默认请求是设备私有命名空间。需要多设备时，设备A调用 `POST /api/sync/spaces`，将返回的一次性加入码通过安全渠道交给设备B；设备B调用 `POST /api/sync/spaces/join`，随后同步请求带 `X-Sync-Space`。只有OWNER能生成新的加入码，服务端只保存加入码哈希。空间成员共享的是加密对象和revision，服务端不接收密钥或明文。

这只解决服务端空间授权；App的同步设置页提供密码保护的密钥导出/导入（PBKDF2 + AES-GCM），用户必须通过安全渠道把加密包和密码带到第二设备，不能让服务器代管。删除本机安全密钥且没有导出包不能解密旧对象。聊天/角色/记忆仍未自动同步，旧的无header请求继续使用设备私有空间。

## LLM中继

按 `config/llm.example.yml` 配置目录，启动时加载该文件，例如：

```text
java -jar build/libs/aichat-backend.jar --spring.config.additional-location=file:config/llm.example.yml
```

只接受部署者目录中的modelId，客户端不能指定任意上游URL。API `/api/models` 返回能力但不返回上游endpoint。POST `/api/llm/completions` 需要设备Bearer，用户提供的X-Provider-Key只在本次内存请求中转发，不落库。

公网要求HTTPS。`app.llm.allow-local-http=true`仅用于loopback测试，不用于公网关闭TLS校验。上游不跟随重定向。期限1–120秒，默认45；16全局并发、30次/设备/分钟。SSE返回start/delta/tool_call_start/tool_call_delta/tool_call_end/usage以及唯一done或error，heartbeat为注释。

JSON Schema只接受2020-12文档内引用；输出与工具参数必须符合Schema。上游429不会自动重试，避免重复生成/计费。工具调用结果仅是数据，不执行本机函数或脚本。

## 评论

comments关闭时接口返回403 FEATURE_DISABLED，故事下载仍可用。启用后公开列表只展示已审核可见评论和有公开资格的删除占位；写入需要设备令牌。

新评论与二级回复均为PENDING。管理员按cursor审核列表，设VISIBLE/HIDDEN/DELETED。隐藏父评论同时隐藏其回复；未审核或隐藏评论删除不变公开。举报仅原因代码，无附件；列表不返回作者设备ID。管理员举报列表采用items/hasMore/nextCursor。

## 迁移、备份与回退

升级前停止服务，完整备份数据目录、配置与JAR；SQLite停止后复制主文件及任何wal/shm文件。保留token pepper才能让原哈希令牌继续验证。绝不编辑已执行Flyway文件。

升级运行会自动执行V3–V7。V7对历史DELETED评论保守设不公开；管理员可明确审核恢复。降级不要直接用旧JAR打开已升级库，恢复对应旧备份与旧JAR后启动。

测试覆盖空库、V2升级、文件库关闭/重开、幂等并发。Ubuntu与公网隧道实际运行仍需部署者验收；Windows本地测试不能代替Ubuntu/公网/Android真机。

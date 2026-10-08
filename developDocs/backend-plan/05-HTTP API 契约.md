# 05 HTTP API 契约

## 1. 通用规则

- Base path：`/api`。
- JSON 编码 UTF-8，响应 `Content-Type: application/json`。
- 时间使用 UTC；所有日期字段带 `Z`。
- 成功响应统一使用 `data`，列表使用 `items`、`nextCursor`、`hasMore`。
- 失败响应统一使用 `error.code`、`error.message`、`error.details`、`error.requestId`。
- 未知字段不能改变旧字段语义；新增字段必须可选。
- 生产环境所有非健康接口必须 HTTPS。

成功示例：

```json
{
  "data": {
    "items": [],
    "nextCursor": null,
    "hasMore": false
  },
  "requestId": "req_01J..."
}
```

错误示例：

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "请求参数无效",
    "details": [{"field": "path", "reason": "must not be blank"}],
    "requestId": "req_01J..."
  }
}
```

## 2. 基础与设备接口

| 方法 | 路径 | 认证 | 说明 |
|---|---|---|---|
| GET | `/api/health` | 否 | 存活检查，不暴露密钥或数据库细节 |
| GET | `/api/version` | 否 | 服务版本、schema、feature flags |
| POST | `/api/invite/exchange` | 否 | 邀请码兑换设备令牌 |
| POST | `/api/auth/refresh` | refresh | 轮换 access token |
| POST | `/api/auth/revoke` | access | 撤销当前设备 |
| GET | `/api/devices` | admin | 查看设备摘要 |
| DELETE | `/api/devices/{deviceId}` | admin | 撤销设备 |

`/api/version` 示例：

```json
{
  "data": {
    "serverVersion": "1.0.0",
    "apiVersion": "v1",
    "minClientVersion": "1.6.0",
    "features": {"stories": true, "sync": false, "comments": false, "adminPublish": true}
  }
}
```

## 3. 故事接口

| 方法 | 路径 | 认证 | 说明 |
|---|---|---|---|
| GET | `/api/stories` | 否/设备 | 分页、搜索、标签、排序 |
| GET | `/api/stories/{storyId}` | 否/设备 | 当前已发布详情 |
| GET | `/api/stories/{storyId}/versions/{version}` | 否/设备 | 指定版本 |
| GET | `/api/stories/{storyId}/download` | 否/设备 | 返回完整故事 JSON 并记录被动下载 |
| POST | `/api/stories/{storyId}/download-events` | 设备 | 可选幂等下载事件 |

查询参数：`q`、`tag`、`cursor`、`limit`。`limit` 服务端强制限制在 1–50。搜索必须服务端参数化查询，不能把用户输入拼进 SQL。

`StoryCatalogEntry` 与现有静态 `index.json` 字段兼容：`storyId`、`version`、`title`、`author`、`summary`、`tags`、`file`；服务端可额外返回 `downloadCount`，静态源不显示统计。

下载接口不要返回文件系统绝对路径；返回 JSON、签名下载 URL 或流。客户端收到详情后仍按现有 `StoryPackage` 校验，再绑定角色和安装记忆。

## 4. 同步接口（V1 可关闭）

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/sync/manifest` | 获取每个数据域的版本、哈希和服务器时间 |
| PUT | `/api/sync/objects/{domain}` | 上传客户端加密块 |
| GET | `/api/sync/objects/{domain}` | 下载最新加密块 |
| POST | `/api/sync/resolve` | 提交冲突解决结果 |

`domain` 只能是白名单，例如 `characters`、`conversations`、`messages`、`memories`、`settings`。服务端只看哈希、版本和大小，不能按 JSON 内部字段做业务判断。

## 5. 管理员故事接口

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/admin/invites` | 生成邀请码 |
| POST | `/api/admin/stories` | 创建草稿 |
| PUT | `/api/admin/stories/{id}/draft` | 更新草稿 |
| POST | `/api/admin/stories/{id}/validate` | 校验 JSON 并返回字段错误 |
| POST | `/api/admin/stories/{id}/submit` | 提交审核 |
| POST | `/api/admin/stories/{id}/publish` | 发布不可变版本 |
| POST | `/api/admin/stories/{id}/archive` | 归档故事 |
| GET | `/api/admin/audit-logs` | 查询审计摘要 |

发布请求必须携带 `baseVersion` 和 `Idempotency-Key`。如果期间已有新版本，返回 `VERSION_CONFLICT`，管理员必须重新加载后合并，不能静默覆盖。

## 6. 评论接口（V2 feature flag）

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/stories/{id}/comments` | 只返回可见评论，游标分页 |
| POST | `/api/stories/{id}/comments` | 创建待审核评论 |
| POST | `/api/comments/{id}/replies` | 创建二级回复 |
| DELETE | `/api/comments/{id}` | 软删除自己的评论或管理员删除 |
| POST | `/api/comments/{id}/reports` | 举报 |
| POST | `/api/admin/comments/{id}/moderate` | 审核/隐藏/恢复 |

评论正文不接受 HTML；接口层限制单条长度和嵌套深度。V1 关闭时客户端不显示评论入口。

## 7. 客户端错误映射

| HTTP | code | App 行为 |
|---:|---|---|
| 400 | `VALIDATION_ERROR` | 显示字段级提示，不重试 |
| 401 | `TOKEN_EXPIRED` | 静默刷新一次，失败后要求重新配置 |
| 403 | `FORBIDDEN`/`FEATURE_DISABLED` | 显示权限或功能未开启 |
| 404 | `NOT_FOUND` | 显示资源不存在，不把它当模块关闭 |
| 409 | `VERSION_CONFLICT` | 重新拉取并提示合并 |
| 413 | `PAYLOAD_TOO_LARGE` | 提示压缩或减少内容 |
| 429 | `RATE_LIMITED` | 按 `retryAfterSeconds` 延迟，不立即循环 |
| 5xx | `SERVER_ERROR` | 有上限的指数退避 |
| 网络超时 | 无 HTTP | 取消请求并保留本地状态 |


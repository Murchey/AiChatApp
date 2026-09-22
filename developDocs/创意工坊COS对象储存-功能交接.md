# 创意工坊 COS 对象储存 — 功能交接说明

> **用途**：本文件描述已在本工作区实现的「创意工坊 COS 类对象储存」能力，供迁移到正确仓库/工作区时对照移植。
>
> **状态**：实现完成，`flutter analyze` 相关文件无 issue。
>
> **相关提交范围**（本工作区未提交的改动 + 已有 UI 修复上下文）：
> - 核心：`lib/services/workshop_service.dart`、`lib/models/workshop_repository.dart`、`lib/providers/workshop_provider.dart`、`lib/screens/workshop_repos_screen.dart`
> - 通知展示：`lib/app.dart`
> - 依赖：`pubspec.yaml` / `pubspec.lock`（新增 `xml`）
> - 文档：`README.md`、`README_FILES/README_EN.md`

---

## 1. 需求摘要

在原有 **GitHub / Gitee Release 仓库** 之外，新增第二类来源：**COS 类对象储存**（腾讯云 COS、阿里云 OSS、AWS S3、MinIO 等兼容 ListObjects 的服务）。

用户填写 **BASE_URL**，App 按固定目录约定自动发现资产。

### 目录约定

```text
{BASE_URL}/
├── Characters/*.zip   # 角色分类（角色包，内含 Profile.json 等）
├── Games/*.zip        # 游戏分类（朋友圈数据包，内含 moments.json 等）
├── Stickers/*.zip     # 表情包分类（打包标准同 Git V1.3.0）
└── Note/*.md          # 更新通知（Markdown，弹窗完整展示）
```

| 目录 | 资产 | App 映射 tag（复用现有体系） |
| ---- | ---- | --------------------------- |
| `Characters/` | `.zip` | `kCharacterPackTag`（V1.1.0） |
| `Games/` | `.zip` | `kGamePackTag`（V1.0.0） |
| `Stickers/` | `.zip` | `kStickerPackTag`（V1.3.0） |
| `Note/` | `.md` | `kUpdateNotifyTag`（V1.2.0） |

**Note 优先级**：`update.md` → `note.md` → `readme.md` → 目录中最后一个 `.md`。

**权限要求**：桶需允许匿名 `ListObjects` + `GetObject`。

**列举方式**：S3 ListObjects V2

```http
GET {桶根}/?list-type=2&prefix={BASE路径}/&max-keys=1000
```

解析 XML 中的 `<Contents><Key>`、`<Size>`。

---

## 2. 架构决策

1. **不新建第三套资产模型**  
   COS 目录探测结果映射到现有 `WorkshopAsset.tag`（V1.1.0 / V1.0.0 / V1.3.0 / V1.2.0）。  
   → 下载、导入角色/朋友圈/表情包 UI **零改动**。

2. **仓库增加 `type` 字段**  
   `WorkshopRepoType.git` | `WorkshopRepoType.cos`。  
   旧 JSON 无 `type` 时默认 `git`（向后兼容）。

3. **类型识别**  
   - 完整 `http(s)` URL 且 host **不是** github / gitee → COS  
   - `owner/repo` 或 GitHub/Gitee URL → Git  
   - 添加流程：**先 ActionSheet 询问类型**，再打开填写弹窗（弹窗内仍可切换）

4. **COS 不使用下载代理**（`proxyFor` 对 COS 恒返回 `''`）。

5. **更新通知**  
   - Git：读 V1.2.0 Release body  
   - COS：读 `Note/*.md` 全文  
   - 弹窗高度改为约 `55%` 屏高可滚动，**完整展示** Markdown（`lib/app.dart`）

6. **依赖**：新增 `xml: ^6.5.0`（解析 ListObjects XML）。

---

## 3. 文件改动清单（移植时逐文件对照）

### 3.1 `lib/models/workshop_repository.dart`

- 新增枚举：

```dart
enum WorkshopRepoType { git, cos }
```

- `WorkshopRepository` 增加 `type`（默认 `git`）
- `toJson` / `fromJson` / `copyWith` 支持 `type`
- 便捷：`isGit` / `isCos`
- `hasCharacter` / `hasGame` / `hasSticker` / `hasUpdateNotify` 逻辑不变（仍看 `availableTags`）

### 3.2 `lib/services/workshop_service.dart`

新增常量与方法（均在 `WorkshopService` 上）：

| 成员 | 说明 |
| ---- | ---- |
| `kCosCharactersFolder` | `'Characters'` |
| `kCosGamesFolder` | `'Games'` |
| `kCosStickersFolder` | `'Stickers'` |
| `kCosNoteFolder` | `'Note'` |
| `looksLikeCosUrl(String)` | 是否对象储存 URL |
| `parseCosBaseUrl(String)` | → `(bucketRoot: Uri, prefix: String)`，列表打在桶根 |
| `cosDisplayName(String)` | 显示名：`host/末级路径` |
| `listCosObjects(String)` | ListObjects V2，返回 `List<({String key, int size})>` |
| `checkCosFolders(String)` | 探测四类，返回可用 tag 列表 |
| `listCosAssets(String, String tag)` | 某分类下 zip → `WorkshopAsset`（`downloadUrl` = BASE + 编码后的相对 Key） |
| `fetchCosNote(String)` | 拉取并返回 Note Markdown 全文 |
| `detectRepoType(String)` | → `WorkshopRepoType` |

原 Git 路径：`parseRepoPath` / `checkTags` / `listAssets` / `fetchReleaseBody` / `downloadZip` **保留不动**。

**注意**：`import 'package:xml/xml.dart';` 与 `import '../models/workshop_repository.dart';`（`WorkshopRepoType`）。

### 3.3 `lib/providers/workshop_provider.dart`

- `addRepository({path, proxyUrl, type})`：按 type / 自动探测分流  
- `updateRepository` / `refreshRepository`：同上，`type: repo.type.name`  
- `loadAssets`：`repo.isCos` → `listCosAssets`，否则 Git `listAssets`  
- `proxyFor`：COS 返回 `''`  
- `checkForUpdates`：COS → `fetchCosNote`，Git → `fetchReleaseBody(V1.2.0)`  
- 空分类错误文案区分 Git / COS  

### 3.4 `lib/screens/workshop_repos_screen.dart`

- **添加流程**：点 `+` → `CupertinoActionSheet`  
  - 「对象储存服务（COS / OSS / S3）」  
  - 「Git 仓库（GitHub / Gitee）」  
  → 再打开 `_AddRepoDialog(title: …, initialType: …)`  
- 弹窗：「来源类型」分段控件（Git / 对象储存）；COS 显示目录约定说明框；Git 才显示代理  
- 提交校验：COS 必须 `https://`；类型与 URL 不匹配时提示  
- 列表行：显示 `COS 对象储存` / `Git Release`；标签 chip 文案区分  
- 编辑时传入 `initialType: repo.type.name`  

### 3.5 `lib/app.dart`

- 更新通知弹窗：`maxHeight: 200` → `MediaQuery.sizeOf(ctx).height * 0.55`，完整滚动展示 MD。

### 3.6 `pubspec.yaml`

```yaml
dependencies:
  xml: ^6.5.0
```

### 3.7 README

- `README.md`：功能特性 +「创意工坊」章节增加 COS 目录表与说明  
- `README_FILES/README_EN.md`：同步英文  

---

## 4. 添加 / 编辑交互（验收点）

1. 创意工坊设置 → 右上角 **+**  
2. 弹出「添加来源」：先选 **对象储存** 或 **Git 仓库**  
3. 对象储存：填 `https://bucket.cos.ap-xxx.myqcloud.com/aichat`，可见目录约定提示  
4. 保存后自动 ListObjects，成功提示列出 Characters / Games / Stickers / Note  
5. 返回创意工坊，分类筛选可下载对应 zip（导入逻辑与 Git 资产一致）  
6. 若将该 COS 仓库设为通知源，启动时拉取 `Note/*.md`，内容变化时完整弹窗  

---

## 5. 移植步骤建议

1. 在**正确工作区**确认基线功能与本工作区一致（至少 `workshop_*`、`WorkshopService`）。  
2. 按第 3 节逐文件对照合并（优先 `git diff` 本工作区相关文件，或直接拷贝后 `flutter analyze`）。  
3. `flutter pub get`（拉 `xml`）。  
4. `flutter analyze lib/services/workshop_service.dart lib/providers/workshop_provider.dart lib/models/workshop_repository.dart lib/screens/workshop_repos_screen.dart lib/app.dart`。  
5. 真机验证：Git 添加仍可用；COS 添加 + 列表 + 下载导入 + Note 通知。  
6. 若目标仓库已有部分改动，以 **tag 映射 + 不新建资产模型** 为原则做合并，避免两套分类枚举。  

---

## 6. 已知限制 / 后续可做

| 项 | 说明 |
| -- | ---- |
| 列表上限 | `max-keys=1000`，未做分页 Continue 游标 |
| 鉴权 | 仅匿名 List/Get；不支持临时密钥 / 签名 URL |
| 路径风格 | 假定虚拟主机或路径前缀写在 BASE_URL path 中；列表固定打在 `scheme://host/` |
| 转义 | Key 中特殊字符按 path segment `Uri.encodeComponent` |
| 表情包分类 | COS 已支持 `Stickers/`；打包标准与 Git V1.3.0 相同 |

---

## 7. 同工作区其它已做但可独立丢弃的改动（勿与 COS 混淆）

若目标工作区**只需要 COS**，可不要一并带上的内容：

- 朋友圈长图缩略修复（`moment_card.dart`：长图分支 + `_coverDecodeSize` 等比解码）  
- 输入栏几何 / 经典圆形发送按钮（`message_input.dart`、`chat_send_button.dart`、群聊输入栏）  
- 会话/通讯录行高与个人页副标题精简（`home_screen.dart`、`profile_screen.dart`）  
- `lib/config/motion.dart` 动效 token  

以上与创意工坊 COS **无代码依赖**，可按需取舍。

---

## 8. 快速自测清单

- [ ] 添加 Git：`owner/repo` 仍检测 Release tag  
- [ ] 添加 COS：ActionSheet → BASE_URL → 列表成功  
- [ ] COS 下仅 `Characters/*.zip` 时只出现角色分类  
- [ ] COS 下 `Stickers/*.zip` 出现表情包并可导入  
- [ ] `Note/update.md` 变更后启动弹完整 MD  
- [ ] 编辑 COS/Git 仓库类型与代理行为正确  
- [ ] 旧数据（无 `type` 字段）仍按 Git 打开  

# AiChat

一款**角色扮演类微信聊天风格**的 Flutter Android 应用：内置多个角色，可与角色进行一对一的沉浸式聊天（支持发送图片、合并转发、角色包导入导出、自动更新等）。

> 纯 Cupertino（iOS 风格）UI，仅适配 Android。

---

## 目录

- [功能特性](#功能特性)
- [项目结构](#项目结构)
- [如何添加角色（以 CharactersImport 为例）](#如何添加角色以-charactersimport-为例)
- [修改应用版本号（V1.0.0）](#修改应用版本号v100)
- [本地打包 APK](#本地打包-apk)
- [自动更新机制](#自动更新机制)
- [API 设置与压缩会话](#api-设置与压缩会话)
- [技术栈](#技术栈)

---

## 功能特性

- **沉浸式角色聊天**：内置多个角色（人设、说话风格、核心记忆），支持自定义人设与用户关系
- **合并转发**：多选消息合并转发为卡片，独立展示并显示我方头像
- **图片消息**：通过「API 设置」中添加的模型发送图片（需模型支持视觉）
- **角色包导入/导出**：`.zip` 角色包一键导入、导出，支持批量勾选
- **上下文管理**：设置携带上下文条数（1 ~ 999 条，或「无限制」），可精确输入
- **会话自动压缩**：上下文无限制时自动开启压缩，达到所选模型上下文阈值（可调）时自动把更早的历史消息压缩为摘要
- **自动更新**：启动时自动检测 GitHub Release 新版本，支持加速代理源，一键下载并安装 APK
- **明暗模式**：跟随系统 / 浅色 / 深色，可自定义主题色

---

## 项目结构

```
lib/
├── main.dart                      # 入口
├── app.dart                       # 应用根组件（Provider 注入、主题）
├── config/
│   ├── routes.dart                # 路由表
│   └── theme.dart                 # 主题色板与扩展
├── models/                        # 数据模型（Character/Message/Conversation 等）
├── providers/                     # 状态管理（Auth/Api/Chat/Character/Settings）
├── screens/                       # 页面（聊天、通讯录、我、设置、API 设置等）
├── services/
│   ├── llm_service.dart           # LLM 调用（生成回复 / 压缩摘要）
│   ├── update_service.dart        # GitHub 更新检测、APK 下载与安装
│   ├── prompt_builder.dart        # System Prompt 与输出指令组装
│   └── character_pack_service.dart# 角色包 zip 解析与导出
├── utils/                         # 文件选择、角色包拾取等
└── widgets/                       # 气泡、时间标签、更新弹窗等
```

---

## 如何添加角色（以 CharactersImport 为例）

角色包是一个 `.zip` 文件，App 内通过 **【我】→ 导入角色包** 导入。一个 zip 中可以包含多个角色，每个角色是一个独立的文件夹。

项目根目录的 `CharactersImport\Sample1` 就是一份可直接打包成 zip 的示例：

```
CharactersImport/
└── Sample1/
    └── 爱弥斯/                  # 角色文件夹（文件夹名即角色名，可任意命名）
        ├── Profile.json         # 角色资料（必填）
        ├── Prompt.txt           # 角色提示词 / 人设（强烈建议提供）
        └── ProfilePicture.jpg   # 角色头像（可选）
```

### 步骤

1. 在 `Sample1` 下新建一个文件夹，文件夹名即角色显示名（如 `爱弥斯`）；
2. 在文件夹内新建 `Profile.json`，填入角色资料；
3. （可选）新建 `Prompt.txt` 写入角色人设提示词；
4. （可选）放入头像图片 `ProfilePicture.jpg`（支持 jpg / jpeg / png / webp / gif / bmp，取第一个）；
5. 将整个 `Sample1` 文件夹压缩为 zip；
6. 在 App 中进入 **【我】→ 导入角色包**，选择该 zip 并勾选要导入的角色。

### Profile.json 字段说明

| 字段 | 说明 | 是否必填 |
| ---- | ---- | ---- |
| `name` | 角色名称（缺省时使用文件夹名） | 建议 |
| `location` | 所在地（映射到「地区」） | 可选 |
| `gender` | 性别 | 可选 |
| `signature` | 个性签名 | 可选 |
| `remark` | 备注 | 可选 |
| `description` | 角色简介 | 可选 |
| `personality` | 性格特征 | 可选 |
| `greeting` | 开场白 | 可选 |
| `system_prompt` | 角色提示词（存在时优先于 `Prompt.txt`） | 可选 |
| `custom_persona` | 自定义人设 | 可选 |
| `user_relationship` | 与用户的关系 | 可选 |
| `tags` | 标签数组，如 `["鸣潮","电子幽灵"]` | 可选 |
| `avatar` | 内嵌头像（base64 字符串，存在时优先于图片文件） | 可选 |

`Sample1\爱弥斯\Profile.json` 示例：

```json
{
    "name": "爱弥斯",
    "location": "拉海洛·星炬学院",
    "gender": "女",
    "signature": "关注飞行雪绒喵~"
}
```

### Prompt.txt 说明

`Prompt.txt` 的内容就是角色的 `systemPrompt`，App 在每次对话前会把它与用户资料、时间、输出格式指令一起组装成 System Prompt。

参考 `Sample1\爱弥斯\Prompt.txt`：建议写清楚角色**基础身份**、**性格特征**、**说话风格**、**核心记忆与执念**、**注意事项**，让角色行为稳定、性格鲜明。

### 注意事项

- 文本文件建议使用 **UTF-8** 编码；程序对 GBK 乱码有兼容处理，但建议统一 UTF-8；
- zip 中**必须**包含至少一个带 `Profile.json` 的角色文件夹，否则会被过滤；
- 文件层级不要过深：`Sample1\角色A\Profile.json` 即可，不要把文件直接放在 zip 根目录。

---

## 修改应用版本号（V1.0.0）

> 约定：版本号完全由**开发者自行设置**，没有固定递增规则。在 `pubspec.yaml` 中自由填一个版本号即可，GitHub Release 的 `tag` 与它保持一致。

版本号定义在项目根目录的 `pubspec.yaml`：

```yaml
version: 1.0.0
```

- 开发者自由填写版本号（如 `1.0.0`、`1.1.0`），App 内「软件版本」显示为 `V1.0.0`；
- 不需要 `1.0.0+1` 这种带 build 号的写法，一个数字即可。

发布流程：

1. 开发者在 `pubspec.yaml` 中填写想要的版本号，例如 `1.0.0` → `1.1.0`；
2. 执行 `build_apk.bat release` 打包；
3. 在 GitHub 仓库新建 Release，`tag` 填与 pubspec 相同的版本号（如 `1.1.0`，可带可不带 `v` 前缀；必须比本地版本新，更新检测据此提示升级），并上传 APK 资产。

> 说明：App 内「软件版本」通过 `package_info_plus` 读取，`flutter build apk` 会把 pubspec 中的版本写入 APK，无需手动改 AndroidManifest。

---

## 本地打包 APK

项目根目录已提供一键打包脚本 **`build_apk.bat`**（需已安装 Flutter 并配置 PATH）：

```bat
:: 打包 debug 包
build_apk.bat

:: 打包 release 包
build_apk.bat release
```

脚本会自动执行 `flutter pub get` → `flutter build apk --debug|--release`，并将 APK 复制到 `dist\` 目录，文件名带版本号：

```text
dist\ai_chat_v1.0.0+1_debug.apk
```

也可以手动执行：

```bash
flutter pub get
flutter build apk --release
# 产物位于 build\app\outputs\flutter-apk\app-release.apk
```

---

## 自动更新机制

- 版本检查：通过 GitHub API `https://api.github.com/repos/Murchey/AiChatApp/releases/latest` 获取最新 Release，对比 `tag_name` 与本地版本号；
- 下载：优先使用 Release 附带的 APK 资产直链，无资产时按 GitHub 下载地址规则拼接；可通过**更新代理地址**（内置 3 个加速源或自定义）加速；
- 安装：下载到应用外部目录 `updates/`，通过原生 FileProvider + 系统安装器安装（需授权「安装未知应用」）；
- 入口：
  - **【我】→ 软件版本**：手动检查更新；
  - **【我】→ 设置 → 启动时自动检测更新**：开启后每次启动自动检测；
  - **【我】→ 设置 → 更新代理地址**：选择/自定义加速代理。

发布新版本流程：在 GitHub 仓库新建 Release，`tag` 填与 `pubspec.yaml` 相同的版本号（可带 `v` 前缀，需比本地版本新），并上传 APK 资产即可。

---

## API 设置与压缩会话

### API 设置（【我】→ API 设置）

- 添加模型：支持任意 OpenAI 兼容接口，填「展示名称 / 模型名称 / 接口地址 / API Key / 上下文长度(token)」；
- 支持「一键填入 DeepSeek 官方配置」；
- 为每个模型配置**上下文长度**，作为会话压缩 70% 阈值的基准；
- **压缩会话使用的模型**：单独指定用于压缩的模型（默认跟随聊天模型）。

### 会话压缩（【我】→ 聊天设置 → 压缩会话）

- 上下文条数滑到【无限制】时自动开启「自动压缩历史消息」；
- 聊天设置页顶部实时显示**当前会话的上下文使用情况**：已用 / 总 token、占用百分比、进度条与压缩阈值刻度线，达到阈值时提示"下次发送将自动压缩"；
- 压缩阈值可手动调整（30% ~ 90%，默认 70%）：当会话历史估算 token 达到所选模型上下文长度的阈值时，自动把更早的历史消息（保留最近 20 条）压缩为一段摘要，并替换进会话记录，避免上下文超长；
- 压缩请求使用「压缩会话使用的模型」完成。

---

## 技术栈

- **Flutter / Dart**：纯 Cupertino 风格，Provider 状态管理
- **数据持久化**：SharedPreferences（设置与数据）
- **依赖**：`http`（LLM 与更新请求）、`archive` + `gbk_codec`（角色包 zip 解析）、`image_picker`（图片发送）、`package_info_plus`（版本号）、`uuid`、`intl`、`lpinyin` 等

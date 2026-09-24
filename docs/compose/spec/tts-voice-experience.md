---
feature: tts-voice-experience
status: delivered
updated: 2026-09-24
branch: main
commits: 21543b0..21543b0
---

# 语音播放与声音工作台

## Report

**What was built** — 实现了全局播放状态机 `TtsPlaybackController`，支持同消息逐次排队（点击三次播三次）、FIFO 顺序播放、按消息取消和整轮连续播。气泡播放控件按 idle/synthesizing/playing/queued/error 五态显示图标、颜色和排队角标。`Conversation.continuousRead` 开关控制短信模式整轮连续播，一轮边界按用户消息切分。MiMo voicedesign/voiceclone 请求已按官方协议组装，克隆样本持久化到应用文档目录。【我】页新增声音工作台入口，支持音色设计试听、克隆试听和保存到角色。

**Verification** — `flutter analyze` 通过（0 issues）；`flutter test` 50 项全部通过；`git diff --check` 通过（仅 LF/CRLF 提示）。

**Journey log** — 1) `TtsService.speak` 拆为 `synthesize` 返回字节，播放上收到控制器，消除了强制 stop 导致的堆叠播放。2) 审查发现自动朗读在 continuousRead 关闭时误播全历史，已修正为只播最新一条。3) 「一轮」边界最初取到会话末尾，已改为按用户消息切分。4) 克隆样本最初写入 systemTemp，已改为 `getApplicationDocumentsDirectory`。5) `_playBytes` 的 `onPlayerStateChanged` 订阅每次播放后未取消，已改为单订阅复用。

## [S1] Problem

语音朗读当前存在三类用户可见问题：

1. **重复点击产生堆叠播放**：点击三次会同时触发三次 TTS 请求与播放，第二次点击不会停掉或排队，音频互相覆盖，行为不可预期。
2. **无播放状态反馈**：气泡下方只有一个静态扬声器图标，请求中、播放中、排队中、失败均无区分，用户无法判断是否在播、播的是哪条。
3. **短信模式无法整轮连续播**：AI 分条回复时每条都要手动点，自动朗读也只覆盖最新一条，缺少「一轮回复连续播完」的可选能力。

此外，用户需要在【我】页配置 MiMo 声音克隆 / 音色设计，并让角色包可携带已克隆声音。

## [S2] Design

### S2.1 播放状态机（TtsPlaybackController）

新增全局单例 `TtsPlaybackController`（`lib/services/tts_playback_controller.dart`），统一管理请求、排队与播放：

```dart
enum TtsPlaybackPhase { idle, synthesizing, playing, error }

class TtsPlaybackEntry {
  final String messageId;       // 关联气泡，用于图标状态
  final String requestId;       // 每次点击唯一，用于排队计数与取消
  final ApiModel model;
  final String text;
  final String voice;
  final String instructions;
}

class TtsPlaybackSnapshot {
  final TtsPlaybackPhase phase;
  final String? activeMessageId;
  final String? activeRequestId;
  final int queuedCount;        // 排队中的 entry 数（含正在合成）
  final String? errorMessage;
}
```

对外契约：

| 方法 | 行为 |
|---|---|
| `enqueue(entry)` | 追加到 FIFO 队列尾部；同 messageId 可多次入队（逐次排队） |
| `cancelMessage(messageId)` | 移除该消息所有排队 entry；若正在播放/合成该消息则停止并跳到下一条 |
| `stopAll()` | 清空队列并停止当前播放 |
| `playSequence(entries)` | 用于整轮连续播：替换剩余队列为给定序列并开始 |
| `snapshot` / `addListener` | `ChangeNotifier`，供 UI 订阅 |

调度规则：

- 队列同时只处理一条：`synthesizing` → `playing` → 下一条。
- `AudioPlayer` 播放结束（`PlayerState.completed`）才出队下一条。
- 新 `enqueue` 不打断当前播放，只追加。
- `cancelMessage` / `stopAll` 是仅有的打断手段。
- 合成失败：标记 `error` 短暂展示后自动继续下一条，不阻塞队列。

### S2.2 与 TtsService 的边界

- `TtsService` 保持纯协议层：`speak` 改造为 `synthesize`（返回音频字节）+ `playBytes`，不再内部强制 `stop()`。
- 播放控制完全上收到 `TtsPlaybackController`。
- 缓存文件清理策略不变（保留最近一份，替换旧文件）。

### S2.3 气泡播放控件 UI

`ChatBubble` 增加播放状态参数：

```dart
final TtsPlaybackPhase? playbackPhase; // null = 未关联播放
final int playbackQueuedCount;
final VoidCallback? onSpeak;           // 点击 = enqueue
final VoidCallback? onCancelPlayback;  // 点击播放中/排队中图标 = cancelMessage
```

图标状态（与现有 `CupertinoIcons` + `context.textSecondaryColor` / `context.accentColor` 风格一致）：

| 状态 | 图标 | 颜色 | 额外 |
|---|---|---|---|
| idle | `CupertinoIcons.volume_up` | `textSecondaryColor` | — |
| synthesizing | `CupertinoIcons.waveform` | `accentColor` | 轻量脉冲动画 |
| playing | `CupertinoIcons.speaker_2_fill` 或 stop 填充图标 | `accentColor` | 显示停止语义（点击 = 停止该条） |
| queued | `CupertinoIcons.volume_up` | `accentColor` | 角标显示剩余次数（如 `×3`） |
| error | `CupertinoIcons.exclamationmark_bubble` | 系统红 | 点击重试 |

按钮最小点击区扩大到 44×44 logical pixels，避免误触；图标视觉尺寸保持 18–20。

### S2.4 多条连续播（会话开关）

`Conversation` 增加 `bool continuousRead`（默认 `false`），持久化到会话数据。

- 聊天设置 / 会话资料卡增加「连续播放回复」开关。
- **开启时**：
  - 自动朗读：一轮 AI 分条回复全部生成后，`playSequence` 按时间顺序整轮播放。
  - 手动点击任一条：从该条开始，把本轮后续角色回复一并入队。
- **关闭时**：维持现状——自动朗读只播最新一条，手动点击只播被点击的一条（仍遵守逐次排队）。

「一轮回复」定义：同一次用户触发后连续到达的、`isFromUser == false` 的消息序列（中间无用户消息）。

### S2.5 MiMo 声音克隆与设计请求支持

扩展 `TtsService` 请求组装：

- **voiceclone**（`mimo-v2.5-tts-voiceclone`）：
  - `audio.voice = "data:{mime};base64,{sample}"`。
  - 样本来源：角色 `voice.sampleFile` 指向的角色包内音频，或工作台临时选择的样本。
  - 限制：仅 mp3/wav，Base64 后 ≤ 10 MB。
- **voicedesign**（`mimo-v2.5-tts-voicedesign`）：
  - `user.content` = 音色描述（必填），`assistant.content` = 试听文本。
  - 不传 `audio.voice`；支持 `optimize_text_preview`。

角色模型扩展（`Character` / `Profile.json`，向后兼容）：

```json
{
  "voice": {
    "type": "preset | design | clone",
    "voice_id": "茉莉",
    "instructions": "风格描述",
    "sample_file": "voice/sample.mp3",
    "mime_type": "audio/mpeg"
  }
}
```

- 旧包无 `type`/`sample_file` 时按 `preset` 处理。
- 角色包导入/导出自动携带 `voice/` 目录样本。
- 样本缺失或超限时导入报可读错误。

### S2.6 【我】页声音工作台

入口：【我】→「声音工作台」列表项（`CupertinoListTile`，图标 `CupertinoIcons.waveform`）。

页面 `VoiceWorkbenchScreen`（Cupertino 风格，与设置页一致）：

1. **音色设计**分组：描述输入（多行）、试听文本输入、「生成试听」→ voicedesign、「应用到角色…」。
2. **声音克隆**分组：「选择音频样本」（file_picker，mp3/wav）、样本信息（名称/大小/校验）、「克隆试听」→ voiceclone、「保存到角色…」（复制样本到角色存储并写入 voice 扩展字段）。
3. **已保存声音**分组：按角色列出音色类型，支持试听、删除。

视觉约束：`CupertinoListSection.insetGrouped`、`CupertinoButton.filled` 主操作、`showCupertinoModalPopup` 底部 Panel、theme 扩展色板。

## [S3] Out of Scope

- 不实现流式 TTS 播放（MiMo voicedesign/voiceclone 低延迟流式尚未上线）。
- 不实现音频波形真实可视化（仅用脉冲动画表达合成中）。
- 不改动 OpenAI / MiniMax / Qwen 的协议分发逻辑。
- 不做声音克隆样本的云端托管；样本仅存本地与角色包。
- 不支持将克隆声音导出为独立音频库。

## Tasks

- [x] T1: 新增 `TtsPlaybackController` 播放状态机 — acceptance: 三次 enqueue 同 messageId 产生三个排队 entry，播放顺序 FIFO，cancelMessage 只移除该消息 entry (covers: S2.1)
- [x] T2: `TtsService` 拆分 synthesize/playBytes 并移除强制 stop — acceptance: synthesize 返回音频字节且不触碰播放器；控制器独占播放 (covers: S2.2)
- [x] T3: 播放状态机单元测试 — acceptance: 排队、逐次重复、取消、stopAll、失败不阻塞均有测试且通过 (covers: S2.1)
- [x] T4: ChatBubble 播放控件状态化 — acceptance: 五种状态图标/颜色/角标正确，播放中点击停止该条，点击区 ≥44 (covers: S2.3)
- [x] T5: Conversation 增加 continuousRead 并接入会话设置开关 — acceptance: 开关持久化，重进会话保持 (covers: S2.4)
- [x] T6: 整轮连续播逻辑 — acceptance: 开启后自动朗读播完整轮；点击某条从该条起连续播后续；关闭则单条 (covers: S2.4)
- [x] T7: MiMo voiceclone/voicedesign 请求组装与角色 voice 扩展字段 — acceptance: 请求体符合官方协议；旧 Profile.json 兼容；样本导入导出带 voice/ 目录 (covers: S2.5)
- [x] T8: VoiceWorkbenchScreen 入口与三组功能 — acceptance: 可设计试听、克隆试听、保存到角色；UI 与设置页风格一致 (covers: S2.6)
- [ ] T9: 全量 analyze/test + 模拟器实测重复点击、状态图标、整轮播、工作台 — acceptance: 命令通过；模拟器验证行为符合 S2.1/S2.3/S2.4/S2.6 (covers: S2.1; S2.3; S2.4; S2.6)

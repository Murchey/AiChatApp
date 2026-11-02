# API 模型兼容格式（三种请求协议）

## 功能概述

每个 API 模型可单独选择「兼容格式」（请求报文协议），位于
「API 设置 → 编辑/添加模型 → 连接配置 → 兼容格式」：

| 选项 | 协议 | 接口 | 鉴权 |
| --- | --- | --- | --- |
| OpenAI Chat Completions（默认） | Chat Completions | `{base}/chat/completions` | `Authorization: Bearer` |
| Anthropic | Messages | `{base}/messages` | `x-api-key` + `anthropic-version: 2023-06-01` |
| OpenAI Responses | Responses | `{base}/responses` | `Authorization: Bearer` |

聊天、朋友圈互动、压缩、表情语义、语音工作台提示词等所有模型请求都按
所选格式发送；非流式与语C流式输出均支持三种协议。

## 报文转换（见 LLMService.buildChatBody）

- **Anthropic**：
  - `system` 消息提升为顶层 `system` 字段；
  - 文本消息保持 `{role, content}`；图片（data URL）转 `{type:image,
    source:{type:base64, media_type, data}}`；
  - `max_tokens` 必填；不发送 Qwen 风格思考字段（`enable_thinking` 等）。
- **OpenAI Responses**：
  - `system` 消息合并为 `instructions`；
  - 文本转 `input_text`、图片转 `input_image`（保留 data URL）；
  - `max_output_tokens`；jsonMode 映射 `text.format: json_object`。
- **OpenAI Chat Completions**：原样透传（含思考兼容字段与 `response_format`）。

## 响应解析（LLMService.parseChatReply，容错兼容三种报文）

- Chat：`choices[0].message.content`；
- Anthropic：`content` blocks（`text` 拼接正文、`thinking` 记入思考），
  `stop_reason: max_tokens` 映射为 `length`（触发"输出额度"提示）；
- Responses：`output` 数组（message 的 `output_text` 拼接、reasoning 摘要
  记入思考），`status: incomplete` 映射为 `length`；
- usage 兼容 `prompt_tokens/completion_tokens` 与
  `input_tokens/output_tokens` 两套字段名。

## 流式输出（LLMService.parseStreamChunkFor）

- Chat：`choices[0].delta`（原有行为）；
- Anthropic：`message_start`（用量）/ `content_block_delta`
  （`text_delta` 正文、`thinking_delta` 思考）/ `message_delta`（增量用量）；
- Responses：`response.output_text.delta` / `response.reasoning_*_delta`
  / `response.completed`（用量）。

## 地址与数据

- baseUrl 留空时的默认地址：Chat/Responses 用 DeepSeek 官方（Grok 名称/域名
  仍自动走 xAI）；Anthropic 用 `https://api.anthropic.com/v1`。
- baseUrl 误填完整接口地址时自动剥离末级路径
  （`/chat/completions`、`/messages`、`/responses`）。
- 存储：`ApiModel.apiFormat`（JSON 键 `api_format`，缺省 `openai-chat`，
  旧数据自动回退默认）。

## 测试

`test/services/api_format_test.dart`：URL 分派、三种报文转换、三种响应
容错解析、流式事件解析、本地服务端集成（鉴权头/路径/用量映射）、序列化。

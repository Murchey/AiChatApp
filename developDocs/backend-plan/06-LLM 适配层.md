# 06 LLM 适配层

## 1. 目标

业务层不能假设所有模型都是 GPT/OpenAI Chat Completions。不同供应商可能使用：

- OpenAI-compatible `/chat/completions`。
- Anthropic `/messages`，文本在 `content[]` 中，system 独立。
- Gemini `generateContent`，消息角色和候选结构不同。
- Qwen、MiMo、MiniMax 的原生语音/多模态字段。
- Ollama 或局域网模型，可能没有 token usage、工具调用或稳定模型名。

因此后端统一的是“能力和语义”，不是某个厂商的原始 JSON。

## 2. 领域接口

```java
public interface ModelAdapter {
    ProviderId provider();
    ModelCapabilities capabilities(ModelDescriptor model);
    CompletionResult complete(CompletionRequest request);
    void stream(CompletionRequest request, StreamObserver observer);
}

public record ModelCapabilities(
    boolean text,
    boolean vision,
    boolean audioInput,
    boolean audioOutput,
    boolean tools,
    boolean jsonMode,
    boolean streaming,
    int contextWindow
) {}
```

业务层只调用 `ModelRouter`：

```text
ChatProvider request
  -> ModelRouter.select(modelId, requiredCapabilities)
  -> PromptNormalizer
  -> ModelAdapter
  -> ProviderResponseNormalizer
  -> ChatEvent / UsageEvent
```

不要在 `ChatService` 里写 `if model.startsWith("gpt")`。模型名称永远不是能力证明；能力来自手动配置、供应商目录或探测结果。

## 3. 统一请求语义

```json
{
  "model": "provider-model-id",
  "messages": [
    {"role": "system", "content": [{"type": "text", "text": "..."}]},
    {"role": "user", "content": [{"type": "text", "text": "..."}]}
  ],
  "temperature": 0.7,
  "maxOutputTokens": 1024,
  "stream": true,
  "tools": [],
  "responseFormat": {"type": "text"}
}
```

内部规范使用 `maxOutputTokens`，适配器分别映射到 `max_tokens`、`max_tokens_to_sample` 或 Gemini 对应字段。不要把一个字段名直接透传给所有供应商。

`content` 使用 parts 而不是单一字符串，才能兼容图片、音频和未来文件。文本消息也必须用一个 text part，不能让下游自行猜类型。

## 4. 适配器必须处理的差异

### OpenAI-compatible

- 请求通常是 `messages`、`model`、`stream`。
- 响应可能是 `choices[0].message.content`，也可能是 `choices[0].delta.content`。
- 代理服务可能返回 `output_text`、非标准错误或 HTML；解析器要先按 HTTP 状态判断，再按 JSON 字段兜底。
- `usage` 可能只在最后一个流事件出现，也可能完全缺失。

### Anthropic

- system 不在 messages 中；适配器要拆分 system。
- assistant content 是数组，必须拼接所有 text block。
- 工具调用是 `tool_use` block，不能把它当普通文本发送给客户端。
- 流事件可能是 `content_block_delta`、`message_delta` 等多种类型，必须按事件类型处理。

### Gemini

- 使用 `contents[].parts[]`，角色通常是 `user`/`model`，没有直接等价的 system message（新版本可能有 system instruction）。
- 候选可能被 safety block，不能把空 text 当成成功回复。
- finish reason、usageMetadata 和候选结构都可能缺失。

### 本地模型/Ollama

- endpoint、模型名和能力由用户配置；没有公网证书、usage 或 tools 都是合法状态。
- 连接失败和模型未下载必须分开提示。
- 不要默认把 `localhost` 当作手机本机；移动端的 localhost 指向手机本身，电脑模型要使用局域网地址或内网穿透。

### 语音与多模态

- TTS、音色设计、声音克隆是独立能力，不等于文本聊天能力。
- 只有模型声明支持 `speech`/`design`/`clone` 才显示在对应选择器。
- Base64 音频不能当作普通 voice ID 发送；协议适配器负责字段和 MIME 类型转换。

## 5. 流式输出协议

后端若启用 LLM 中继，统一向 App 输出 SSE：

```text
event: start
data: {"requestId":"req_1","model":"..."}

event: delta
data: {"text":"你好"}

event: usage
data: {"inputTokens":12,"outputTokens":4}

event: done
data: {"finishReason":"stop"}
```

约束：

- 每个事件一行 `event` 和一行 `data`，JSON data 不输出裸换行。
- 客户端断开时取消下游 HTTP 请求；不能继续生成并占用额度。
- 每个请求只允许一个 `done` 或 `error`，服务器结束前发送 heartbeat 防止代理超时。
- 中间网络断开时，客户端保留已收到的 delta，使用 requestId 做重试或标记失败，不能重复拼接。
- 非流式供应商由适配器转换成一个 `delta` + `done`。

## 6. 错误归一化

内部错误至少分为：`AUTH_FAILED`、`MODEL_NOT_FOUND`、`CAPABILITY_UNSUPPORTED`、`RATE_LIMITED`、`CONTEXT_TOO_LARGE`、`PROVIDER_BAD_RESPONSE`、`PROVIDER_TIMEOUT`、`CANCELLED`。

保留供应商状态码和安全的短摘要，不能把完整响应（可能含密钥或用户 prompt）写入日志。重试策略：

- 401/403：不自动重试，要求重新配置。
- 404 model：不重试，提示模型名。
- 429：按 Retry-After 和上限退避。
- 500/502/503：最多有限次退避，并要求幂等 requestId。
- 解析失败：不重试同一坏响应，记录 provider 和响应摘要。

## 7. 工具调用与结构化输出

统一内部事件：`text_delta`、`tool_call_start`、`tool_call_delta`、`tool_call_end`、`usage`、`finish`。模型不支持 tools 时由能力检查提前拒绝。

JSON 输出不能只依赖 prompt。适配器应：

1. 使用供应商原生 JSON schema（如果支持）。
2. 设置最大输出和校验器。
3. 解析失败返回 `INVALID_STRUCTURED_OUTPUT`，保留原文给调试界面但不自动执行。
4. 工具参数通过 JSON Schema 校验后才能执行；工具执行结果再次标记为不可信输入。

## 8. 模型目录

`GET /api/models` 返回非敏感目录：provider、modelId、displayName、capabilities、contextWindow、deprecated。API Key 永远不随目录返回。

客户端手动添加模型时可以覆盖能力，但服务端中继必须再次校验；不能让客户端声明“支持工具”就绕过服务端限制。

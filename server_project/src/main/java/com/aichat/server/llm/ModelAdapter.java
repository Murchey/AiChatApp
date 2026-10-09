package com.aichat.server.llm;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.Map;

/** Protocol mapping has no network or credentials; the router owns both. */
public interface ModelAdapter {
    enum ProviderId { OPENAI, ANTHROPIC, GEMINI, OLLAMA }
    record ModelCapabilities(boolean text,boolean vision,boolean audioInput,boolean audioOutput,
                             boolean tools,boolean jsonMode,boolean streaming,int contextWindow) {}
    record ModelDescriptor(String id,String providerModelId,String displayName,ProviderId provider,
                           String endpoint,ModelCapabilities capabilities,boolean deprecated) {}
    record CompletionRequest(String model,JsonNode messages,Double temperature,Integer maxOutputTokens,
                             boolean stream,JsonNode tools,JsonNode responseFormat) {}
    record CompletionResult(String text,String finishReason,Long inputTokens,Long outputTokens,JsonNode toolCalls) {}
    record WireRequest(String path,JsonNode body,Map<String,String> headers) {}
    ProviderId provider();
    WireRequest encode(CompletionRequest request,ModelDescriptor model,String credential);
    CompletionResult decode(JsonNode response);
}

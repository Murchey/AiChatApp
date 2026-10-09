package com.aichat.server.llm;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import com.aichat.server.common.ApiException;
import com.aichat.server.llm.ModelAdapter.*;

class JsonModelAdapterTest {
    final ObjectMapper mapper=new ObjectMapper();
    CompletionRequest request() throws Exception {
        return new CompletionRequest("model",mapper.readTree("""
          [{"role":"system","content":[{"type":"text","text":"instruction"}]},
           {"role":"user","content":[{"type":"text","text":"question"}]}]
          """),0.7,512,false,null,null);
    }
    ModelDescriptor model(ProviderId provider) {
        return new ModelDescriptor("model","custom-model","Custom model",provider,"http://127.0.0.1",new ModelCapabilities(true,false,false,false,false,false,true,8192),false);
    }
    @Test void fourProtocolsMapRequestsWithoutModelNameInference() throws Exception {
        for(ProviderId provider:ProviderId.values()) {
            var adapter=new JsonModelAdapter(provider,mapper);
            var wire=adapter.encode(request(),model(provider),"temporary-key");
            assertThat(wire.body().toString()).doesNotContain("temporary-key");
            switch(provider){
                case OPENAI -> {assertThat(wire.path()).isEqualTo("/chat/completions");assertThat(wire.body().path("max_tokens").asInt()).isEqualTo(512);}
                case ANTHROPIC -> {assertThat(wire.body().path("system").path(0).path("text").asText()).isEqualTo("instruction");assertThat(wire.body().path("messages").size()).isEqualTo(1);}
                case GEMINI -> {assertThat(wire.path()).isEqualTo("/models/custom-model:generateContent");assertThat(wire.body().path("generationConfig").path("maxOutputTokens").asInt()).isEqualTo(512);}
                case OLLAMA -> {assertThat(wire.path()).isEqualTo("/api/chat");assertThat(wire.body().path("options").path("num_predict").asInt()).isEqualTo(512);}
            }
        }
    }
    @Test void fourProtocolsNormalizeTextUsageAndSafety() throws Exception {
        assertThat(new JsonModelAdapter(ProviderId.OPENAI,mapper).decode(mapper.readTree("{\"choices\":[{\"message\":{\"content\":\"answer\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":2}}")).inputTokens()).isEqualTo(5);
        assertThat(new JsonModelAdapter(ProviderId.ANTHROPIC,mapper).decode(mapper.readTree("{\"content\":[{\"type\":\"text\",\"text\":\"one\"},{\"type\":\"text\",\"text\":\"two\"}]}")).text()).isEqualTo("onetwo");
        assertThat(new JsonModelAdapter(ProviderId.GEMINI,mapper).decode(mapper.readTree("{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"answer\"}]}}]}")).text()).isEqualTo("answer");
        assertThat(new JsonModelAdapter(ProviderId.OLLAMA,mapper).decode(mapper.readTree("{\"message\":{\"content\":\"answer\"},\"done\":true}")).inputTokens()).isNull();
        assertThatThrownBy(()->new JsonModelAdapter(ProviderId.GEMINI,mapper).decode(mapper.readTree("{\"candidates\":[{\"finishReason\":\"SAFETY\"}]}"))).isInstanceOf(ApiException.class);
        assertThatThrownBy(()->new JsonModelAdapter(ProviderId.OPENAI,mapper).decode(mapper.readTree("{}"))).isInstanceOf(ApiException.class);
    }
}

package com.aichat.server.llm;

import com.aichat.server.common.ApiException;
import com.aichat.server.llm.ModelAdapter.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class LlmRelayHttpTest {
    final ObjectMapper mapper=new ObjectMapper();
    CompletionRequest request(boolean stream) throws Exception {
        return new CompletionRequest("fixture",mapper.readTree("[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"question\"}]}]"),0.5,64,stream,null,null);
    }
    LlmRelayService relay(ProviderId provider,int port) {
        LlmProperties config=new LlmProperties(); config.setAllowLocalHttp(true);config.setTimeoutSeconds(2);
        config.setModels(List.of(new ModelDescriptor("fixture","custom","Fixture",provider,"http://127.0.0.1:"+port,
            new ModelCapabilities(true,false,false,false,false,false,true,4096),false)));
        return new LlmRelayService(new ModelRouter(config,mapper),config,mapper);
    }
    LlmRelayService toolRelay(ProviderId provider,int port) {
        LlmProperties config=new LlmProperties(); config.setAllowLocalHttp(true);config.setTimeoutSeconds(2);
        config.setModels(List.of(new ModelDescriptor("fixture","custom","Fixture",provider,"http://127.0.0.1:"+port,
            new ModelCapabilities(true,false,false,false,true,true,true,4096),false)));
        return new LlmRelayService(new ModelRouter(config,mapper),config,mapper);
    }
    CompletionRequest toolRequest() throws Exception {
        return new CompletionRequest("fixture",mapper.readTree("[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"question\"}]}]"),null,64,true,
            mapper.readTree("[{\"type\":\"function\",\"function\":{\"name\":\"lookup\",\"parameters\":{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"integer\"}},\"required\":[\"id\"]}}}]"),null);
    }
    @Test void fourProtocolsCompleteOverRealHttp() throws Exception {
        for(ProviderId provider:ProviderId.values()){
            var server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
            List<String> paths=new ArrayList<>();
            server.createContext("/",exchange->{
                paths.add(exchange.getRequestURI().getPath());
                var body=mapper.readTree(exchange.getRequestBody());
                assertThat(body.toString()).doesNotContain("ephemeral");
                String response=switch(provider){
                    case OPENAI -> "{\"choices\":[{\"message\":{\"content\":\"answer\"}}]}";
                    case ANTHROPIC -> "{\"content\":[{\"type\":\"text\",\"text\":\"answer\"}]}";
                    case GEMINI -> "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"answer\"}]}}]}";
                    case OLLAMA -> "{\"message\":{\"content\":\"answer\"},\"done\":true}";
                };
                byte[] bytes=response.getBytes(StandardCharsets.UTF_8);exchange.sendResponseHeaders(200,bytes.length);
                exchange.getResponseBody().write(bytes);exchange.close();
            });server.start();
            try(var cancellation=new LlmRelayService.Cancellation()){
                assertThat(relay(provider,server.getAddress().getPort()).complete(request(false),"ephemeral","req-test",cancellation,(type,data)->{}).text()).isEqualTo("answer");
                assertThat(paths).hasSize(1);
            }finally{server.stop(0);}
        }
    }
    @Test void fourProtocolsStreamDeltasAndFinishOverRealHttp() throws Exception {
        for(ProviderId provider:ProviderId.values()){
            var server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
            String stream=switch(provider){
                case OPENAI -> "data: {\"choices\":[{\"delta\":{\"content\":\"answer\"}}]}\n\ndata: [DONE]\n\n";
                case ANTHROPIC -> "data: {\"type\":\"content_block_delta\",\"delta\":{\"text\":\"answer\"}}\n\ndata: {\"type\":\"message_stop\"}\n\n";
                case GEMINI -> "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"answer\"}]},\"finishReason\":\"STOP\"}]}\n\n";
                case OLLAMA -> "{\"message\":{\"content\":\"answer\"},\"done\":true}\n";
            };
            server.createContext("/",exchange->{byte[] bytes=stream.getBytes(StandardCharsets.UTF_8);exchange.sendResponseHeaders(200,bytes.length);exchange.getResponseBody().write(bytes);exchange.close();});
            server.start();
            try(var cancellation=new LlmRelayService.Cancellation()){
                List<String> events=new ArrayList<>();
                var result=relay(provider,server.getAddress().getPort()).complete(request(true),"ephemeral","req-test",cancellation,(type,data)->events.add(type));
                assertThat(result.text()).isEqualTo("answer");assertThat(events).containsExactly("start","delta");
            }finally{server.stop(0);}
        }
    }
    @Test void badStatusAndTruncatedStreamReturnSafeErrors() throws Exception {
        var server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
        var code=new java.util.concurrent.atomic.AtomicInteger(401);
        server.createContext("/",exchange->{byte[] bytes="data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n".getBytes(StandardCharsets.UTF_8);exchange.sendResponseHeaders(code.get(),bytes.length);exchange.getResponseBody().write(bytes);exchange.close();});
        server.start();
        try{
            var relay=relay(ProviderId.OPENAI,server.getAddress().getPort());
            try(var cancellation=new LlmRelayService.Cancellation()){
                assertThatThrownBy(()->relay.complete(request(false),"ephemeral","req-test",cancellation,(type,data)->{})).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AUTH_FAILED"));
            }
            code.set(200);
            try(var cancellation=new LlmRelayService.Cancellation()){
                List<String> events=new ArrayList<>();
                assertThatThrownBy(()->relay.complete(request(true),null,"req-test",cancellation,(type,data)->events.add(type))).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("PROVIDER_BAD_RESPONSE"));
                assertThat(events).contains("delta");
            }
        }finally{server.stop(0);}
    }
    @Test void cancellationAbortsWaitingForHeaders() throws Exception {
        var entered=new CountDownLatch(1);
        var release=new CountDownLatch(1);
        var server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
        server.createContext("/",exchange->{entered.countDown();try{release.await(2,TimeUnit.SECONDS);}catch(InterruptedException e){Thread.currentThread().interrupt();}exchange.close();});server.start();
        var workers=Executors.newVirtualThreadPerTaskExecutor();
        try(var cancellation=new LlmRelayService.Cancellation()){
            var request=request(false);
            var relay=relay(ProviderId.OPENAI,server.getAddress().getPort());
            Future<?> result=workers.submit(()->relay.complete(request,null,"req-test",cancellation,(type,data)->{}));
            assertThat(entered.await(1,TimeUnit.SECONDS)).isTrue();cancellation.close();
            assertThatThrownBy(()->result.get(1,TimeUnit.SECONDS)).isInstanceOf(ExecutionException.class)
                .satisfies(e->assertThat(e.getCause()).isInstanceOfSatisfying(ApiException.class,api->assertThat(api.getCode()).isEqualTo("CANCELLED")));
        }finally{release.countDown();server.stop(0);workers.shutdownNow();}
    }
    @Test void deadlineAbortsBodyReadAfterHeaders() throws Exception {
        var release=new CountDownLatch(1);
        var server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
        server.createContext("/",exchange->{
            exchange.sendResponseHeaders(200,0);exchange.getResponseBody().write(' ');exchange.getResponseBody().flush();
            try{release.await(5,TimeUnit.SECONDS);}catch(InterruptedException e){Thread.currentThread().interrupt();}exchange.close();
        });server.start();
        try(var cancellation=new LlmRelayService.Cancellation()){
            var service=relay(ProviderId.OPENAI,server.getAddress().getPort());
            assertThatThrownBy(()->service.complete(request(false),null,"body-timeout",cancellation,(type,data)->{}))
                .isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("PROVIDER_TIMEOUT"));
        }finally{release.countDown();server.stop(0);}
    }
    @Test void openAiToolFragmentsNormalizeAndValidateBeforeTerminalEvent() throws Exception {
        var server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
        String stream="""
            data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call-1","function":{"name":"lookup","arguments":"{\\\"id\\\":"}}]}}]}

            data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"1}"}}]},"finish_reason":"tool_calls"}]}

            data: [DONE]

            """;
        server.createContext("/",exchange->{byte[] bytes=stream.getBytes(StandardCharsets.UTF_8);exchange.sendResponseHeaders(200,bytes.length);exchange.getResponseBody().write(bytes);exchange.close();});server.start();
        try(var cancellation=new LlmRelayService.Cancellation()){
            LlmProperties config=new LlmProperties();config.setAllowLocalHttp(true);config.setTimeoutSeconds(2);
            config.setModels(List.of(new ModelDescriptor("fixture","custom","Fixture",ProviderId.OPENAI,"http://127.0.0.1:"+server.getAddress().getPort(),new ModelCapabilities(true,false,false,false,true,true,true,4096),false)));
            var original=request(true);
            var request=new CompletionRequest(original.model(),original.messages(),null,64,true,mapper.readTree("[{\"type\":\"function\",\"function\":{\"name\":\"lookup\",\"parameters\":{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"integer\"}},\"required\":[\"id\"]}}}]"),null);
            List<String> events=new ArrayList<>();
            var result=new LlmRelayService(new ModelRouter(config,mapper),config,mapper).complete(request,null,"tool-test",cancellation,(type,data)->events.add(type));
            assertThat(result.toolCalls().path(0).path("function").path("arguments").asText()).isEqualTo("{\"id\":1}");
            assertThat(events).containsExactly("start","tool_call_start","tool_call_delta","tool_call_delta","tool_call_end");
        }finally{server.stop(0);}
    }
    @Test void oversizedSseLineIsRejectedWithoutWaitingForNewline() throws Exception {
        var server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
        server.createContext("/",exchange->{byte[] bytes=("data: "+"x".repeat(70000)).getBytes(StandardCharsets.UTF_8);exchange.sendResponseHeaders(200,bytes.length);exchange.getResponseBody().write(bytes);exchange.close();});server.start();
        try(var cancellation=new LlmRelayService.Cancellation()){
            assertThatThrownBy(()->relay(ProviderId.OPENAI,server.getAddress().getPort()).complete(request(true),null,"oversized",cancellation,(type,data)->{}))
                .isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("PROVIDER_BAD_RESPONSE"));
        }finally{server.stop(0);}
    }
    @Test void fourProtocolsStreamToolCallsThroughCommonEvents() throws Exception {
        for(ProviderId provider:ProviderId.values()){
            var server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
            String stream=switch(provider){
                case OPENAI -> "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c\",\"function\":{\"name\":\"lookup\",\"arguments\":\"{\\\"id\\\":1}\"}}]}}]}\n\ndata: [DONE]\n\n";
                case ANTHROPIC -> "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"c\",\"name\":\"lookup\",\"input\":{\"id\":1}}}\n\ndata: {\"type\":\"message_stop\"}\n\n";
                case GEMINI -> "data: {\"candidates\":[{\"content\":{\"parts\":[{\"functionCall\":{\"name\":\"lookup\",\"args\":{\"id\":1}}}]},\"finishReason\":\"STOP\"}]}\n\n";
                case OLLAMA -> "{\"message\":{\"tool_calls\":[{\"function\":{\"name\":\"lookup\",\"arguments\":{\"id\":1}}}]},\"done\":true}\n";
            };
            server.createContext("/",exchange->{byte[] bytes=stream.getBytes(StandardCharsets.UTF_8);exchange.sendResponseHeaders(200,bytes.length);exchange.getResponseBody().write(bytes);exchange.close();});server.start();
            try(var cancellation=new LlmRelayService.Cancellation()){
                List<String> events=new ArrayList<>();var result=toolRelay(provider,server.getAddress().getPort()).complete(toolRequest(),null,"tool-"+provider,cancellation,(type,data)->events.add(type));
                assertThat(result.toolCalls()).isNotNull().isNotEmpty();assertThat(events).contains("tool_call_start","tool_call_end");
            }finally{server.stop(0);}
        }
    }
}

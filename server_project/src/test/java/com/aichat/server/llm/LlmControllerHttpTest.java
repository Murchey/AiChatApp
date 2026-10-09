package com.aichat.server.llm;

import com.aichat.server.auth.TokenService;
import com.aichat.server.config.AppProperties;
import com.sun.net.httpserver.HttpServer;
import java.net.*;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.util.ReflectionTestUtils;
import static org.assertj.core.api.Assertions.*;

@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")
class LlmControllerHttpTest {
    static final AtomicReference<String> mode=new AtomicReference<>("normal");
    static final HttpServer upstream=createUpstream();
    static HttpServer createUpstream(){
        try{
            var server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
            server.setExecutor(Executors.newVirtualThreadPerTaskExecutor());
            server.createContext("/",exchange->{
                String scenario=mode.get();exchange.getRequestBody().readAllBytes();
                exchange.getResponseHeaders().set("Content-Type","text/event-stream");exchange.sendResponseHeaders(200,0);
                try(var body=exchange.getResponseBody()){
                    if("stall".equals(scenario)){
                        body.write(':');body.flush();
                        try{Thread.sleep(2500);}catch(InterruptedException e){Thread.currentThread().interrupt();}
                    }else if("disconnect".equals(scenario)){
                        for(int i=0;i<100;i++){
                            body.write("data: {\"choices\":[{\"delta\":{\"content\":\"x\"}}]}\n\n".getBytes(StandardCharsets.UTF_8));body.flush();
                            try{Thread.sleep(20);}catch(InterruptedException e){Thread.currentThread().interrupt();break;}
                        }
                    }else{
                        body.write("data: {\"choices\":[{\"delta\":{\"content\":\"answer\"}}]}\n\n".getBytes(StandardCharsets.UTF_8));
                        if(!"truncated".equals(scenario))body.write("data: [DONE]\n\n".getBytes(StandardCharsets.UTF_8));
                    }
                }catch(java.io.IOException ignored){}finally{exchange.close();}
            });server.start();return server;
        }catch(Exception e){throw new IllegalStateException(e);}
    }
    @DynamicPropertySource static void config(DynamicPropertyRegistry r){
        r.add("spring.datasource.url",()->"jdbc:sqlite:file:llm_controller?mode=memory&cache=shared");
        r.add("app.features.llm-relay",()->true);
        r.add("app.llm.allow-local-http",()->true);r.add("app.llm.timeout-seconds",()->1);
        r.add("app.llm.models[0].id",()->"fixture");r.add("app.llm.models[0].provider-model-id",()->"custom");
        r.add("app.llm.models[0].display-name",()->"Fixture");r.add("app.llm.models[0].provider",()->"OPENAI");
        r.add("app.llm.models[0].endpoint",()->"http://127.0.0.1:"+upstream.getAddress().getPort());
        r.add("app.llm.models[0].capabilities.text",()->true);
        r.add("app.llm.models[0].capabilities.streaming",()->true);
        r.add("app.llm.models[0].capabilities.context-window",()->4096);
    }
    @LocalServerPort int port;
    @Autowired TokenService tokens;
    @Autowired AppProperties properties;
    @Autowired LlmController controller;
    final HttpClient client=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build();
    HttpRequest request(String token){
        var builder=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/llm/completions"))
            .timeout(Duration.ofSeconds(5)).header("Content-Type","application/json")
            .POST(HttpRequest.BodyPublishers.ofString("{\"model\":\"fixture\",\"stream\":true,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"question\"}]}]}"));
        if(token!=null)builder.header("Authorization","Bearer "+token);return builder.build();
    }
    String token(){return tokens.issue("llm-http","USER","",Instant.now()).accessToken();}
    @Test void catalogBindingAndSuccessfulSseHaveSingleTerminalEvent()throws Exception{
        mode.set("normal");
        var models=client.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/models")).GET().build(),HttpResponse.BodyHandlers.ofString());
        assertThat(models.statusCode()).isEqualTo(200);assertThat(models.body()).contains("fixture").doesNotContain("127.0.0.1");
        var result=client.send(request(token()),HttpResponse.BodyHandlers.ofString());
        assertThat(result.statusCode()).isEqualTo(200);assertThat(result.body()).contains("event:start","event:delta","event:done").doesNotContain("event:error");
        assertThat(result.body().split("event:done",-1)).hasSize(2);
    }
    @Test void truncatedAndStalledUpstreamEmitOneErrorWithoutDone()throws Exception{
        for(String scenario:new String[]{"truncated","stall"}){
            mode.set(scenario);var result=client.send(request(token()),HttpResponse.BodyHandlers.ofString());
            assertThat(result.body()).contains("event:error").doesNotContain("event:done");
            assertThat(result.body().split("event:error",-1)).hasSize(2);
            if("stall".equals(scenario))assertThat(result.body()).contains("PROVIDER_TIMEOUT");
        }
    }
    @Test void flagsAuthenticationAndDisconnectReleaseResources()throws Exception{
        assertThat(client.send(request(null),HttpResponse.BodyHandlers.ofString()).statusCode()).isEqualTo(401);
        properties.getFeatures().setLlmRelay(false);
        try{assertThat(client.send(request(token()),HttpResponse.BodyHandlers.ofString()).body()).contains("FEATURE_DISABLED");}
        finally{properties.getFeatures().setLlmRelay(true);}
        mode.set("disconnect");
        var response=client.send(request(token()),HttpResponse.BodyHandlers.ofInputStream());
        response.body().readNBytes(20);response.body().close();
        var slots=(Semaphore)ReflectionTestUtils.getField(controller,"slots");
        org.awaitility.Awaitility.await().atMost(Duration.ofSeconds(3)).until(()->slots.availablePermits()==16);
    }
    @AfterAll static void stop(){upstream.stop(0);((ExecutorService)upstream.getExecutor()).shutdownNow();}
}

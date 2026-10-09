package com.aichat.server.llm;

import com.aichat.server.common.ApiException;
import com.aichat.server.llm.ModelAdapter.*;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.*;
import java.net.URI;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.AtomicBoolean;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

@Service
public class LlmRelayService {
    private final ModelRouter router;
    private final LlmProperties properties;
    private final ObjectMapper mapper;
    private final HttpClient http=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).followRedirects(HttpClient.Redirect.NEVER).build();
    public LlmRelayService(ModelRouter router,LlmProperties properties,ObjectMapper mapper){this.router=router;this.properties=properties;this.mapper=mapper;}
    public static class Cancellation implements AutoCloseable {
        private volatile boolean cancelled;
        private final AtomicReference<InputStream> body=new AtomicReference<>();
        private final AtomicReference<CompletableFuture<?>> pending=new AtomicReference<>();
        public boolean cancelled(){return cancelled;}
        public void check(){if(cancelled)throw new ApiException(HttpStatus.REQUEST_TIMEOUT,"CANCELLED","请求已取消");}
        @Override public void close(){cancelled=true;var future=pending.getAndSet(null);if(future!=null)future.cancel(true);var stream=body.getAndSet(null);if(stream!=null)try{stream.close();}catch(IOException ignored){}}
    }
    @FunctionalInterface public interface Observer {void event(String type,Object data) throws IOException;}
    public CompletionResult complete(CompletionRequest request,String credential,String requestId,Cancellation cancellation,Observer observer){
        var model=router.select(request);
        var adapter=router.adapter(model);
        var wire=adapter.encode(request,model,credential);
        String endpoint=model.endpoint().replaceAll("/+$","")+wire.path();
        HttpRequest.Builder builder=HttpRequest.newBuilder(URI.create(endpoint)).timeout(Duration.ofSeconds(Math.max(1,Math.min(120,properties.getTimeoutSeconds()))))
            .header("Content-Type","application/json").header("X-Request-Id",requestId)
            .header("Accept",request.stream()?"text/event-stream":"application/json")
            .POST(HttpRequest.BodyPublishers.ofString(wire.body().toString(),StandardCharsets.UTF_8));
        wire.headers().forEach(builder::header);
        var deadlineReached=new AtomicBoolean();
        var deadline=Thread.ofVirtual().start(()->{
            try{
                Thread.sleep(Math.max(1,Math.min(120,properties.getTimeoutSeconds()))*1000L);
                deadlineReached.set(true);cancellation.close();
            }catch(InterruptedException ignored){Thread.currentThread().interrupt();}
        });
        try{
            cancellation.check();
            var pending=http.sendAsync(builder.build(),HttpResponse.BodyHandlers.ofInputStream());
            cancellation.pending.set(pending);
            if(cancellation.cancelled()){pending.cancel(true);cancellation.check();}
            HttpResponse<InputStream> response=pending.get(Math.max(1,Math.min(120,properties.getTimeoutSeconds())),TimeUnit.SECONDS);
            cancellation.body.set(response.body()); cancellation.check();
            try(InputStream body=response.body()){
                int status=response.statusCode();
                if(status<200||status>=300){
                    var error=providerError(status);
                    if(status==429)error.retryAfter(retryAfter(response.headers().firstValue("Retry-After").orElse("30")));
                    throw error;
                }
                if(!request.stream()){
                    byte[] raw=body.readNBytes(2*1024*1024+1);
                    if(raw.length>2*1024*1024)throw badResponse();
                    var result=adapter.decode(mapper.readTree(raw));
                    LlmSchemaValidation.result(request,result,mapper);
                    return result;
                }
                observer.event("start",Map.of("requestId",requestId,"model",model.id()));
                var result=readStream(body,model.provider(),cancellation,observer);
                LlmSchemaValidation.result(request,result,mapper);
                if(result.toolCalls()!=null)for(JsonNode call:result.toolCalls())observer.event("tool_call_end",call);
                return result;
            }finally{cancellation.body.set(null);cancellation.pending.set(null);}
        }catch(ApiException e){if(deadlineReached.get())throw timeout();throw e;}
        catch(TimeoutException e){cancellation.close();throw new ApiException(HttpStatus.GATEWAY_TIMEOUT,"PROVIDER_TIMEOUT","供应商请求超时");}
        catch(InterruptedException e){Thread.currentThread().interrupt();cancellation.close();throw new ApiException(HttpStatus.REQUEST_TIMEOUT,"CANCELLED","请求已取消");}
        catch(Exception e){if(deadlineReached.get())throw timeout();cancellation.check();throw badResponse();}
        finally{deadline.interrupt();}
    }
    private CompletionResult readStream(InputStream body,ProviderId provider,Cancellation cancellation,Observer observer) throws IOException {
        BufferedReader reader=new BufferedReader(new InputStreamReader(body,StandardCharsets.UTF_8));
        StringBuilder output=new StringBuilder();
        Long input=null,tokens=null;
        boolean finished=false;
        String reason="stop",line;
        int size=0;
        var calls=new StreamTools(observer);
        while((line=boundedLine(reader))!=null){
            cancellation.check();size+=line.length();if(size>2*1024*1024)throw badResponse();
            if(line.isBlank()||line.startsWith(":"))continue;
            String raw;
            if(provider==ProviderId.OLLAMA)raw=line;
            else if(line.startsWith("data:"))raw=line.substring(5).trim();
            else continue;
            if("[DONE]".equals(raw)){finished=true;break;}
            JsonNode chunk=mapper.readTree(raw);
            if(chunk.has("error"))throw badResponse();
            String delta="";
            switch(provider){
                case OPENAI -> {
                    JsonNode choice=chunk.path("choices").path(0);
                    delta=choice.path("delta").path("content").asText("");
                    for(JsonNode call:choice.path("delta").path("tool_calls"))calls.fragment(call.path("index").asInt(),call.path("id").asText(""),call.path("function").path("name").asText(""),call.path("function").path("arguments").asText(""));
                    if(choice.hasNonNull("finish_reason")){finished=true;reason=choice.path("finish_reason").asText();}
                    if(chunk.path("usage").has("prompt_tokens")){input=chunk.path("usage").path("prompt_tokens").asLong();tokens=chunk.path("usage").path("completion_tokens").asLong();}
                }
                case ANTHROPIC -> {
                    String type=chunk.path("type").asText();
                    if("content_block_start".equals(type)&&"tool_use".equals(chunk.path("content_block").path("type").asText())){
                        JsonNode block=chunk.path("content_block");calls.fragment(chunk.path("index").asInt(),block.path("id").asText(),block.path("name").asText(),block.path("input").isEmpty()?"":block.path("input").toString());
                    }
                    if("content_block_delta".equals(type)){
                        delta=chunk.path("delta").path("text").asText("");
                        if(chunk.path("delta").has("partial_json"))calls.fragment(chunk.path("index").asInt(),"","",chunk.path("delta").path("partial_json").asText());
                    }
                    if("message_start".equals(type)&&chunk.path("message").path("usage").has("input_tokens"))input=chunk.path("message").path("usage").path("input_tokens").asLong();
                    if("message_delta".equals(type)){reason=chunk.path("delta").path("stop_reason").asText("stop");if(chunk.path("usage").has("output_tokens"))tokens=chunk.path("usage").path("output_tokens").asLong();}
                    if("message_stop".equals(type)){finished=true;}
                }
                case GEMINI -> {
                    JsonNode candidate=chunk.path("candidates").path(0);
                    delta=JsonModelAdapter.text(candidate.path("content").path("parts"));
                    for(JsonNode part:candidate.path("content").path("parts"))if(part.has("functionCall")){JsonNode fn=part.path("functionCall");calls.whole(fn.path("name").asText(),fn.path("args"));}
                    if(candidate.has("finishReason")){finished=true;reason=candidate.path("finishReason").asText();}
                    if(Set.of("SAFETY","RECITATION").contains(reason))throw badResponse();
                    if(chunk.path("usageMetadata").has("promptTokenCount")){input=chunk.path("usageMetadata").path("promptTokenCount").asLong();tokens=chunk.path("usageMetadata").path("candidatesTokenCount").asLong();}
                }
                case OLLAMA -> {
                    delta=chunk.path("message").path("content").asText("");
                    for(JsonNode call:chunk.path("message").path("tool_calls")){JsonNode fn=call.path("function");calls.whole(fn.path("name").asText(),fn.path("arguments"));}
                    if(chunk.path("done").asBoolean()){finished=true;reason=chunk.path("done_reason").asText("stop");
                        if(chunk.has("prompt_eval_count"))input=chunk.path("prompt_eval_count").asLong();if(chunk.has("eval_count"))tokens=chunk.path("eval_count").asLong();}
                }
            }
            if(!delta.isEmpty()){output.append(delta);observer.event("delta",Map.of("text",delta));}
        }
        if(!finished)throw badResponse();
        if(input!=null||tokens!=null){Map<String,Object> usage=new LinkedHashMap<>();if(input!=null)usage.put("inputTokens",input);if(tokens!=null)usage.put("outputTokens",tokens);observer.event("usage",usage);}
        return new CompletionResult(output.toString(),reason,input,tokens,calls.result());
    }
    private final class StreamTools {
        private final Observer observer;
        private final Map<Integer,com.fasterxml.jackson.databind.node.ObjectNode> entries=new TreeMap<>();
        private final Map<Integer,StringBuilder> arguments=new HashMap<>();
        StreamTools(Observer observer){this.observer=observer;}
        void whole(String name,JsonNode args)throws IOException{fragment(entries.size(),"",name,args.toString());}
        void fragment(int index,String id,String name,String argument)throws IOException{
            if(index<0||index>127||entries.size()>32)throw badResponse();
            var entry=entries.get(index);
            if(entry==null){
                entry=mapper.createObjectNode().put("id",id.isEmpty()?"call-"+index:id).put("type","function");
                entry.putObject("function").put("name",name);entries.put(index,entry);arguments.put(index,new StringBuilder());
                observer.event("tool_call_start",Map.of("index",index,"id",entry.path("id").asText(),"name",name));
            }else{
                if(!id.isEmpty())entry.put("id",id);
                if(!name.isEmpty())((com.fasterxml.jackson.databind.node.ObjectNode)entry.path("function")).put("name",name);
            }
            if(arguments.get(index).length()+argument.length()>65536)throw badResponse();
            arguments.get(index).append(argument);
            if(!argument.isEmpty())observer.event("tool_call_delta",Map.of("index",index,"arguments",argument));
        }
        JsonNode result(){
            var result=mapper.createArrayNode();
            entries.forEach((index,entry)->{((com.fasterxml.jackson.databind.node.ObjectNode)entry.path("function")).put("arguments",arguments.get(index).isEmpty()?"{}":arguments.get(index).toString());result.add(entry);});
            return result;
        }
    }
    private ApiException timeout(){return new ApiException(HttpStatus.GATEWAY_TIMEOUT,"PROVIDER_TIMEOUT","供应商请求超时");}
    private ApiException providerError(int status){
        String code=switch(status){case 401,403 -> "AUTH_FAILED";case 404 -> "MODEL_NOT_FOUND";case 429 -> "RATE_LIMITED";default -> "PROVIDER_BAD_RESPONSE";};
        return new ApiException(status==429?HttpStatus.TOO_MANY_REQUESTS:HttpStatus.BAD_GATEWAY,code,"供应商请求失败（HTTP "+status+"）");
    }
    private int retryAfter(String raw){
        try{return (int)Math.max(1,Math.min(86400,Long.parseLong(raw)));}
        catch(Exception ignored){
            try{return (int)Math.max(1,Math.min(86400,java.time.Duration.between(java.time.Instant.now(),java.time.ZonedDateTime.parse(raw,java.time.format.DateTimeFormatter.RFC_1123_DATE_TIME).toInstant()).toSeconds()));}
            catch(Exception invalid){return 30;}
        }
    }
    private String boundedLine(Reader reader)throws IOException{
        StringBuilder line=new StringBuilder();int ch;
        while((ch=reader.read())!=-1){
            if(ch=='\n')return line.toString();
            if(line.length()>=65536)throw badResponse();
            if(ch!='\r')line.append((char)ch);
        }
        return line.isEmpty()?null:line.toString();
    }
    private ApiException badResponse(){return new ApiException(HttpStatus.BAD_GATEWAY,"PROVIDER_BAD_RESPONSE","供应商响应无法解析或连接中断");}
}

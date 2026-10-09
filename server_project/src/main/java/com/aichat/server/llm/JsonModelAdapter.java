package com.aichat.server.llm;

import com.aichat.server.common.ApiException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.*;
import java.util.*;
import org.springframework.http.HttpStatus;

/** Maps the four documented text protocols without inferring capability from model names. */
public class JsonModelAdapter implements ModelAdapter {
    private final ProviderId provider;
    private final ObjectMapper mapper;
    public JsonModelAdapter(ProviderId provider,ObjectMapper mapper){this.provider=provider;this.mapper=mapper;}
    @Override public ProviderId provider(){return provider;}
    @Override public WireRequest encode(CompletionRequest request,ModelDescriptor model,String credential){
        ObjectNode root=mapper.createObjectNode();
        Map<String,String> headers=new LinkedHashMap<>();
        String path;
        if(provider==ProviderId.OPENAI||provider==ProviderId.OLLAMA){
            root.put("model",model.providerModelId()); root.put("stream",request.stream());
            root.set("messages",normalizedMessages(request.messages(),provider==ProviderId.OLLAMA));
            if(provider==ProviderId.OPENAI){
                path="/chat/completions";
                if(credential!=null&&!credential.isBlank()) headers.put("Authorization","Bearer "+credential);
                if(request.maxOutputTokens()!=null) root.put("max_tokens",request.maxOutputTokens());
                if(request.temperature()!=null) root.put("temperature",request.temperature());
                if(request.tools()!=null&&!request.tools().isEmpty())root.set("tools",request.tools());
                if(request.responseFormat()!=null)root.set("response_format",request.responseFormat());
                if(request.stream())root.set("stream_options",mapper.createObjectNode().put("include_usage",true));
            }else{
                path="/api/chat";
                ObjectNode options=root.putObject("options");
                if(request.maxOutputTokens()!=null)options.put("num_predict",request.maxOutputTokens());
                if(request.temperature()!=null)options.put("temperature",request.temperature());
                if(request.tools()!=null&&!request.tools().isEmpty())root.set("tools",request.tools());
                if(request.responseFormat()!=null&& !"text".equals(request.responseFormat().path("type").asText()))
                    root.set("format",request.responseFormat().path("json_schema").has("schema")?request.responseFormat().path("json_schema").path("schema"):TextNode.valueOf("json"));
            }
        }else if(provider==ProviderId.ANTHROPIC){
            path="/messages"; headers.put("anthropic-version","2023-06-01");
            if(credential!=null)headers.put("x-api-key",credential);
            root.put("model",model.providerModelId());root.put("stream",request.stream());
            root.put("max_tokens",request.maxOutputTokens()==null?1024:request.maxOutputTokens());
            if(request.temperature()!=null)root.put("temperature",request.temperature());
            ArrayNode system=root.putArray("system"),messages=root.putArray("messages");
            for(JsonNode message:request.messages()){
                if("system".equals(message.path("role").asText())){
                    for(JsonNode part:message.path("content"))system.add(part);
                }else{
                    ObjectNode entry=mapper.createObjectNode().put("role",message.path("role").asText());
                    ArrayNode content=entry.putArray("content");
                    for(JsonNode part:message.path("content")){
                        if("text".equals(part.path("type").asText()))content.add(part);
                        else if("image".equals(part.path("type").asText())){
                            content.addObject().put("type","image").set("source",part.path("source"));
                        }else throw unsupported();
                    }
                    messages.add(entry);
                }
            }
            if(request.tools()!=null&&!request.tools().isEmpty()){
                ArrayNode tools=root.putArray("tools");
                for(JsonNode tool:request.tools()){
                    JsonNode fn=tool.path("function");
                    ObjectNode target=tools.addObject().put("name",fn.path("name").asText()).put("description",fn.path("description").asText());
                    target.set("input_schema",fn.path("parameters"));
                }
            }
            if(request.responseFormat()!=null&& !"text".equals(request.responseFormat().path("type").asText())) throw unsupported();
        }else{
            path="/models/"+model.providerModelId()+(request.stream()?":streamGenerateContent?alt=sse":":generateContent");
            if(credential!=null)headers.put("x-goog-api-key",credential);
            ArrayNode contents=root.putArray("contents"),system=mapper.createArrayNode();
            for(JsonNode message:request.messages()){
                String role=message.path("role").asText();
                ArrayNode parts=mapper.createArrayNode();
                for(JsonNode part:message.path("content")){
                    if("text".equals(part.path("type").asText())) parts.addObject().put("text",part.path("text").asText());
                    else if("image".equals(part.path("type").asText())) {
                        JsonNode source=part.path("source");
                        parts.addObject().putObject("inlineData").put("mimeType",source.path("media_type").asText()).put("data",source.path("data").asText());
                    }else throw unsupported();
                }
                if("system".equals(role))system.addAll(parts);
                else contents.addObject().put("role","assistant".equals(role)?"model":"user").set("parts",parts);
            }
            if(!system.isEmpty())root.putObject("systemInstruction").set("parts",system);
            ObjectNode generation=root.putObject("generationConfig");
            if(request.maxOutputTokens()!=null)generation.put("maxOutputTokens",request.maxOutputTokens());
            if(request.temperature()!=null)generation.put("temperature",request.temperature());
            if(request.responseFormat()!=null&& !"text".equals(request.responseFormat().path("type").asText())){
                generation.put("responseMimeType","application/json");
                if(request.responseFormat().path("json_schema").has("schema"))generation.set("responseSchema",request.responseFormat().path("json_schema").path("schema"));
            }
            if(request.tools()!=null&&!request.tools().isEmpty()){
                ArrayNode declarations=mapper.createArrayNode();
                for(JsonNode tool:request.tools())declarations.add(tool.path("function"));
                root.putArray("tools").addObject().set("functionDeclarations",declarations);
            }
        }
        return new WireRequest(path,root,headers);
    }
    private ArrayNode normalizedMessages(JsonNode messages,boolean ollama){
        ArrayNode result=mapper.createArrayNode();
        for(JsonNode message:messages){
            ObjectNode target=result.addObject().put("role",message.path("role").asText());
            if(ollama){
                target.put("content",text(message.path("content")));
                for(JsonNode part:message.path("content")){
                    if("image".equals(part.path("type").asText())) {
                        ArrayNode images=target.has("images")?(ArrayNode)target.get("images"):target.putArray("images");
                        images.add(part.path("source").path("data").asText());
                    }else if(!"text".equals(part.path("type").asText()))throw unsupported();
                }
            }
            else{
                ArrayNode parts=target.putArray("content");
                for(JsonNode part:message.path("content")){
                    if("text".equals(part.path("type").asText()))parts.add(part);
                    else if("image".equals(part.path("type").asText())){
                        JsonNode source=part.path("source");
                        parts.addObject().put("type","image_url").putObject("image_url").put("url","data:"+source.path("media_type").asText()+";base64,"+source.path("data").asText());
                    }else throw unsupported();
                }
            }
        }
        return result;
    }
    @Override public CompletionResult decode(JsonNode response){
        String output,reason;
        JsonNode usage,tools=null;
        Long input=null,total=null;
        if(provider==ProviderId.OPENAI){
            JsonNode choice=response.path("choices").path(0);
            output=choice.path("message").path("content").isTextual()?choice.path("message").path("content").asText():text(choice.path("message").path("content"));
            if(output.isEmpty())output=response.path("output_text").asText("");
            reason=choice.path("finish_reason").asText("stop");tools=choice.path("message").get("tool_calls");usage=response.path("usage");
            input=number(usage,"prompt_tokens");total=number(usage,"completion_tokens");
        }else if(provider==ProviderId.ANTHROPIC){
            output=text(response.path("content"));reason=response.path("stop_reason").asText("stop");usage=response.path("usage");
            input=number(usage,"input_tokens");total=number(usage,"output_tokens");
            ArrayNode calls=mapper.createArrayNode();
            for(JsonNode block:response.path("content"))if("tool_use".equals(block.path("type").asText()))calls.add(block);
            tools=calls;
        }else if(provider==ProviderId.GEMINI){
            JsonNode candidate=response.path("candidates").path(0);
            output=text(candidate.path("content").path("parts"));reason=candidate.path("finishReason").asText("stop");
            if(response.path("promptFeedback").hasNonNull("blockReason")||Set.of("SAFETY","RECITATION").contains(reason))throw badResponse("模型安全策略阻止了回复");
            usage=response.path("usageMetadata");input=number(usage,"promptTokenCount");total=number(usage,"candidatesTokenCount");
            ArrayNode calls=mapper.createArrayNode();
            for(JsonNode part:candidate.path("content").path("parts"))if(part.has("functionCall"))calls.add(part.path("functionCall"));
            tools=calls;
        }else{
            output=response.path("message").path("content").asText();reason=response.path("done_reason").asText("stop");
            input=number(response,"prompt_eval_count");total=number(response,"eval_count");tools=response.path("message").get("tool_calls");
        }
        if(output.isEmpty()&&(tools==null||tools.isEmpty()))throw badResponse("模型返回了空内容或无效格式");
        return new CompletionResult(output,reason,input,total,normalizeTools(tools));
    }
    private JsonNode normalizeTools(JsonNode tools){
        if(tools==null)return null;
        if(!tools.isArray())throw badResponse("工具调用格式无效");
        ArrayNode normalized=mapper.createArrayNode();int index=0;
        for(JsonNode call:tools){
            JsonNode fn=call.has("function")?call.path("function"):call;
            JsonNode arguments=fn.has("arguments")?fn.get("arguments"):fn.has("input")?fn.get("input"):fn.get("args");
            ObjectNode target=normalized.addObject().put("id",call.path("id").asText("call-"+index++)).put("type","function");
            target.putObject("function").put("name",fn.path("name").asText())
                .put("arguments",arguments==null?"{}":arguments.isTextual()?arguments.asText():arguments.toString());
        }
        return normalized;
    }
    public static String text(JsonNode parts){
        if(parts.isTextual())return parts.asText();
        StringBuilder text=new StringBuilder();
        if(parts.isArray())for(JsonNode part:parts)if(part.has("text"))text.append(part.path("text").asText());
        return text.toString();
    }
    private Long number(JsonNode node,String key){return node.path(key).isNumber()?node.path(key).asLong():null;}
    private ApiException unsupported(){return new ApiException(HttpStatus.BAD_REQUEST,"CAPABILITY_UNSUPPORTED","该协议不支持所请求的能力");}
    private ApiException badResponse(String text){return new ApiException(HttpStatus.BAD_GATEWAY,"PROVIDER_BAD_RESPONSE",text);}
}

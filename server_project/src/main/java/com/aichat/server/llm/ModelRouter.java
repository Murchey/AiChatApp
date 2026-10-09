package com.aichat.server.llm;

import com.aichat.server.common.ApiException;
import com.aichat.server.llm.ModelAdapter.*;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.URI;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

@Service
public class ModelRouter {
    private final LlmProperties properties;
    private final Map<ProviderId,ModelAdapter> adapters=new EnumMap<>(ProviderId.class);
    public ModelRouter(LlmProperties properties,ObjectMapper mapper){
        this.properties=properties;
        for(ProviderId provider:ProviderId.values())adapters.put(provider,new JsonModelAdapter(provider,mapper));
    }
    public ModelDescriptor select(CompletionRequest request){
        LlmSchemaValidation.request(request);
        ModelDescriptor model=properties.getModels().stream().filter(m->m.id().equals(request.model())).findFirst()
            .orElseThrow(()->error("MODEL_NOT_FOUND","模型未在服务器目录配置"));
        ModelCapabilities caps=model.capabilities();
        if(caps==null||!caps.text()||(request.stream()&&!caps.streaming()))throw unsupported();
        if(request.messages()==null||!request.messages().isArray()||request.messages().isEmpty()||request.messages().size()>200)
            throw error("VALIDATION_ERROR","messages 必须包含1至200条消息");
        long characters=0;
        for(JsonNode message:request.messages()){
            if(!Set.of("system","user","assistant").contains(message.path("role").asText())||!message.path("content").isArray()||message.path("content").isEmpty())
                throw error("VALIDATION_ERROR","消息必须使用合法角色和非空 parts");
            for(JsonNode part:message.path("content")){
                String type=part.path("type").asText();
                if("text".equals(type)){
                    if(!part.path("text").isTextual())throw error("VALIDATION_ERROR","text part 无效");
                    characters+=part.path("text").asText().length();
                }else if("image".equals(type)){
                    if(!caps.vision())throw unsupported();
                    JsonNode source=part.path("source");
                    if(!"base64".equals(source.path("type").asText())||!Set.of("image/png","image/jpeg","image/webp").contains(source.path("media_type").asText()))
                        throw error("VALIDATION_ERROR","图像必须是受支持 MIME 的 base64 source");
                    try {if(Base64.getDecoder().decode(source.path("data").asText()).length>1048576)throw error("PAYLOAD_TOO_LARGE","图像超过1MB");}
                    catch(IllegalArgumentException e){throw error("VALIDATION_ERROR","图像 Base64 无效");}
                }else throw unsupported();
            }
        }
        if(characters>100000||(caps.contextWindow()>0&&characters>caps.contextWindow()*4L))throw error("CONTEXT_TOO_LARGE","消息超过服务器上下文上限");
        if(request.temperature()!=null&&(!Double.isFinite(request.temperature())||request.temperature()<0||request.temperature()>2))throw error("VALIDATION_ERROR","temperature 超出范围");
        if(request.maxOutputTokens()!=null&&(request.maxOutputTokens()<1||request.maxOutputTokens()>32768))throw error("VALIDATION_ERROR","maxOutputTokens 超出范围");
        if(request.tools()!=null&&!request.tools().isEmpty()&&!caps.tools())throw unsupported();
        if(request.responseFormat()!=null&&!"text".equals(request.responseFormat().path("type").asText())&&!caps.jsonMode())throw unsupported();
        URI uri;
        try{uri=URI.create(model.endpoint());}catch(Exception e){throw error("VALIDATION_ERROR","服务器模型地址无效");}
        boolean local=Set.of("localhost","127.0.0.1","::1").contains(uri.getHost());
        if(uri.getHost()==null||uri.getUserInfo()!=null||uri.getQuery()!=null||uri.getFragment()!=null
            ||(!"https".equals(uri.getScheme())&&!("http".equals(uri.getScheme())&&local&&properties.isAllowLocalHttp())))
            throw error("VALIDATION_ERROR","中继 endpoint 必须为部署者配置的 HTTPS 地址");
        if(!model.providerModelId().matches("[A-Za-z0-9._:/-]{1,128}"))throw error("VALIDATION_ERROR","模型名称无效");
        if(model.provider()==ProviderId.GEMINI&&!model.providerModelId().matches("[A-Za-z0-9_-][A-Za-z0-9._-]{0,127}"))throw error("VALIDATION_ERROR","Gemini 模型必须为安全路径段");
        return model;
    }
    public ModelAdapter adapter(ModelDescriptor model){return adapters.get(model.provider());}
    public List<Map<String,Object>> catalog(){
        return properties.getModels().stream().map(model->Map.<String,Object>of("modelId",model.id(),"provider",model.provider(),"displayName",model.displayName(),"capabilities",model.capabilities(),"contextWindow",model.capabilities().contextWindow(),"deprecated",model.deprecated())).toList();
    }
    private ApiException unsupported(){return error("CAPABILITY_UNSUPPORTED","服务器模型不支持所请求能力");}
    private ApiException error(String code,String message){return new ApiException("MODEL_NOT_FOUND".equals(code)?HttpStatus.NOT_FOUND:HttpStatus.BAD_REQUEST,code,message);}
}

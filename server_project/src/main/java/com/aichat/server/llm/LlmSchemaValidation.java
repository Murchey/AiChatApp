package com.aichat.server.llm;

import com.aichat.server.common.ApiException;
import com.aichat.server.llm.ModelAdapter.*;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.networknt.schema.JsonSchemaFactory;
import com.networknt.schema.SpecVersion;
import java.util.*;
import org.springframework.http.HttpStatus;

/** No remote references: validating untrusted schemas never performs network I/O. */
public final class LlmSchemaValidation {
    private static final JsonSchemaFactory FACTORY=JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V202012);
    private LlmSchemaValidation() {}
    public static void request(CompletionRequest request){
        JsonNode tools=request.tools();
        if(tools!=null){
            if(!tools.isArray()||tools.size()>32)throw invalid("tools 必须为不超过32项的数组");
            Set<String> names=new HashSet<>();
            for(JsonNode tool:tools){
                JsonNode fn=tool.path("function");String name=fn.path("name").asText();
                if(!"function".equals(tool.path("type").asText())||!name.matches("[A-Za-z_][A-Za-z0-9_-]{0,63}")||!names.add(name))throw invalid("工具名称无效或重复");
                schema(fn.path("parameters"));
            }
        }
        JsonNode format=request.responseFormat();
        if(format!=null){
            if(!format.isObject())throw invalid("responseFormat 必须为对象");
            switch(format.path("type").asText()){
                case "text","json_object" -> {}
                case "json_schema" -> schema(format.path("json_schema").path("schema"));
                default -> throw invalid("未知 responseFormat");
            }
        }
    }
    private static void schema(JsonNode schema){
        if(!schema.isObject()||schema.toString().length()>65536)throw invalid("JSON Schema 必须为不超过64KB的对象");
        references(schema,0);
        try{FACTORY.getSchema(schema);}catch(Exception e){throw invalid("JSON Schema 无效");}
    }
    private static void references(JsonNode node,int depth){
        if(depth>32)throw invalid("JSON Schema 层级过深");
        // Restrict dialect and prohibit arbitrary schema loading/identifiers.
        if(node.isObject()){
            if(node.has("$schema")&&!"https://json-schema.org/draft/2020-12/schema".equals(node.path("$schema").asText()))throw invalid("仅支持 JSON Schema 2020-12");
            if(node.has("$id")||node.has("$dynamicRef")||node.has("$recursiveRef"))throw invalid("不支持外部 Schema 标识或动态引用");
            if(node.has("$ref")&&!node.path("$ref").asText().startsWith("#/"))throw invalid("仅支持文档内 JSON Pointer 引用");
        }
        for(JsonNode child:node)references(child,depth+1);
    }
    public static void result(CompletionRequest request,CompletionResult result,ObjectMapper mapper){
        try{
            JsonNode format=request.responseFormat();
            if(format!=null&&!"text".equals(format.path("type").asText())&&(result.toolCalls()==null||result.toolCalls().isEmpty())){
                JsonNode output=mapper.readTree(result.text());
                if(output==null||!output.isObject())throw bad();
                if("json_schema".equals(format.path("type").asText())&&!FACTORY.getSchema(format.path("json_schema").path("schema")).validate(output).isEmpty())throw bad();
            }
            if(result.toolCalls()!=null&&!result.toolCalls().isEmpty()){
                for(JsonNode call:result.toolCalls()){
                    JsonNode fn=call.has("function")?call.path("function"):call;
                    String name=fn.path("name").asText();JsonNode definition=null;
                    if(request.tools()!=null)for(JsonNode tool:request.tools())if(name.equals(tool.path("function").path("name").asText()))definition=tool.path("function");
                    if(definition==null)throw bad();
                    JsonNode arguments=fn.has("arguments")?fn.get("arguments"):fn.has("input")?fn.get("input"):fn.get("args");
                    if(arguments!=null&&arguments.isTextual())arguments=mapper.readTree(arguments.asText());
                    if(arguments==null||!arguments.isObject()||!FACTORY.getSchema(definition.path("parameters")).validate(arguments).isEmpty())throw bad();
                }
            }
        }catch(ApiException e){throw e;}catch(Exception e){throw bad();}
    }
    private static ApiException invalid(String message){return new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR",message);}
    private static ApiException bad(){return new ApiException(HttpStatus.BAD_GATEWAY,"PROVIDER_BAD_RESPONSE","模型输出或工具参数不符合请求的 JSON Schema");}
}

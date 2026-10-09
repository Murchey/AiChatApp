package com.aichat.server.llm;
import com.aichat.server.common.ApiException;
import com.aichat.server.llm.ModelAdapter.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class LlmSchemaValidationTest {
    final ObjectMapper mapper=new ObjectMapper();
    CompletionRequest request(String tools,String format)throws Exception{
        return new CompletionRequest("fixture",mapper.createArrayNode(),null,null,false,tools==null?null:mapper.readTree(tools),format==null?null:mapper.readTree(format));
    }
    @Test void toolArgumentsAreValidatedAndUnknownToolsRejected()throws Exception{
        var request=request("""
            [{"type":"function","function":{"name":"lookup","parameters":{"type":"object","properties":{"id":{"type":"integer"}},"required":["id"],"additionalProperties":false}}}]
            """,null);
        LlmSchemaValidation.request(request);
        var valid=mapper.readTree("[{\"function\":{\"name\":\"lookup\",\"arguments\":\"{\\\"id\\\":1}\"}}]");
        LlmSchemaValidation.result(request,new CompletionResult("","tool_calls",null,null,valid),mapper);
        for(String invalid:new String[]{"[{\"name\":\"lookup\",\"input\":{\"id\":\"bad\"}}]","[{\"name\":\"unknown\",\"args\":{\"id\":1}}]"}){
            var calls=mapper.readTree(invalid);
            assertThatThrownBy(()->LlmSchemaValidation.result(request,new CompletionResult("","tool_calls",null,null,calls),mapper)).isInstanceOf(ApiException.class);
        }
    }
    @Test void structuredOutputRejectsInvalidJsonAndSchemaMismatch()throws Exception{
        var request=request(null,"{\"type\":\"json_schema\",\"json_schema\":{\"schema\":{\"type\":\"object\",\"required\":[\"answer\"],\"properties\":{\"answer\":{\"type\":\"string\"}}}}}");
        LlmSchemaValidation.request(request);
        LlmSchemaValidation.result(request,new CompletionResult("{\"answer\":\"ok\"}","stop",null,null,null),mapper);
        for(String invalid:new String[]{"not json","{}","{\"answer\":3}"})assertThatThrownBy(()->LlmSchemaValidation.result(request,new CompletionResult(invalid,"stop",null,null,null),mapper)).isInstanceOf(ApiException.class);
    }
    @Test void externalReferencesAndDuplicateToolsRejectedBeforeHttp()throws Exception{
        var external=request(null,"{\"type\":\"json_schema\",\"json_schema\":{\"schema\":{\"$ref\":\"https://example.invalid/schema\"}}}");
        assertThatThrownBy(()->LlmSchemaValidation.request(external)).isInstanceOf(ApiException.class);
        var duplicate=request("[{\"type\":\"function\",\"function\":{\"name\":\"same\",\"parameters\":{}}},{\"type\":\"function\",\"function\":{\"name\":\"same\",\"parameters\":{}}}]",null);
        assertThatThrownBy(()->LlmSchemaValidation.request(duplicate)).isInstanceOf(ApiException.class);
    }
}

package com.aichat.server.story;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;
import static org.assertj.core.api.Assertions.assertThat;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class StoryDraftControllerTest {
    @Autowired MockMvc mvc;
    @Autowired JdbcTemplate jdbc;
    @Autowired ObjectMapper mapper;
    static final String DB = "jdbc:sqlite:file:m4_" + UUID.randomUUID() + "?mode=memory&cache=shared";
    @DynamicPropertySource static void config(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url", () -> DB);
        r.add("app.security.bootstrap-admin-token", () -> "m4-test-admin");
    }
    String story(String id, int version) { return """
        {"schemaVersion":1,"storyId":"%s","version":%d,"title":"Draft test","summary":"test","tags":[],
        "chapters":[{"id":"c1","title":"chapter","order":1,"memories":[{"id":"m1","order":1,"content":"setting"}]}]}
        """.formatted(id,version); }
    String create(String id) throws Exception {
        return mvc.perform(post("/api/admin/stories").header("X-Admin-Token","m4-test-admin")
            .contentType(MediaType.APPLICATION_JSON).content("{\"baseVersion\":0,\"document\":"+story(id,1)+"}"))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.revision").value(1))
            .andReturn().getResponse().getContentAsString();
    }
    @Test void lifecycleIdempotencyConflictAndImmutableVersions() throws Exception {
        create("lifecycle");
        mvc.perform(get("/api/stories/lifecycle")).andExpect(status().isNotFound());
        action("lifecycle","validate",1).andExpect(status().isOk()).andExpect(jsonPath("$.data.validatedRevision").value(1));
        action("lifecycle","submit",1).andExpect(status().isOk()).andExpect(jsonPath("$.data.revision").value(2));
        publish("lifecycle",2,0,"pub-1").andExpect(status().isOk());
        publish("lifecycle",2,0,"pub-1").andExpect(status().isOk());
        assertThat(jdbc.queryForObject("SELECT count(*) FROM story_version WHERE story_id='lifecycle'",Integer.class)).isEqualTo(1);
        publish("lifecycle",3,0,"pub-1").andExpect(status().isConflict());
        mvc.perform(put("/api/admin/stories/lifecycle/draft").header("X-Admin-Token","m4-test-admin")
            .contentType(MediaType.APPLICATION_JSON).content("{\"revision\":1,\"document\":"+story("lifecycle",2)+"}"))
            .andExpect(status().isConflict());
        mvc.perform(put("/api/admin/stories/lifecycle/draft").header("X-Admin-Token","m4-test-admin")
            .contentType(MediaType.APPLICATION_JSON).content("{\"revision\":3,\"document\":"+story("lifecycle",2)+"}"))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.baseVersion").value(1));
        mvc.perform(get("/api/stories/lifecycle")).andExpect(jsonPath("$.version").value(1));
        action("lifecycle","submit",4).andExpect(status().isOk());
        publish("lifecycle",5,0,"pub-2").andExpect(status().isConflict());
        publish("lifecycle",5,1,"pub-2").andExpect(status().isOk());
        mvc.perform(get("/api/stories/lifecycle/versions/1")).andExpect(jsonPath("$.version").value(1));
        action("lifecycle","archive",6).andExpect(status().isOk());
        mvc.perform(get("/api/stories/lifecycle")).andExpect(status().isNotFound());
        assertThat(jdbc.queryForObject("SELECT count(*) FROM admin_audit_log WHERE resource_id='lifecycle'",Integer.class)).isEqualTo(8);
    }
    @Test void malformedDraftHasFieldErrorsAndNoPublishedRows() throws Exception {
        create("invalid");
        mvc.perform(put("/api/admin/stories/invalid/draft").header("X-Admin-Token","m4-test-admin")
            .contentType(MediaType.APPLICATION_JSON).content("{\"revision\":1,\"document\":{\"storyId\":\"invalid\",\"chapters\":[]}}"))
            .andExpect(status().isOk());
        action("invalid","validate",2).andExpect(status().isBadRequest()).andExpect(jsonPath("$.error.details").isArray());
        action("invalid","submit",2).andExpect(status().isBadRequest());
        assertThat(jdbc.queryForObject("SELECT count(*) FROM story_version WHERE story_id='invalid'",Integer.class)).isZero();
        mvc.perform(get("/api/admin/stories/invalid/draft")).andExpect(status().isForbidden());
    }
    @Test void adminRoleIsGrantedOnlyByAdministratorInvite() throws Exception {
        String body=mvc.perform(post("/api/admin/invites").header("X-Admin-Token","m4-test-admin")
            .contentType(MediaType.APPLICATION_JSON).content("{\"role\":\"ADMIN\",\"maxUses\":1}"))
            .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        String code=mapper.readTree(body).path("data").path("code").asText();
        String exchange="{\"inviteCode\":\""+code+"\",\"deviceId\":\"admin-m4\"}";
        String token=mapper.readTree(mvc.perform(post("/api/invite/exchange").contentType(MediaType.APPLICATION_JSON)
            .content(exchange)).andExpect(status().isOk()).andReturn().getResponse().getContentAsString())
            .path("data").path("accessToken").asText();
        mvc.perform(get("/api/admin/stories").header("Authorization","Bearer "+token))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.items").isArray());
        mvc.perform(get("/api/admin/audit-logs").header("Authorization","Bearer "+token).param("limit","1"))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.nextCursor").isString());
        mvc.perform(post("/api/invite/exchange").contentType(MediaType.APPLICATION_JSON).content(exchange))
            .andExpect(status().isUnauthorized());
        mvc.perform(post("/api/admin/invites").contentType(MediaType.APPLICATION_JSON).content("{\"role\":\"ADMIN\"}"))
            .andExpect(status().isForbidden());
    }
    org.springframework.test.web.servlet.ResultActions action(String id,String action,long revision) throws Exception {
        return mvc.perform(post("/api/admin/stories/"+id+"/"+action).header("X-Admin-Token","m4-test-admin")
            .contentType(MediaType.APPLICATION_JSON).content("{\"revision\":"+revision+"}"));
    }
    org.springframework.test.web.servlet.ResultActions publish(String id,long revision,int base,String key) throws Exception {
        return mvc.perform(post("/api/admin/stories/"+id+"/publish").header("X-Admin-Token","m4-test-admin").header("Idempotency-Key",key)
            .contentType(MediaType.APPLICATION_JSON).content("{\"revision\":"+revision+",\"baseVersion\":"+base+"}"));
    }
}

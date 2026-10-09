package com.aichat.server.comment;

import com.aichat.server.auth.TokenService;
import com.aichat.server.config.AppProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
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
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;
import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class CommentControllerTest {
    static final String DB="jdbc:sqlite:file:m7_"+UUID.randomUUID()+"?mode=memory&cache=shared";
    @DynamicPropertySource static void config(DynamicPropertyRegistry r){r.add("spring.datasource.url",()->DB);r.add("app.features.comments",()->true);r.add("app.security.bootstrap-admin-token",()->"m7-admin");}
    @Autowired MockMvc mvc;
    @Autowired TokenService tokens;
    @Autowired ObjectMapper mapper;
    @Autowired JdbcTemplate jdbc;
    @Autowired AppProperties properties;
    @Test void concurrentDuplicateSubmissionsCreateOneComment() throws Exception {
        String story="concurrent-"+UUID.randomUUID();
        jdbc.update("INSERT INTO story(id,slug,title,status,current_version,created_at,updated_at) VALUES(?,?,?,'PUBLISHED',1,?,?)",story,story,"test",Instant.now().toString(),Instant.now().toString());
        String token=tokens.issue("concurrent-author","USER","",Instant.now()).accessToken();
        try(var executor=java.util.concurrent.Executors.newVirtualThreadPerTaskExecutor()){
            var start=new java.util.concurrent.CountDownLatch(1);
            var requests=new java.util.ArrayList<java.util.concurrent.Future<String>>();
            for(int i=0;i<8;i++)requests.add(executor.submit(()->{
                start.await();
                return mvc.perform(post("/api/stories/"+story+"/comments").header("Authorization","Bearer "+token).header("Idempotency-Key","concurrent-comment").contentType(MediaType.APPLICATION_JSON).content("{\"body\":\"one comment\"}"))
                    .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
            }));
            start.countDown();var ids=new java.util.HashSet<String>();
            for(var future:requests)ids.add(mapper.readTree(future.get(10,java.util.concurrent.TimeUnit.SECONDS)).path("data").path("id").asText());
            assertThat(ids).hasSize(1);
            assertThat(jdbc.queryForObject("SELECT count(*) FROM comment WHERE story_id=?",Integer.class,story)).isEqualTo(1);
        }
    }
    @Test void moderationRepliesReportsSoftDeleteAndPagination() throws Exception {
        jdbc.update("INSERT INTO story(id,slug,title,status,current_version,created_at,updated_at) VALUES('comment-world','comment-world','test','PUBLISHED',1,?,?)",Instant.now().toString(),Instant.now().toString());
        String token=tokens.issue("comment-author","USER","",Instant.now()).accessToken();
        String other=tokens.issue("comment-other","USER","",Instant.now()).accessToken();
        String body="{\"body\":\"plain comment\"}";
        String response=mvc.perform(post("/api/stories/comment-world/comments").header("Authorization","Bearer "+token).header("Idempotency-Key","comment-first").contentType(MediaType.APPLICATION_JSON).content(body))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.status").value("PENDING")).andReturn().getResponse().getContentAsString();
        String id=mapper.readTree(response).path("data").path("id").asText();
        mvc.perform(post("/api/stories/comment-world/comments").header("Authorization","Bearer "+token).header("Idempotency-Key","comment-first").contentType(MediaType.APPLICATION_JSON).content(body))
            .andExpect(jsonPath("$.data.id").value(id));
        assertThat(jdbc.queryForObject("SELECT count(*) FROM comment",Integer.class)).isEqualTo(1);
        mvc.perform(get("/api/stories/comment-world/comments")).andExpect(jsonPath("$.data.items").isEmpty());
        moderate(id,"VISIBLE");
        String replyResponse=mvc.perform(post("/api/comments/"+id+"/replies").header("Authorization","Bearer "+other).header("Idempotency-Key","reply-first").contentType(MediaType.APPLICATION_JSON).content("{\"body\":\"reply\"}"))
            .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        String reply=mapper.readTree(replyResponse).path("data").path("id").asText();moderate(reply,"VISIBLE");
        mvc.perform(post("/api/comments/"+reply+"/replies").header("Authorization","Bearer "+token).header("Idempotency-Key","too-deep").contentType(MediaType.APPLICATION_JSON).content(body))
            .andExpect(status().isBadRequest());
        for(int i=0;i<2;i++)mvc.perform(post("/api/comments/"+id+"/reports").header("Authorization","Bearer "+other).header("Idempotency-Key","report-first").contentType(MediaType.APPLICATION_JSON).content("{\"reasonCode\":\"SPAM\"}"))
            .andExpect(status().isOk());
        assertThat(jdbc.queryForObject("SELECT count(*) FROM report",Integer.class)).isEqualTo(1);
        mvc.perform(get("/api/admin/comments/"+id+"/reports").header("X-Admin-Token","m7-admin")).andExpect(jsonPath("$.data.items[0].reason_code").value("SPAM")).andExpect(jsonPath("$.data.hasMore").value(false));
        moderate(id,"HIDDEN");
        mvc.perform(get("/api/stories/comment-world/comments")).andExpect(jsonPath("$.data.items").isEmpty());
        moderate(id,"VISIBLE");
        String page=mvc.perform(get("/api/stories/comment-world/comments").param("limit","1")).andExpect(jsonPath("$.data.hasMore").value(true)).andReturn().getResponse().getContentAsString();
        String cursor=mapper.readTree(page).path("data").path("nextCursor").asText();
        mvc.perform(get("/api/stories/comment-world/comments").param("limit","1").param("cursor",cursor)).andExpect(jsonPath("$.data.hasMore").value(false));
        mvc.perform(delete("/api/comments/"+id).header("Authorization","Bearer "+other)).andExpect(status().isForbidden());
        mvc.perform(delete("/api/comments/"+id).header("Authorization","Bearer "+token)).andExpect(status().isOk()).andExpect(jsonPath("$.data.body").value("评论已删除"));
        mvc.perform(get("/api/stories/comment-world/comments")).andExpect(jsonPath("$.data.items.length()").value(2));
        moderate(id,"VISIBLE");
        mvc.perform(post("/api/stories/comment-world/comments").header("Authorization","Bearer "+token).header("Idempotency-Key","html").contentType(MediaType.APPLICATION_JSON).content("{\"body\":\"<script>alert(1)</script>\"}"))
            .andExpect(status().isBadRequest());
        mvc.perform(post("/api/stories/comment-world/comments").header("Idempotency-Key","anon").contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isUnauthorized());
        mvc.perform(post("/api/admin/comments/"+id+"/moderate").header("Authorization","Bearer "+token).contentType(MediaType.APPLICATION_JSON).content("{\"status\":\"VISIBLE\"}")).andExpect(status().isForbidden());
    }
    @Test void disabledCommentsDoNotChangeStoryAvailability() throws Exception {
        properties.getFeatures().setComments(false);
        try{mvc.perform(get("/api/stories/any/comments")).andExpect(status().isForbidden()).andExpect(jsonPath("$.error.code").value("FEATURE_DISABLED"));
            mvc.perform(get("/api/stories")).andExpect(status().isOk());
        }finally{properties.getFeatures().setComments(true);}
    }
    @Test void deletionCannotExposeUnreviewedOrHiddenComments() throws Exception {
        String story="visibility-"+UUID.randomUUID();
        jdbc.update("INSERT INTO story(id,slug,title,status,current_version,created_at,updated_at) VALUES(?,?,?,'PUBLISHED',1,?,?)",story,story,"test",Instant.now().toString(),Instant.now().toString());
        String token=tokens.issue("visibility-author","USER","",Instant.now()).accessToken();
        for(boolean reviewed:new boolean[]{false,true}){
            String response=mvc.perform(post("/api/stories/"+story+"/comments").header("Authorization","Bearer "+token).header("Idempotency-Key",UUID.randomUUID().toString()).contentType(MediaType.APPLICATION_JSON).content("{\"body\":\"private text\"}"))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
            String id=mapper.readTree(response).path("data").path("id").asText();
            if(reviewed){moderate(id,"VISIBLE");moderate(id,"HIDDEN");}
            mvc.perform(delete("/api/comments/"+id).header("Authorization","Bearer "+token)).andExpect(status().isOk());
            mvc.perform(get("/api/stories/"+story+"/comments")).andExpect(jsonPath("$.data.items").isEmpty());
            mvc.perform(post("/api/comments/"+id+"/replies").header("Authorization","Bearer "+token).header("Idempotency-Key",UUID.randomUUID().toString()).contentType(MediaType.APPLICATION_JSON).content("{\"body\":\"reply\"}"))
                .andExpect(status().isBadRequest());
            mvc.perform(post("/api/comments/"+id+"/reports").header("Authorization","Bearer "+token).header("Idempotency-Key",UUID.randomUUID().toString()).contentType(MediaType.APPLICATION_JSON).content("{\"reasonCode\":\"SPAM\"}"))
                .andExpect(status().isNotFound());
        }
    }
    void moderate(String id,String state)throws Exception {
        mvc.perform(post("/api/admin/comments/"+id+"/moderate").header("X-Admin-Token","m7-admin").contentType(MediaType.APPLICATION_JSON).content("{\"status\":\""+state+"\"}"))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.status").value(state));
    }
}

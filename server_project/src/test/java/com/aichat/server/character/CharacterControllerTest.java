package com.aichat.server.character;

import com.aichat.server.auth.TokenService;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.UUID;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class CharacterControllerTest {
    private static final String URL="jdbc:sqlite:file:characters_"+UUID.randomUUID()+"?mode=memory&cache=shared";
    @DynamicPropertySource static void config(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url",()->URL);
        r.add("app.security.bootstrap-admin-token",()->"character-test-admin");
        r.add("app.features.comments",()->true);
    }
    @Autowired MockMvc mvc;
    @Autowired TokenService tokens;
    @Autowired ObjectMapper mapper;
    private byte[] zip(String path,String content) throws Exception {
        var bytes=new ByteArrayOutputStream();
        try(var zip=new ZipOutputStream(bytes)){zip.putNextEntry(new ZipEntry(path));zip.write(content.getBytes(StandardCharsets.UTF_8));zip.closeEntry();}
        return bytes.toByteArray();
    }
    private void publish(String id,int version,byte[] pack) throws Exception {
        mvc.perform(post("/api/admin/characters").param("characterId",id).param("title","测试角色").param("version",String.valueOf(version))
            .header("X-Admin-Token","character-test-admin").contentType("application/zip").content(pack)).andExpect(status().isOk());
    }
    @Test void adminSessionIsVerifiedAndParameterFailuresAreNotServerErrors() throws Exception {
        mvc.perform(get("/api/admin/session")).andExpect(status().isForbidden());
        mvc.perform(get("/api/admin/session").header("X-Admin-Token","wrong")).andExpect(status().isForbidden());
        mvc.perform(get("/api/admin/session").header("X-Admin-Token","character-test-admin")).andExpect(status().isOk()).andExpect(jsonPath("$.data.role").value("ADMIN"));
        mvc.perform(get("/api/admin/connection")).andExpect(status().isForbidden());
        mvc.perform(get("/api/version")).andExpect(jsonPath("$.data.features.characters").value(true));
        mvc.perform(get("/api/characters").param("limit","invalid")).andExpect(status().isBadRequest());
        mvc.perform(get("/api/missing")).andExpect(status().isNotFound());
    }
    @Test void catalogDownloadsVersionsAndAuthenticatedCommentsAreIndependentOfStories() throws Exception {
        String id="card-"+UUID.randomUUID(); byte[] first=zip("角色/Profile.json","{\"name\":\"测试\"}");
        mvc.perform(post("/api/admin/characters").param("characterId",id).param("title","test").param("version","1").contentType("application/zip").content(first)).andExpect(status().isForbidden());
        publish(id,1,first); publish(id,1,first);
        byte[] second=zip("角色/Profile.json","{\"name\":\"第二版\"}"); publish(id,2,second);
        mvc.perform(post("/api/admin/characters").param("characterId",id).param("title","测试角色").param("version","1").header("X-Admin-Token","character-test-admin").contentType("application/zip").content(second)).andExpect(status().isConflict());
        mvc.perform(get("/api/characters").param("q","测试")).andExpect(jsonPath("$.data.items[0].characterId").value(id));
        var downloaded=mvc.perform(get("/api/characters/"+id+"/download").param("version","1")).andExpect(status().isOk()).andExpect(content().contentType("application/zip")).andReturn().getResponse().getContentAsByteArray();
        assertThat(downloaded).isEqualTo(first);
        mvc.perform(get("/api/stories")).andExpect(jsonPath("$.stories").isEmpty());
        mvc.perform(post("/api/characters/"+id+"/comments").header("Idempotency-Key","anonymous").contentType("application/json").content("{\"body\":\"test\"}")).andExpect(status().isUnauthorized());
        String token=tokens.issue("user-"+UUID.randomUUID(),"USER","测试用户",Instant.now()).accessToken();
        String response=mvc.perform(post("/api/characters/"+id+"/comments").header("Authorization","Bearer "+token).header("Idempotency-Key","character-comment").contentType("application/json").content("{\"body\":\"喜欢这个角色\"}")).andExpect(status().isOk()).andExpect(jsonPath("$.data.status").value("PENDING")).andExpect(jsonPath("$.data.characterId").value(id)).andReturn().getResponse().getContentAsString();
        String comment=mapper.readTree(response).path("data").path("id").asText();
        mvc.perform(get("/api/characters/"+id+"/comments")).andExpect(jsonPath("$.data.items").isEmpty());
        mvc.perform(post("/api/admin/comments/"+comment+"/moderate").header("X-Admin-Token","character-test-admin").contentType("application/json").content("{\"status\":\"VISIBLE\"}")).andExpect(status().isOk());
        mvc.perform(get("/api/characters/"+id+"/comments")).andExpect(jsonPath("$.data.items[0].body").value("喜欢这个角色"));
        mvc.perform(post("/api/comments/"+comment+"/replies").header("Authorization","Bearer "+token).header("Idempotency-Key","character-reply").contentType("application/json").content("{\"body\":\"回复\"}")).andExpect(status().isOk()).andExpect(jsonPath("$.data.characterId").value(id));
        mvc.perform(post("/api/comments/"+comment+"/reports").header("Authorization","Bearer "+token).header("Idempotency-Key","character-report").contentType("application/json").content("{\"reasonCode\":\"OTHER\"}")).andExpect(status().isOk());
    }
    @Test void invalidAndOversizedPackagesAreRejected() throws Exception {
        for(byte[] invalid:new byte[][] {"not a zip".getBytes(),zip("Profile.json","{}"),zip("../role/Profile.json","{}"),zip("role/Profile.json","invalid json")}) {
            mvc.perform(post("/api/admin/characters").param("characterId","invalid-card").param("title","test").param("version","1").header("X-Admin-Token","character-test-admin").contentType("application/zip").content(invalid)).andExpect(status().isBadRequest());
        }
        mvc.perform(post("/api/admin/characters").param("characterId","large-card").param("title","test").param("version","1").header("X-Admin-Token","character-test-admin").contentType("application/zip").content(new byte[4*1024*1024+1])).andExpect(status().isPayloadTooLarge());
    }
}

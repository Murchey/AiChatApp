package com.aichat.server.sync;

import com.aichat.server.auth.TokenService;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest @AutoConfigureMockMvc @ActiveProfiles("test")
class SyncSpaceControllerTest {
    static final String DB="jdbc:sqlite:file:spaces_"+UUID.randomUUID()+"?mode=memory&cache=shared";
    @DynamicPropertySource static void config(DynamicPropertyRegistry r){r.add("spring.datasource.url",()->DB);r.add("app.features.sync",()->true);}
    @Autowired MockMvc mvc;@Autowired TokenService tokens;@Autowired ObjectMapper mapper;
    @Test void ownerCreatesInviteMemberSharesEncryptedObjectWithoutSeeingPlaintext()throws Exception{
        String owner=tokens.issue("space-owner","USER","",Instant.now()).accessToken();
        String member=tokens.issue("space-member","USER","",Instant.now()).accessToken();
        String created=mvc.perform(post("/api/sync/spaces").header("Authorization","Bearer "+owner)).andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        String space=mapper.readTree(created).path("data").path("space").path("spaceId").asText();String initial=mapper.readTree(created).path("data").path("joinCode").asText();assertThat(initial).startsWith("SYN-");
        String invite=mvc.perform(post("/api/sync/spaces/"+space+"/invites").header("Authorization","Bearer "+owner)).andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        String code=mapper.readTree(invite).path("data").path("joinCode").asText();
        mvc.perform(post("/api/sync/spaces/join").header("Authorization","Bearer "+member).contentType(MediaType.APPLICATION_JSON).content(mapper.writeValueAsString(Map.of("code",code))))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.spaceId").value(space));
        mvc.perform(post("/api/sync/spaces/"+space+"/invites").header("Authorization","Bearer "+member)).andExpect(status().isForbidden());
        enable(owner,space);enable(member,space);
        // ciphertext is intentionally rejected as too short; use a valid 16-byte tag fixture below.
        byte[] bytes=new byte[16];String valid=mapper.writeValueAsString(Map.of("baseRevision",0,"sha256",HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(bytes)),"ciphertext",Base64.getEncoder().encodeToString(bytes),"nonce",Base64.getEncoder().encodeToString(new byte[12]),"algorithm","AES-256-GCM"));
        mvc.perform(put("/api/sync/objects/settings").header("Authorization","Bearer "+owner).header("X-Sync-Space",space).header("Idempotency-Key","space-write").contentType(MediaType.APPLICATION_JSON).content(valid)).andExpect(status().isOk());
        mvc.perform(get("/api/sync/objects/settings").header("Authorization","Bearer "+member).header("X-Sync-Space",space)).andExpect(status().isOk()).andExpect(jsonPath("$.data.revision").value(1));
        mvc.perform(get("/api/sync/objects/settings").header("Authorization","Bearer "+member)).andExpect(status().isForbidden());
    }
    void enable(String token,String space)throws Exception{mvc.perform(put("/api/sync/scopes/settings").header("Authorization","Bearer "+token).header("X-Sync-Space",space).contentType(MediaType.APPLICATION_JSON).content("{\"enabled\":true}" )).andExpect(status().isOk());}
}

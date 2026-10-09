package com.aichat.server.sync;

import com.aichat.server.auth.TokenService;
import com.aichat.server.config.AppProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.util.*;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
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
class EncryptedSyncTest {
    static final String DB="jdbc:sqlite:file:m5_"+UUID.randomUUID()+"?mode=memory&cache=shared";
    @DynamicPropertySource static void config(DynamicPropertyRegistry r){
        r.add("spring.datasource.url",()->DB);
        r.add("app.features.sync",()->true);
    }
    @Autowired MockMvc mvc;
    @Autowired TokenService tokens;
    @Autowired ObjectMapper mapper;
    @Autowired JdbcTemplate jdbc;
    @Autowired AppProperties properties;

    @Test void encryptedRoundtripIsolationConflictAndIdempotency() throws Exception {
        String token=tokens.issue("sync-owner","USER","",Instant.now()).accessToken();
        String other=tokens.issue("sync-other","USER","",Instant.now()).accessToken();
        byte[] key=new byte[32],nonce=new byte[12]; new java.security.SecureRandom().nextBytes(key);new java.security.SecureRandom().nextBytes(nonce);
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(key,"AES"),new GCMParameterSpec(128,nonce));
        byte[] encrypted=cipher.doFinal("{\"fontSize\":16}".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        String hash=HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(encrypted));
        String body=mapper.writeValueAsString(new EncryptedSyncService.Upload(0,hash,Base64.getEncoder().encodeToString(encrypted),Base64.getEncoder().encodeToString(nonce),"AES-256-GCM"));
        mvc.perform(put("/api/sync/objects/settings").header("Authorization","Bearer "+token).header("Idempotency-Key","sync-one")
            .contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isForbidden()).andExpect(jsonPath("$.error.code").value("SYNC_SCOPE_DISABLED"));
        enable(token);
        for(int i=0;i<2;i++) mvc.perform(put("/api/sync/objects/settings").header("Authorization","Bearer "+token).header("Idempotency-Key","sync-one")
            .contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isOk()).andExpect(jsonPath("$.data.revision").value(1));
        mvc.perform(put("/api/sync/objects/settings").header("Authorization","Bearer "+token).header("Idempotency-Key","sync-two")
            .contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isConflict());
        String response=mvc.perform(get("/api/sync/objects/settings").header("Authorization","Bearer "+token)).andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        var envelope=mapper.readTree(response).path("data");
        cipher.init(Cipher.DECRYPT_MODE,new SecretKeySpec(key,"AES"),new GCMParameterSpec(128,nonce));
        assertThat(new String(cipher.doFinal(Base64.getDecoder().decode(envelope.path("ciphertext").asText())),java.nio.charset.StandardCharsets.UTF_8)).isEqualTo("{\"fontSize\":16}");
        assertThat(jdbc.queryForObject("SELECT ciphertext FROM sync_object WHERE device_id='sync-owner'",String.class)).doesNotContain("fontSize");
        enable(other);
        mvc.perform(get("/api/sync/objects/settings").header("Authorization","Bearer "+other)).andExpect(status().isNotFound());
        mvc.perform(get("/api/sync/manifest").header("Authorization","Bearer "+token)).andExpect(jsonPath("$.data.items[0].revision").value(1));
        mvc.perform(get("/api/sync/manifest")).andExpect(status().isUnauthorized());
        mvc.perform(put("/api/sync/scopes/apiKeys").header("Authorization","Bearer "+token).contentType(MediaType.APPLICATION_JSON).content("{\"enabled\":true}")).andExpect(status().isBadRequest());
    }
    @Test void closedFeatureReturnsExplicitError() throws Exception {
        properties.getFeatures().setSync(false);
        try{mvc.perform(get("/api/sync/manifest")).andExpect(status().isForbidden()).andExpect(jsonPath("$.error.code").value("FEATURE_DISABLED"));}
        finally{properties.getFeatures().setSync(true);}
    }
    private void enable(String token) throws Exception {
        mvc.perform(put("/api/sync/scopes/settings").header("Authorization","Bearer "+token).contentType(MediaType.APPLICATION_JSON).content("{\"enabled\":true}")).andExpect(status().isOk());
    }
}

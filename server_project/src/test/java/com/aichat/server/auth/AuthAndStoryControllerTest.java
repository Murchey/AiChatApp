package com.aichat.server.auth;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.greaterThan;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;
import java.time.Instant;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.jdbc.core.JdbcTemplate;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class AuthAndStoryControllerTest {
    private static final String ADMIN_TOKEN = "test-admin-token";
    private static final String DATABASE_URL = "jdbc:sqlite:file:aichat_m1_" + UUID.randomUUID().toString().replace("-", "") + "?mode=memory&cache=shared";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private InviteRepository inviteRepository;

    @Autowired
    private TokenService tokenService;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @DynamicPropertySource
    static void properties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", () -> DATABASE_URL);
        registry.add("app.security.bootstrap-admin-token", () -> ADMIN_TOKEN);
        registry.add("app.invite-required", () -> true);
    }

    @Test
    void inviteExchangeRefreshRotationAndStoryDownloadAreCompatible() throws Exception {
        String invite = mockMvc.perform(post("/api/admin/invites")
                        .header("X-Admin-Token", ADMIN_TOKEN)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"maxUses\":1}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.code", notNullValue()))
                .andReturn().getResponse().getContentAsString();
        String code = com.fasterxml.jackson.databind.json.JsonMapper.builder().build().readTree(invite).path("data").path("code").asText();

        String exchange = mockMvc.perform(post("/api/invite/exchange")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"inviteCode\":\"" + code + "\",\"deviceId\":\"device-1\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.accessToken", notNullValue()))
                .andExpect(jsonPath("$.data.refreshToken", notNullValue()))
                .andReturn().getResponse().getContentAsString();
        var json = com.fasterxml.jackson.databind.json.JsonMapper.builder().build().readTree(exchange).path("data");
        String access = json.path("accessToken").asText();
        String refresh = json.path("refreshToken").asText();
        String storedHash = jdbcTemplate.queryForObject("SELECT token_hash FROM device WHERE id='device-1'", String.class);
        Assertions.assertThat(storedHash).isNotEqualTo(access).hasSize(64);

        String story = "{\"schemaVersion\":1,\"storyId\":\"demo-world\",\"version\":1,\"title\":\"Demo World\",\"author\":\"AiChat\",\"summary\":\"A demo\",\"tags\":[\"demo\",\"测试\"],\"chapters\":[{\"id\":\"chapter-1\",\"title\":\"Background\",\"order\":1,\"memories\":[{\"id\":\"memory-1\",\"order\":1,\"content\":\"A stable setting\"}]}]}";
        mockMvc.perform(post("/api/admin/stories/publish")
                        .header("X-Admin-Token", ADMIN_TOKEN)
                        .contentType(MediaType.APPLICATION_JSON).content(story))
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/stories").param("tag", "demo"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.stories", hasSize(1)))
                .andExpect(jsonPath("$.stories[0].storyId", is("demo-world")));

        String secondStory = story.replace("demo-world", "second-world").replace("Demo World", "Second World");
        mockMvc.perform(post("/api/admin/stories/publish").header("X-Admin-Token", ADMIN_TOKEN)
                        .contentType(MediaType.APPLICATION_JSON).content(secondStory)).andExpect(status().isOk());
        String firstPage = mockMvc.perform(get("/api/stories").param("limit", "1"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.stories", hasSize(1)))
                .andReturn().getResponse().getContentAsString();
        String nextCursor = com.fasterxml.jackson.databind.json.JsonMapper.builder().build().readTree(firstPage).path("nextCursor").asText();
        mockMvc.perform(get("/api/stories").param("limit", "1").param("cursor", nextCursor))
                .andExpect(status().isOk()).andExpect(jsonPath("$.stories", hasSize(1)));

        mockMvc.perform(get("/api/stories/demo-world/download").header("Idempotency-Key", "download-1"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.storyId", is("demo-world")));
        mockMvc.perform(get("/api/stories/demo-world/download").header("Idempotency-Key", "download-1"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.storyId", is("demo-world")));
        mockMvc.perform(get("/api/stories").param("q", "Demo World"))
                .andExpect(jsonPath("$.stories[0].storyId", is("demo-world")))
                .andExpect(jsonPath("$.stories[0].downloadCount", is(1)));

        String rotated = mockMvc.perform(post("/api/auth/refresh").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"refreshToken\":\"" + refresh + "\"}"))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        var rotatedJson = com.fasterxml.jackson.databind.json.JsonMapper.builder().build().readTree(rotated).path("data");
        String nextAccess = rotatedJson.path("accessToken").asText();
        String nextRefresh = rotatedJson.path("refreshToken").asText();
        mockMvc.perform(post("/api/auth/refresh").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"refreshToken\":\"" + refresh + "\"}"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(post("/api/auth/revoke").header("Authorization", "Bearer " + nextAccess))
                .andExpect(status().isOk());
        mockMvc.perform(post("/api/auth/refresh").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"refreshToken\":\"" + nextRefresh + "\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void invalidStoryHasFieldErrorsAndInviteCannotBeReused() throws Exception {
        String invite = mockMvc.perform(post("/api/admin/invites").header("X-Admin-Token", ADMIN_TOKEN)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"maxUses\":1}"))
                .andReturn().getResponse().getContentAsString();
        String code = com.fasterxml.jackson.databind.json.JsonMapper.builder().build().readTree(invite).path("data").path("code").asText();
        mockMvc.perform(post("/api/invite/exchange").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"inviteCode\":\"" + code + "\",\"deviceId\":\"first\"}"))
                .andExpect(status().isOk());
        mockMvc.perform(post("/api/invite/exchange").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"inviteCode\":\"" + code + "\",\"deviceId\":\"second\"}"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(post("/api/admin/stories/publish").header("X-Admin-Token", ADMIN_TOKEN)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"schemaVersion\":1,\"storyId\":\"bad\"}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.error.code", is("STORY_INVALID")))
                .andExpect(jsonPath("$.error.details", hasSize(greaterThan(0))));
    }

    @Test
    void expiredInviteIsRejected() throws Exception {
        String code = "AIC-EXPIRED-TEST";
        inviteRepository.create(tokenService.hash(code), 1, Instant.now().minusSeconds(1), Instant.now().minusSeconds(2));
        mockMvc.perform(post("/api/invite/exchange").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"inviteCode\":\"" + code + "\",\"deviceId\":\"expired-device\"}"))
                .andExpect(status().isUnauthorized());
    }
}

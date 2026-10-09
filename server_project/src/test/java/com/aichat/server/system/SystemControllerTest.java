package com.aichat.server.system;

import static org.hamcrest.Matchers.hasKey;
import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class SystemControllerTest {
    private static String databaseUrl;

    @Autowired
    private MockMvc mockMvc;
    @Test void oversizedBodyHasBoundedReadableErrorAndRequestId()throws Exception{
        mockMvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post("/api/invite/exchange")
            .contentType("application/json").content("x".repeat(com.aichat.server.common.JsonBodyLimitFilter.LIMIT+1)))
            .andExpect(status().isPayloadTooLarge()).andExpect(jsonPath("$.error.code").value("PAYLOAD_TOO_LARGE"))
            .andExpect(header().exists("X-Request-Id"));
    }

    @BeforeAll
    static void createDatabaseUrl() {
        databaseUrl = "jdbc:sqlite:file:aichat_m0_" + UUID.randomUUID().toString().replace("-", "")
                + "?mode=memory&cache=shared";
    }

    @DynamicPropertySource
    static void databaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", () -> databaseUrl);
    }

    @Test
    void healthReturnsUpAndRequestId() throws Exception {
        mockMvc.perform(get("/api/health"))
                .andExpect(status().isOk())
                .andExpect(header().exists("X-Request-Id"))
                .andExpect(jsonPath("$.data.status", is("UP")))
                .andExpect(jsonPath("$.requestId").isString());
    }

    @Test
    void versionReturnsFeatureFlags() throws Exception {
        mockMvc.perform(get("/api/version").header("X-Request-Id", "test-request-1"))
                .andExpect(status().isOk())
                .andExpect(header().string("X-Request-Id", "test-request-1"))
                .andExpect(jsonPath("$.data.apiVersion", is("v1")))
                .andExpect(jsonPath("$.data.features", hasKey("stories")))
                .andExpect(jsonPath("$.data.features.comments", is(false)))
                .andExpect(jsonPath("$.requestId", is("test-request-1")));
    }

    @Test
    void malformedRequestIdIsReplaced() throws Exception {
        mockMvc.perform(get("/api/health").header("X-Request-Id", "bad value with spaces"))
                .andExpect(status().isOk())
                .andExpect(header().string("X-Request-Id", org.hamcrest.Matchers.startsWith("req_")));
    }
}

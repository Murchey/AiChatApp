package com.aichat.server.auth;

import com.aichat.server.config.AppProperties;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class AccountControllerTest {
    private static final String URL="jdbc:sqlite:file:accounts_"+UUID.randomUUID()+"?mode=memory&cache=shared";
    @DynamicPropertySource static void config(DynamicPropertyRegistry r){r.add("spring.datasource.url",()->URL);}
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired JdbcTemplate jdbc;
    @Autowired TokenService tokens;
    @Autowired AppProperties properties;
    private MockHttpServletRequestBuilder credentials(String route,String name,String password) throws Exception {
        return post("/api/auth/"+route).with(req->{req.setRemoteAddr(UUID.randomUUID().toString());return req;})
            .contentType("application/json").content(mapper.writeValueAsString(Map.of("username",name,"password",password)));
    }
    @Test void registerLoginRefreshAndLogoutUseServerAssignedUserSessions() throws Exception {
        String username="beta_"+UUID.randomUUID().toString().replace("-","").substring(0,12);
        var response=mvc.perform(credentials("register",username.toUpperCase(),"password123")).andExpect(status().isOk())
            .andExpect(jsonPath("$.data.username").value(username)).andReturn().getResponse().getContentAsString();
        JsonNode first=mapper.readTree(response).path("data");
        String access=first.path("accessToken").asText(),device=first.path("deviceId").asText(),user=first.path("userId").asText();
        assertThat(jdbc.queryForObject("SELECT password_hash FROM user_account WHERE id=?",String.class,user)).startsWith("$2a$12$").doesNotContain("password123");
        assertThat(jdbc.queryForObject("SELECT account_id FROM device WHERE id=?",String.class,device)).isEqualTo(user);
        mvc.perform(get("/api/auth/me")).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/auth/me").header("Authorization","Bearer "+access)).andExpect(jsonPath("$.data.userId").value(user));
        mvc.perform(post("/api/admin/invites").header("Authorization","Bearer "+access).contentType("application/json").content("{}")).andExpect(status().isForbidden());
        mvc.perform(credentials("register",username,"password123")).andExpect(status().isConflict()).andExpect(jsonPath("$.error.code").value("USERNAME_EXISTS"));
        mvc.perform(credentials("login",username,"wrongpass123")).andExpect(status().isUnauthorized()).andExpect(jsonPath("$.error.message").value("账户名或密码错误"));
        mvc.perform(credentials("login","missing_user","wrongpass123")).andExpect(status().isUnauthorized()).andExpect(jsonPath("$.error.message").value("账户名或密码错误"));
        String login=mvc.perform(credentials("login",username.toUpperCase(),"password123")).andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        var second=mapper.readTree(login).path("data");assertThat(second.path("deviceId").asText()).isNotEqualTo(device);
        assertThat(second.path("userId").asText()).isEqualTo(user);
        String refreshed=mvc.perform(post("/api/auth/refresh").contentType("application/json").content(mapper.writeValueAsString(Map.of("refreshToken",second.path("refreshToken").asText())))).andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        var next=mapper.readTree(refreshed).path("data");String newAccess=next.path("accessToken").asText();
        mvc.perform(get("/api/auth/me").header("Authorization","Bearer "+newAccess)).andExpect(jsonPath("$.data.userId").value(user));
        mvc.perform(post("/api/auth/revoke").header("Authorization","Bearer "+newAccess)).andExpect(status().isOk());
        mvc.perform(get("/api/auth/me").header("Authorization","Bearer "+newAccess)).andExpect(status().isUnauthorized());
        mvc.perform(post("/api/auth/refresh").contentType("application/json").content(mapper.writeValueAsString(Map.of("refreshToken",next.path("refreshToken").asText())))).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/auth/me").header("Authorization","Bearer "+access)).andExpect(status().isOk());
    }
    @Test void validationLimitsPasswordBytesAndRejectsClientSuppliedRoleOrDevice() throws Exception {
        for(var item:new String[][]{{"ab","password123"},{"valid_name","short"},{"valid_name","密".repeat(25)},{"bad-name","password123"}})
            mvc.perform(credentials("register",item[0],item[1])).andExpect(status().isBadRequest());
        mvc.perform(post("/api/auth/register").contentType("application/json").content("{\"username\":\"malicious\",\"password\":\"password123\",\"role\":\"ADMIN\",\"deviceId\":\"existing\"}")).andExpect(status().isBadRequest());
        String old=tokens.issue("legacy-"+UUID.randomUUID(),"USER","old",Instant.now()).accessToken();
        mvc.perform(get("/api/auth/me").header("Authorization","Bearer "+old)).andExpect(status().isOk()).andExpect(jsonPath("$.data.authType").value("device"));
    }
    @Test void featureFlagAndRegistrationRateLimitAreEnforced() throws Exception {
        properties.getFeatures().setAccountAuth(false);
        try {mvc.perform(credentials("register","disabled_user","password123")).andExpect(status().isForbidden());}
        finally {properties.getFeatures().setAccountAuth(true);}
        String ip=UUID.randomUUID().toString();
        for(int n=0;n<6;n++){
            var request=post("/api/auth/register").with(req->{req.setRemoteAddr(ip);return req;}).contentType("application/json").content("{\"username\":\"a\",\"password\":\"short\"}");
            if(n<5)mvc.perform(request).andExpect(status().isBadRequest());
            else mvc.perform(request).andExpect(status().isTooManyRequests()).andExpect(header().exists("Retry-After"));
        }
    }
}

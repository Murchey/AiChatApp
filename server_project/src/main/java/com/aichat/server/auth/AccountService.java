package com.aichat.server.auth;

import com.aichat.server.common.ApiException;
import com.aichat.server.config.AppProperties;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AccountService {
    public record Account(String userId, String username, String deviceId) {}
    public record Session(Account account, TokenService.TokenPair tokens) {}
    private record Stored(String id, String username, String hash) {}
    private final JdbcTemplate jdbc;
    private final TokenService tokens;
    private final AppProperties properties;
    private final BCryptPasswordEncoder passwords = new BCryptPasswordEncoder(12);
    private final String dummyHash = passwords.encode(UUID.randomUUID().toString());

    public AccountService(JdbcTemplate jdbc, TokenService tokens, AppProperties properties) {
        this.jdbc = jdbc; this.tokens = tokens; this.properties = properties;
    }
    private void enabled() {
        if (!properties.getFeatures().isAccountAuth()) throw error(HttpStatus.FORBIDDEN, "FEATURE_DISABLED", "服务器账号认证未启用");
    }
    private String username(String value) {
        String normalized = value == null ? "" : value.trim().toLowerCase(Locale.ROOT);
        if (!normalized.matches("[a-z0-9_]{3,32}")) throw error(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "账户名须为3至32位字母、数字或下划线");
        return normalized;
    }
    private void password(String value) {
        if (value == null || value.codePointCount(0, value.length()) < 8 || value.getBytes(StandardCharsets.UTF_8).length > 72)
            throw error(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "密码至少8个字符，且不能超过72个UTF-8字节");
    }
    @Transactional
    public Session register(String name, String password) {
        enabled(); String username = username(name); password(password);
        String accountId = UUID.randomUUID().toString();
        int inserted = jdbc.update("INSERT INTO user_account(id,username,password_hash,created_at) VALUES(?,?,?,?) ON CONFLICT(username) DO NOTHING", accountId, username, passwords.encode(password), Instant.now().toString());
        if (inserted == 0) throw error(HttpStatus.CONFLICT, "USERNAME_EXISTS", "账户名已被注册");
        return session(accountId, username);
    }
    @Transactional
    public Session login(String name, String password) {
        enabled(); String username = username(name); password(password);
        Stored stored = jdbc.query("SELECT id,username,password_hash FROM user_account WHERE username=?", (rs,n) -> new Stored(rs.getString(1),rs.getString(2),rs.getString(3)),username).stream().findFirst().orElse(null);
        boolean matches = passwords.matches(password, stored == null ? dummyHash : stored.hash());
        if (stored == null || !matches) throw error(HttpStatus.UNAUTHORIZED, "INVALID_CREDENTIALS", "账户名或密码错误");
        return session(stored.id(), stored.username());
    }
    private Session session(String accountId, String username) {
        String deviceId = UUID.randomUUID().toString();
        var pair = tokens.issue(deviceId, "USER", username, Instant.now());
        jdbc.update("UPDATE device SET account_id=? WHERE id=?", accountId, deviceId);
        return new Session(new Account(accountId, username, deviceId), pair);
    }
    public Object me(CurrentDevice device) {
        enabled();
        if (device == null) throw error(HttpStatus.UNAUTHORIZED, "AUTH_REQUIRED", "请先登录服务器账号");
        return jdbc.query("SELECT a.id,a.username FROM user_account a JOIN device d ON d.account_id=a.id WHERE d.id=?", (rs,n) -> (Object)new Account(rs.getString(1),rs.getString(2),device.id()),device.id()).stream().findFirst()
            .orElse(Map.of("deviceId",device.id(),"authType","device"));
    }
    private ApiException error(HttpStatus status,String code,String message) { return new ApiException(status,code,message); }
}

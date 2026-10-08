package com.aichat.server.auth;

import com.aichat.server.common.ApiException;
import com.aichat.server.config.AppProperties;
import java.time.Clock;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthService {
    private final InviteRepository invites;
    private final TokenService tokens;
    private final AppProperties properties;
    private final Clock clock = Clock.systemUTC();

    public AuthService(InviteRepository invites, TokenService tokens, AppProperties properties) {
        this.invites = invites;
        this.tokens = tokens;
        this.properties = properties;
    }

    @Transactional
    public TokenService.TokenPair exchange(String inviteCode, String deviceId, String label) {
        String normalizedCode = inviteCode == null ? "" : inviteCode.trim();
        String id = deviceId == null || deviceId.isBlank() ? UUID.randomUUID().toString() : deviceId.trim();
        if (id.length() > 128) throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_DEVICE_ID", "设备 ID 过长");
        if (properties.isInviteRequired() && (normalizedCode.isEmpty() || !invites.consume(tokens.hash(normalizedCode), clock.instant()))) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_INVITE", "邀请码无效、已用尽或已过期");
        }
        return tokens.issue(id, "USER", label == null ? "" : label.trim(), clock.instant());
    }

    public TokenService.TokenPair refresh(String refreshToken) {
        return tokens.rotate(require(refreshToken, "刷新令牌不能为空", "REFRESH_REQUIRED"));
    }

    public void revoke(CurrentDevice device) {
        if (device == null) throw new ApiException(HttpStatus.UNAUTHORIZED, "AUTH_REQUIRED", "需要设备令牌");
        tokens.revoke(device.id());
    }

    private String require(String value, String message, String code) {
        if (value == null || value.isBlank()) throw new ApiException(HttpStatus.BAD_REQUEST, code, message);
        return value.trim();
    }
}

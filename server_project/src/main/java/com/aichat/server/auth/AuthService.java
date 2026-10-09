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
    private final DeviceRepository devices;
    private final Clock clock = Clock.systemUTC();

    public AuthService(InviteRepository invites, TokenService tokens, AppProperties properties, DeviceRepository devices) {
        this.invites = invites;
        this.tokens = tokens;
        this.properties = properties;
        this.devices = devices;
    }

    @Transactional
    public TokenService.TokenPair exchange(String inviteCode, String deviceId, String label) {
        String normalizedCode = inviteCode == null ? "" : inviteCode.trim();
        String id = deviceId == null || deviceId.isBlank() ? UUID.randomUUID().toString() : deviceId.trim();
        if (id.length() > 128) throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_DEVICE_ID", "设备 ID 过长");
        if ((properties.isInviteRequired() && normalizedCode.isEmpty())
                || (!normalizedCode.isEmpty() && !invites.consume(tokens.hash(normalizedCode), clock.instant()))) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_INVITE", "邀请码无效、已用尽或已过期");
        }
        if (devices.exists(id)) throw new ApiException(HttpStatus.CONFLICT, "DEVICE_ID_EXISTS", "设备 ID 已绑定，请使用新设备 ID 重新绑定；已有会话使用刷新接口");
        String role = normalizedCode.isEmpty() ? "USER" : invites.role(tokens.hash(normalizedCode));
        return tokens.issue(id, role, label == null ? "" : label.trim(), clock.instant());
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

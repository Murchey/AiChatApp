package com.aichat.server.auth.web;

import com.aichat.server.auth.AuthService;
import com.aichat.server.auth.CurrentDevice;
import com.aichat.server.auth.SimpleRateLimiter;
import com.aichat.server.auth.TokenService;
import com.aichat.server.common.ApiResponse;
import com.aichat.server.common.RequestIdFilter;
import jakarta.servlet.http.HttpServletRequest;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class AuthController {
    private final AuthService auth;
    private final SimpleRateLimiter limiter;

    public AuthController(AuthService auth, SimpleRateLimiter limiter) {
        this.auth = auth;
        this.limiter = limiter;
    }

    @PostMapping("/invite/exchange")
    public ApiResponse<Map<String, Object>> exchange(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        String deviceId = text(body.get("deviceId"), body.get("device_id"));
        limiter.check("invite:" + request.getRemoteAddr() + ":" + (deviceId == null ? "unknown" : deviceId), 10, 60);
        TokenService.TokenPair pair = auth.exchange(text(body.get("inviteCode"), body.get("invite_code")),
                deviceId, text(body.get("label")));
        return response(pair, RequestIdFilter.from(request));
    }

    @PostMapping("/auth/refresh")
    public ApiResponse<Map<String, Object>> refresh(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        limiter.check("refresh:" + request.getRemoteAddr(), 30, 60);
        return response(auth.refresh(text(body.get("refreshToken"), body.get("refresh_token"))), RequestIdFilter.from(request));
    }

    @PostMapping("/auth/revoke")
    public ApiResponse<Map<String, Object>> revoke(HttpServletRequest request) {
        Object value = request.getAttribute(CurrentDevice.REQUEST_ATTRIBUTE);
        auth.revoke(value instanceof CurrentDevice device ? device : null);
        return new ApiResponse<>(Map.of("revoked", true), RequestIdFilter.from(request));
    }

    private ApiResponse<Map<String, Object>> response(TokenService.TokenPair pair, String requestId) {
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("accessToken", pair.accessToken());
        data.put("refreshToken", pair.refreshToken());
        data.put("accessExpiresAt", pair.accessExpiresAt());
        data.put("refreshExpiresAt", pair.refreshExpiresAt());
        return new ApiResponse<>(data, requestId);
    }

    private String text(Object... values) {
        for (Object value : values) if (value != null && !value.toString().isBlank()) return value.toString().trim();
        return null;
    }
}

package com.aichat.server.system.web;

import com.aichat.server.auth.AdminAuthService;
import com.aichat.server.common.ApiResponse;
import com.aichat.server.common.RequestIdFilter;
import com.aichat.server.config.AppProperties;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class AdminSystemController {
    private final AdminAuthService auth;
    private final AppProperties properties;

    public AdminSystemController(AdminAuthService auth, AppProperties properties) {
        this.auth = auth;
        this.properties = properties;
    }

    @GetMapping("/api/admin/session")
    public ApiResponse<?> session(HttpServletRequest request) {
        var actor = auth.requireAdmin(request);
        return new ApiResponse<>(Map.of("role", actor.role(), "label", actor.label()), RequestIdFilter.from(request));
    }

    @GetMapping("/api/admin/connection")
    public ApiResponse<?> connection(HttpServletRequest request) {
        auth.requireAdmin(request);
        return new ApiResponse<>(Map.of(
                "publicBaseUrl", properties.getPublicBaseUrl(),
                "inviteRequired", properties.isInviteRequired(),
                "healthPath", "/api/health", "versionPath", "/api/version"), RequestIdFilter.from(request));
    }
}

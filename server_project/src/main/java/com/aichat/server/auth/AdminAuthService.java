package com.aichat.server.auth;

import com.aichat.server.common.ApiException;
import com.aichat.server.config.AppProperties;
import jakarta.servlet.http.HttpServletRequest;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

@Service
public class AdminAuthService {
    private final AppProperties properties;

    public AdminAuthService(AppProperties properties) {
        this.properties = properties;
    }

    public CurrentDevice requireAdmin(HttpServletRequest request) {
        Object value = request.getAttribute(CurrentDevice.REQUEST_ATTRIBUTE);
        if (value instanceof CurrentDevice device && device.isAdmin()) return device;
        String configured = properties.getSecurity().getBootstrapAdminToken();
        String supplied = request.getHeader("X-Admin-Token");
        if (configured != null && !configured.isBlank() && supplied != null
                && MessageDigest.isEqual(configured.getBytes(StandardCharsets.UTF_8), supplied.getBytes(StandardCharsets.UTF_8))) {
            return new CurrentDevice("bootstrap", "bootstrap", "ADMIN", null);
        }
        throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "需要管理员权限");
    }
}

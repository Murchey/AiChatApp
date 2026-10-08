package com.aichat.server.auth.web;

import com.aichat.server.auth.AdminAuthService;
import com.aichat.server.auth.AuditRepository;
import com.aichat.server.auth.CurrentDevice;
import com.aichat.server.auth.InviteService;
import com.aichat.server.auth.TokenService;
import com.aichat.server.common.ApiResponse;
import com.aichat.server.common.RequestIdFilter;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/admin")
public class AdminInviteController {
    private final AdminAuthService admin;
    private final InviteService invites;
    private final TokenService tokens;
    private final AuditRepository audit;

    public AdminInviteController(AdminAuthService admin, InviteService invites, TokenService tokens, AuditRepository audit) {
        this.admin = admin;
        this.invites = invites;
        this.tokens = tokens;
        this.audit = audit;
    }

    @PostMapping("/invites")
    public ApiResponse<InviteService.CreatedInvite> create(@RequestBody(required = false) Map<String, Object> body,
                                                            HttpServletRequest request) {
        var actor = admin.requireAdmin(request);
        Map<String, Object> safe = body == null ? Map.of() : body;
        int maxUses = number(safe.get("maxUses"), safe.get("max_uses"), 1);
        Integer expires = numberOrNull(safe.get("expiresInHours"), safe.get("expires_in_hours"));
        var created = invites.create(maxUses, expires);
        audit.record(actor, "INVITE_CREATED", "INVITE", null, RequestIdFilter.from(request));
        return new ApiResponse<>(created, RequestIdFilter.from(request));
    }

    @PostMapping("/devices/{deviceId}/revoke")
    public ApiResponse<Map<String, Object>> revoke(@PathVariable String deviceId, HttpServletRequest request) {
        var actor = admin.requireAdmin(request);
        tokens.revoke(deviceId);
        audit.record(actor, "DEVICE_REVOKED", "DEVICE", deviceId, RequestIdFilter.from(request));
        return new ApiResponse<>(Map.of("deviceId", deviceId, "revoked", true), RequestIdFilter.from(request));
    }

    private int number(Object first, Object second, int fallback) {
        Object value = first != null ? first : second;
        if (value instanceof Number number) return number.intValue();
        try { return value == null ? fallback : Integer.parseInt(value.toString()); }
        catch (NumberFormatException ignored) { return fallback; }
    }

    private Integer numberOrNull(Object first, Object second) {
        Object value = first != null ? first : second;
        if (value == null) return null;
        try { return value instanceof Number n ? n.intValue() : Integer.parseInt(value.toString()); }
        catch (NumberFormatException ignored) { return null; }
    }
}

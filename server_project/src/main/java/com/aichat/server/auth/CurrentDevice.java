package com.aichat.server.auth;

import java.time.Instant;

/** Authentication result attached to a request by {@link AuthFilter}. */
public record CurrentDevice(String id, String label, String role, Instant accessExpiresAt) {
    public static final String REQUEST_ATTRIBUTE = CurrentDevice.class.getName();

    public boolean isAdmin() {
        return "ADMIN".equalsIgnoreCase(role);
    }
}

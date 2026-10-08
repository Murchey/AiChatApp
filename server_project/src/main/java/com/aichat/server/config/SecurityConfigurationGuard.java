package com.aichat.server.config;

import org.springframework.stereotype.Component;

@Component
public class SecurityConfigurationGuard {
    public SecurityConfigurationGuard(AppProperties properties) {
        if (properties.getSecurity().isRequireTokenPepper()
                && properties.getSecurity().getTokenPepper().trim().length() < 32) {
            throw new IllegalStateException(
                    "AICHAT_TOKEN_PEPPER must contain at least 32 characters when token protection is enabled");
        }
    }
}

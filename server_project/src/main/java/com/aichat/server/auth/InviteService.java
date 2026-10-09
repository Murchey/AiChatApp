package com.aichat.server.auth;

import java.security.SecureRandom;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import org.springframework.stereotype.Service;

@Service
public class InviteService {
    public record CreatedInvite(String code, Instant expiresAt, int maxUses) {}

    private final InviteRepository repository;
    private final TokenService tokens;
    private final SecureRandom random = new SecureRandom();

    public InviteService(InviteRepository repository, TokenService tokens) {
        this.repository = repository;
        this.tokens = tokens;
    }

    public CreatedInvite create(int maxUses, Integer expiresInHours) {
        return create(maxUses, expiresInHours, "USER");
    }

    @org.springframework.transaction.annotation.Transactional
    public CreatedInvite create(int maxUses, Integer expiresInHours, String role) {
        if (!"USER".equals(role) && !"ADMIN".equals(role)) {
            throw new com.aichat.server.common.ApiException(org.springframework.http.HttpStatus.BAD_REQUEST,
                    "VALIDATION_ERROR", "邀请码角色只能为 USER 或 ADMIN");
        }
        int uses = Math.max(1, Math.min(maxUses, 1000));
        Instant expires = expiresInHours == null || expiresInHours <= 0
                ? null : Instant.now().plus(Math.min(expiresInHours, 24 * 365), ChronoUnit.HOURS);
        String code = "AIC-" + randomCode(20);
        String id = repository.create(tokens.hash(code), uses, expires, Instant.now());
        repository.assignRole(id, role);
        return new CreatedInvite(code, expires, uses);
    }

    private String randomCode(int length) {
        final String alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        StringBuilder result = new StringBuilder(length);
        for (int i = 0; i < length; i++) result.append(alphabet.charAt(random.nextInt(alphabet.length())));
        return result.toString();
    }
}

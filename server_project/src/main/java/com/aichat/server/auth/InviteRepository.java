package com.aichat.server.auth;

import java.time.Instant;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class InviteRepository {
    private final JdbcTemplate jdbc;

    public InviteRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public String create(String codeHash, int maxUses, Instant expiresAt, Instant now) {
        String id = UUID.randomUUID().toString();
        jdbc.update("INSERT INTO invite_code(id,code_hash,max_uses,used_count,expires_at,status,created_at) VALUES(?,?,?,0,?,'ACTIVE',?)",
                id, codeHash, maxUses, expiresAt == null ? null : expiresAt.toString(), now.toString());
        return id;
    }

    public boolean consume(String codeHash, Instant now) {
        int updated = jdbc.update("UPDATE invite_code SET used_count=used_count+1 "
                        + "WHERE code_hash=? AND status='ACTIVE' AND used_count<max_uses "
                        + "AND (expires_at IS NULL OR expires_at>?)",
                codeHash, now.toString());
        return updated == 1;
    }
}

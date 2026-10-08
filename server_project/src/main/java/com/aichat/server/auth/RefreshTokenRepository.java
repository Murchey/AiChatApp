package com.aichat.server.auth;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class RefreshTokenRepository {
    public record Stored(String id, String deviceId, Instant expiresAt, Instant revokedAt) {
        public boolean activeAt(Instant now) { return revokedAt == null && expiresAt.isAfter(now); }
    }

    private final JdbcTemplate jdbc;

    public RefreshTokenRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public String insert(String deviceId, String tokenHash, Instant expiresAt, Instant now) {
        String id = UUID.randomUUID().toString();
        jdbc.update("INSERT INTO refresh_token(id,device_id,token_hash,expires_at,created_at) VALUES(?,?,?,?,?)",
                id, deviceId, tokenHash, expiresAt.toString(), now.toString());
        return id;
    }

    public Optional<Stored> findByHash(String tokenHash) {
        return jdbc.query("SELECT id,device_id,expires_at,revoked_at FROM refresh_token WHERE token_hash=?",
                this::map, tokenHash).stream().findFirst();
    }

    public void revoke(String id, Instant now, String replacedById) {
        jdbc.update("UPDATE refresh_token SET revoked_at=?, replaced_by_id=? WHERE id=? AND revoked_at IS NULL",
                now.toString(), replacedById, id);
    }

    public void revokeForDevice(String deviceId, Instant now) {
        jdbc.update("UPDATE refresh_token SET revoked_at=? WHERE device_id=? AND revoked_at IS NULL",
                now.toString(), deviceId);
    }

    private Stored map(ResultSet rs, int row) throws SQLException {
        String revoked = rs.getString("revoked_at");
        return new Stored(rs.getString("id"), rs.getString("device_id"),
                Instant.parse(rs.getString("expires_at")), revoked == null ? null : Instant.parse(revoked));
    }
}

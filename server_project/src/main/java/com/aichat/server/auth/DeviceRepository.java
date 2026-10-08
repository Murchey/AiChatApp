package com.aichat.server.auth;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.util.Optional;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class DeviceRepository {
    private final JdbcTemplate jdbc;

    public DeviceRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public void insert(String id, String label, String tokenHash, String role,
                       Instant now, Instant accessExpiresAt) {
        jdbc.update("INSERT INTO device(id,label,token_hash,role,status,last_seen_at,created_at,updated_at,access_expires_at) "
                        + "VALUES(?,?,?,?, 'ACTIVE',?,?,?,?)",
                id, label, tokenHash, role, now.toString(), now.toString(), now.toString(), accessExpiresAt.toString());
    }

    public Optional<CurrentDevice> findByAccessHash(String tokenHash, Instant now) {
        return jdbc.query("SELECT id,label,role,access_expires_at FROM device "
                        + "WHERE token_hash=? AND status='ACTIVE' AND access_expires_at>?",
                this::mapCurrent, tokenHash, now.toString()).stream().findFirst();
    }

    public Optional<CurrentDevice> findById(String id) {
        return jdbc.query("SELECT id,label,role,access_expires_at FROM device WHERE id=? AND status='ACTIVE'",
                this::mapCurrent, id).stream().findFirst();
    }

    public void rotateAccess(String id, String tokenHash, Instant now, Instant expiresAt) {
        jdbc.update("UPDATE device SET token_hash=?, access_expires_at=?, last_seen_at=?, updated_at=? WHERE id=?",
                tokenHash, expiresAt.toString(), now.toString(), now.toString(), id);
    }

    public void touch(String id, Instant now) {
        jdbc.update("UPDATE device SET last_seen_at=?, updated_at=? WHERE id=?", now.toString(), now.toString(), id);
    }

    public void revoke(String id, Instant now) {
        jdbc.update("UPDATE device SET status='REVOKED', updated_at=? WHERE id=?", now.toString(), id);
    }

    public boolean exists(String id) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM device WHERE id=?", Integer.class, id);
        return count != null && count > 0;
    }

    private CurrentDevice mapCurrent(ResultSet rs, int row) throws SQLException {
        return new CurrentDevice(rs.getString("id"), rs.getString("label"), rs.getString("role"),
                Instant.parse(rs.getString("access_expires_at")));
    }
}

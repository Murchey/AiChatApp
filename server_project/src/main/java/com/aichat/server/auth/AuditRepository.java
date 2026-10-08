package com.aichat.server.auth;

import java.time.Instant;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class AuditRepository {
    private final JdbcTemplate jdbc;

    public AuditRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public void record(CurrentDevice actor, String action, String resourceType, String resourceId, String requestId) {
        jdbc.update("INSERT INTO admin_audit_log(id,actor_device_id,action,resource_type,resource_id,request_id,metadata_json,created_at) "
                        + "VALUES(?,?,?,?,?,?,?,?)",
                UUID.randomUUID().toString(), actor == null || "bootstrap".equals(actor.id()) ? null : actor.id(), action, resourceType, resourceId,
                requestId, "{}", Instant.now().toString());
    }
}

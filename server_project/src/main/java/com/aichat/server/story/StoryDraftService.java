package com.aichat.server.story;

import com.aichat.server.auth.AuditRepository;
import com.aichat.server.auth.CurrentDevice;
import com.aichat.server.common.ApiException;
import com.aichat.server.config.AppProperties;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Drafts remain separate from published versions, so editing never hides a live story. */
@Service
public class StoryDraftService {
    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;
    private final StoryValidator validator;
    private final StoryRepository stories;
    private final AuditRepository audit;
    private final AppProperties properties;

    public StoryDraftService(JdbcTemplate jdbc, ObjectMapper mapper, StoryValidator validator,
                             StoryRepository stories, AuditRepository audit, AppProperties properties) {
        this.jdbc = jdbc; this.mapper = mapper; this.validator = validator;
        this.stories = stories; this.audit = audit; this.properties = properties;
    }

    public record Draft(String storyId, int baseVersion, long revision, JsonNode document,
                        String status, Long validatedRevision, String createdAt, String updatedAt) {}

    public Draft get(String id) {
        requireEnabled();
        return jdbc.query("SELECT * FROM story_draft WHERE story_id=?", (rs, n) ->
            new Draft(rs.getString("story_id"), rs.getInt("base_version"), rs.getLong("revision"),
                parse(rs.getString("draft_json")), rs.getString("status"),
                rs.getObject("validated_revision") == null ? null : rs.getLong("validated_revision"),
                rs.getString("created_at"), rs.getString("updated_at")), id).stream().findFirst()
            .orElseThrow(() -> error(HttpStatus.NOT_FOUND, "NOT_FOUND", "草稿不存在"));
    }

    @Transactional
    public Draft create(JsonNode document, int baseVersion, CurrentDevice actor, String requestId) {
        requireEnabled();
        String id = document.path("storyId").asText();
        if (!id.matches("[A-Za-z0-9][A-Za-z0-9._-]{1,127}"))
            throw error(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "storyId 无效");
        checkSize(document);
        if (baseVersion != currentVersion(id)) throw conflict();
        if (jdbc.queryForObject("SELECT count(*) FROM story_draft WHERE story_id=?", Integer.class, id) > 0)
            throw error(HttpStatus.CONFLICT, "DRAFT_EXISTS", "草稿已存在，请读取当前修订后编辑");
        String now = Instant.now().toString();
        jdbc.update("INSERT INTO story_draft(story_id,base_version,draft_json,author_device_id,created_at,updated_at) VALUES(?,?,?,?,?,?)",
            id, baseVersion, document.toString(), actor.id(), now, now);
        audit.record(actor, "STORY_DRAFT_CREATED", "STORY", id, requestId);
        return get(id);
    }

    @Transactional
    public Draft update(String id, long revision, JsonNode document, CurrentDevice actor, String requestId) {
        Draft old = get(id);
        checkRevision(old, revision);
        if (!id.equals(document.path("storyId").asText()))
            throw error(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "storyId 不能改变");
        checkSize(document);
        if (old.status().equals("ARCHIVED")) throw error(HttpStatus.CONFLICT, "INVALID_STATE", "归档草稿不能编辑");
        int baseVersion = old.status().equals("PUBLISHED") ? currentVersion(id) : old.baseVersion();
        int changed = jdbc.update("UPDATE story_draft SET draft_json=?,base_version=?,revision=revision+1,status='DRAFT',validated_revision=NULL,updated_at=? WHERE story_id=? AND revision=?",
            document.toString(), baseVersion, Instant.now().toString(), id, revision);
        if (changed != 1) throw conflict();
        audit.record(actor, "STORY_DRAFT_UPDATED", "STORY", id, requestId);
        return get(id);
    }

    @Transactional
    public Draft validate(String id, long revision, CurrentDevice actor, String requestId) {
        Draft draft = get(id); checkRevision(draft, revision);
        validator.validate(draft.document());
        jdbc.update("UPDATE story_draft SET validated_revision=revision,updated_at=? WHERE story_id=? AND revision=?",
            Instant.now().toString(), id, revision);
        audit.record(actor, "STORY_DRAFT_VALIDATED", "STORY", id, requestId);
        return get(id);
    }

    @Transactional
    public Draft submit(String id, long revision, CurrentDevice actor, String requestId) {
        Draft draft = get(id); checkRevision(draft, revision);
        if (!draft.status().equals("DRAFT")) throw error(HttpStatus.CONFLICT, "INVALID_STATE", "仅草稿可提交审核");
        validator.validate(draft.document());
        jdbc.update("UPDATE story_draft SET status='PENDING_REVIEW',revision=revision+1,validated_revision=revision+1,updated_at=? WHERE story_id=? AND revision=?",
            Instant.now().toString(), id, revision);
        audit.record(actor, "STORY_SUBMITTED", "STORY", id, requestId);
        return get(id);
    }

    @Transactional
    public JsonNode publish(String id, long revision, int baseVersion, String key, CurrentDevice actor, String requestId) {
        requireEnabled();
        if (key == null || key.isBlank() || key.length() > 128)
            throw error(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "发布需要 Idempotency-Key（最多128字符）");
        String signature = id + ":" + revision + ":" + baseVersion;
        var previous = jdbc.query("SELECT request_hash,response_json FROM admin_publish_result WHERE actor_id=? AND idempotency_key=?",
            (rs, n) -> Map.entry(rs.getString(1), rs.getString(2)), actor.id(), key);
        if (!previous.isEmpty()) {
            if (!signature.equals(previous.getFirst().getKey())) throw conflict();
            return parse(previous.getFirst().getValue());
        }
        Draft draft = get(id); checkRevision(draft, revision);
        if (!draft.status().equals("PENDING_REVIEW")) throw error(HttpStatus.CONFLICT, "INVALID_STATE", "请先提交审核");
        if (baseVersion != draft.baseVersion() || baseVersion != currentVersion(id)) throw conflict();
        if (draft.document().path("version").asInt() != baseVersion + 1) throw conflict();
        validator.validate(draft.document());
        JsonNode result = mapper.valueToTree(stories.publish(draft.document()));
        jdbc.update("UPDATE story_draft SET status='PUBLISHED',revision=revision+1,updated_at=? WHERE story_id=? AND revision=?",
            Instant.now().toString(), id, revision);
        jdbc.update("INSERT INTO admin_publish_result(actor_id,idempotency_key,request_hash,response_json,created_at) VALUES(?,?,?,?,?)",
            actor.id(), key, signature, result.toString(), Instant.now().toString());
        audit.record(actor, "STORY_PUBLISHED", "STORY", id, requestId);
        return result;
    }

    @Transactional
    public Draft archive(String id, long revision, CurrentDevice actor, String requestId) {
        Draft draft = get(id); checkRevision(draft, revision);
        jdbc.update("UPDATE story SET status='ARCHIVED',updated_at=? WHERE id=?", Instant.now().toString(), id);
        jdbc.update("UPDATE story_draft SET status='ARCHIVED',revision=revision+1,updated_at=? WHERE story_id=? AND revision=?",
            Instant.now().toString(), id, revision);
        audit.record(actor, "STORY_ARCHIVED", "STORY", id, requestId);
        return get(id);
    }

    private int currentVersion(String id) {
        return jdbc.query("SELECT COALESCE(current_version,0) FROM story WHERE id=?", (rs, n) -> rs.getInt(1), id)
            .stream().findFirst().orElse(0);
    }
    private void checkRevision(Draft draft, long revision) { if (draft.revision() != revision) throw conflict(); }
    private void checkSize(JsonNode node) {
        if (node.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 1048576)
            throw error(HttpStatus.PAYLOAD_TOO_LARGE, "PAYLOAD_TOO_LARGE", "草稿不能超过1MB");
    }
    private void requireEnabled() {
        if (!properties.getFeatures().isAdminPublish() || !properties.getFeatures().isStories())
            throw error(HttpStatus.FORBIDDEN, "FEATURE_DISABLED", "管理员故事发布未启用");
    }
    private JsonNode parse(String json) {
        try { return mapper.readTree(json); }
        catch (Exception e) { throw error(HttpStatus.INTERNAL_SERVER_ERROR, "STORY_CORRUPT", "存储内容损坏"); }
    }
    private ApiException conflict() { return error(HttpStatus.CONFLICT, "VERSION_CONFLICT", "版本或修订已变化，请重新加载并合并"); }
    private ApiException error(HttpStatus status, String code, String message) { return new ApiException(status, code, message); }
}

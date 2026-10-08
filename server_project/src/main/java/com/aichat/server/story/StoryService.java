package com.aichat.server.story;

import com.aichat.server.auth.CurrentDevice;
import com.aichat.server.common.ApiException;
import com.aichat.server.config.AppProperties;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class StoryService {
    private final StoryRepository repository;
    private final StoryValidator validator;
    private final AppProperties properties;
    private final ObjectMapper mapper;
    private final JdbcTemplate jdbc;

    public StoryService(StoryRepository repository, StoryValidator validator, AppProperties properties,
                        ObjectMapper mapper, JdbcTemplate jdbc) {
        this.repository = repository;
        this.validator = validator;
        this.properties = properties;
        this.mapper = mapper;
        this.jdbc = jdbc;
    }

    public StoryPage list(String query, String tag, String cursor, int limit) {
        requireStories();
        return repository.page(query, tag, cursor, Math.max(1, Math.min(limit, 50)));
    }

    public JsonNode detail(String storyId, Integer version) {
        requireStories();
        String content = repository.content(storyId, version)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "STORY_NOT_FOUND", "故事不存在或尚未发布"));
        try { return mapper.readTree(content); }
        catch (JsonProcessingException exception) { throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "STORY_CORRUPT", "故事内容损坏"); }
    }

    @Transactional
    public JsonNode download(String storyId, Integer version, CurrentDevice device, String idempotencyKey) {
        requireStories();
        String deviceId = device == null ? null : device.id();
        if (idempotencyKey != null && !idempotencyKey.isBlank()) {
            Optional<String> previous = findIdempotent(storyId, deviceId, idempotencyKey.trim());
            if (previous.isPresent()) return parse(previous.get());
        }
        JsonNode packageJson = detail(storyId, version);
        repository.incrementDownload(storyId, version);
        if (idempotencyKey != null && !idempotencyKey.isBlank()) {
            String response = packageJson.toString();
            try {
                jdbc.update("INSERT INTO idempotency_record(id,device_id,route,idempotency_key,response_json,status_code,created_at,expires_at) "
                                + "VALUES(lower(hex(randomblob(16))),?,?,?,?,?,datetime('now'),datetime('now','+1 day'))",
                        deviceId, "/api/stories/" + storyId + "/download", idempotencyKey.trim(), response, 200);
            } catch (DuplicateKeyException ignored) {
                return findIdempotent(storyId, deviceId, idempotencyKey.trim()).map(this::parse).orElse(packageJson);
            }
        }
        return packageJson;
    }

    @Transactional
    public StoryCatalogEntry publish(JsonNode document) {
        requireStories();
        validator.validate(document);
        return repository.publish(document);
    }

    private Optional<String> findIdempotent(String storyId, String deviceId, String key) {
        return jdbc.query("SELECT response_json FROM idempotency_record WHERE route=? AND idempotency_key=? "
                        + "AND ((device_id=? ) OR (device_id IS NULL AND ? IS NULL)) AND expires_at>datetime('now')",
                (rs, row) -> rs.getString(1), "/api/stories/" + storyId + "/download", key, deviceId, deviceId).stream().findFirst();
    }

    private JsonNode parse(String json) {
        try { return mapper.readTree(json); }
        catch (JsonProcessingException exception) { throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "IDEMPOTENCY_CORRUPT", "幂等响应损坏"); }
    }

    private void requireStories() {
        if (!properties.getFeatures().isStories()) throw new ApiException(HttpStatus.NOT_FOUND, "FEATURE_DISABLED", "故事服务未启用");
    }
}

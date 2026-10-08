package com.aichat.server.story;

import com.aichat.server.common.ApiException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

@Repository
public class StoryRepository {
    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;
    private final CursorCodec cursors;

    public StoryRepository(JdbcTemplate jdbc, ObjectMapper mapper, CursorCodec cursors) {
        this.jdbc = jdbc;
        this.mapper = mapper;
        this.cursors = cursors;
    }

    public StoryPage page(String query, String tag, String cursor, int limit) {
        CursorCodec.Cursor decoded = cursors.decode(cursor);
        StringBuilder sql = new StringBuilder("SELECT s.id,s.title,s.author_name,s.summary,s.current_version,s.download_count,s.updated_at "
                + "FROM story s WHERE s.status='PUBLISHED'");
        List<Object> args = new ArrayList<>();
        if (query != null && !query.isBlank()) {
            sql.append(" AND (LOWER(s.title) LIKE ? OR LOWER(s.summary) LIKE ? OR EXISTS "
                    + "(SELECT 1 FROM story_tag sq WHERE sq.story_id=s.id AND LOWER(sq.tag) LIKE ?))");
            String like = "%" + query.trim().toLowerCase() + "%";
            args.add(like); args.add(like); args.add(like);
        }
        if (tag != null && !tag.isBlank()) {
            sql.append(" AND EXISTS (SELECT 1 FROM story_tag st WHERE st.story_id=s.id AND LOWER(st.tag)=?)");
            args.add(tag.trim().toLowerCase());
        }
        if (decoded != null) {
            sql.append(" AND (s.updated_at < ? OR (s.updated_at = ? AND s.id < ?))");
            args.add(decoded.updatedAt()); args.add(decoded.updatedAt()); args.add(decoded.id());
        }
        sql.append(" ORDER BY s.updated_at DESC,s.id DESC LIMIT ?");
        args.add(limit + 1);
        List<Row> rows = jdbc.query(sql.toString(), this::mapRow, args.toArray());
        boolean hasMore = rows.size() > limit;
        if (hasMore) rows = rows.subList(0, limit);
        List<StoryCatalogEntry> entries = rows.stream().map(row -> new StoryCatalogEntry(
                row.id, row.version, row.title, row.author, row.summary, tags(row.id),
                "stories/" + row.id + "/" + row.version + ".json", row.downloadCount, row.updatedAt)).toList();
        String next = hasMore && !rows.isEmpty() ? cursors.encode(rows.get(rows.size() - 1).updatedAt, rows.get(rows.size() - 1).id) : null;
        return new StoryPage(entries, next, hasMore);
    }

    public Optional<String> content(String storyId, Integer version) {
        if (version == null) {
            return jdbc.query("SELECT v.content_json FROM story s JOIN story_version v ON v.story_id=s.id AND v.version=s.current_version "
                            + "WHERE s.id=? AND s.status='PUBLISHED'", (rs, row) -> rs.getString(1), storyId).stream().findFirst();
        }
        return jdbc.query("SELECT v.content_json FROM story s JOIN story_version v ON v.story_id=s.id "
                        + "WHERE s.id=? AND v.version=? AND s.status='PUBLISHED'", (rs, row) -> rs.getString(1), storyId, version).stream().findFirst();
    }

    @Transactional
    public void incrementDownload(String storyId, Integer version) {
        jdbc.update("UPDATE story SET download_count=download_count+1, updated_at=updated_at WHERE id=? AND status='PUBLISHED'", storyId);
    }

    @Transactional
    public StoryCatalogEntry publish(JsonNode document) {
        String storyId = document.path("storyId").asText().trim();
        String title = document.path("title").asText().trim();
        String author = document.path("author").asText("").trim();
        String summary = document.path("summary").asText("").trim();
        int version = document.path("version").asInt(1);
        String content = document.toString();
        String hash = sha256(content);
        Instant now = Instant.now();
        String existingHash = jdbc.query("SELECT content_sha256 FROM story_version WHERE story_id=? AND version=?",
                (rs, row) -> rs.getString(1), storyId, version).stream().findFirst().orElse(null);
        if (existingHash != null && !existingHash.equals(hash)) {
            throw new ApiException(HttpStatus.CONFLICT, "VERSION_CONFLICT", "故事版本已存在且内容不同");
        }
        Integer currentVersion = jdbc.query("SELECT current_version FROM story WHERE id=?", (rs, row) -> rs.getInt(1), storyId)
                .stream().findFirst().orElse(null);
        if (currentVersion != null && version < currentVersion) {
            throw new ApiException(HttpStatus.CONFLICT, "VERSION_OLDER", "不能发布低于当前版本的故事");
        }
        jdbc.update("INSERT INTO story(id,slug,title,author_name,summary,status,current_version,download_count,created_at,updated_at) "
                        + "VALUES(?,?,?,?,?,'PUBLISHED',?,0,?,?) ON CONFLICT(slug) DO UPDATE SET title=excluded.title,author_name=excluded.author_name,summary=excluded.summary,status='PUBLISHED',current_version=excluded.current_version,updated_at=excluded.updated_at",
                storyId, storyId, title, author, summary, version, now.toString(), now.toString());
        if (existingHash == null) {
            jdbc.update("INSERT INTO story_version(id,story_id,version,content_json,content_sha256,content_size,schema_version,status,published_at,created_at) VALUES(?,?,?,?,?,?,1,'PUBLISHED',?,?)",
                    UUID.randomUUID().toString(), storyId, version, content, hash, content.getBytes(StandardCharsets.UTF_8).length,
                    now.toString(), now.toString());
        }
        jdbc.update("DELETE FROM story_tag WHERE story_id=?", storyId);
        JsonNode tags = document.path("tags");
        if (tags.isArray()) for (JsonNode tag : tags) {
            String value = tag.asText("").trim();
            if (!value.isEmpty()) jdbc.update("INSERT OR IGNORE INTO story_tag(story_id,tag) VALUES(?,?)", storyId, value);
        }
        return new StoryCatalogEntry(storyId, version, title, author, summary, tags(storyId),
                "stories/" + storyId + "/" + version + ".json", downloadCount(storyId), now.toString());
    }

    private Long downloadCount(String id) {
        return jdbc.queryForObject("SELECT download_count FROM story WHERE id=?", Long.class, id);
    }

    private List<String> tags(String storyId) {
        return jdbc.query("SELECT tag FROM story_tag WHERE story_id=? ORDER BY tag", (rs, row) -> rs.getString(1), storyId);
    }

    private Row mapRow(ResultSet rs, int row) throws SQLException {
        return new Row(rs.getString("id"), rs.getString("title"), rs.getString("author_name"), rs.getString("summary"),
                rs.getInt("current_version"), rs.getLong("download_count"), rs.getString("updated_at"));
    }

    private record Row(String id, String title, String author, String summary, int version, long downloadCount, String updatedAt) {}

    private String sha256(String value) {
        try { return java.util.HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8))); }
        catch (NoSuchAlgorithmException exception) { throw new IllegalStateException(exception); }
    }
}

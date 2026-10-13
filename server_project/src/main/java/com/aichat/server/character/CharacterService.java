package com.aichat.server.character;

import com.aichat.server.auth.AuditRepository;
import com.aichat.server.auth.CurrentDevice;
import com.aichat.server.common.ApiException;
import com.aichat.server.config.AppProperties;
import com.aichat.server.story.CursorCodec;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.Charset;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.*;
import java.util.zip.ZipInputStream;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class CharacterService {
    private final JdbcTemplate jdbc;
    private final CursorCodec cursors;
    private final ObjectMapper mapper;
    private final AppProperties properties;
    private final AuditRepository audit;
    public CharacterService(JdbcTemplate jdbc, CursorCodec cursors, ObjectMapper mapper, AppProperties properties, AuditRepository audit) {
        this.jdbc = jdbc; this.cursors = cursors; this.mapper = mapper; this.properties = properties; this.audit = audit;
    }
    public record Card(String characterId, String title, String author, String summary, int version, String updatedAt) {}
    public void enabled() {
        if (!properties.getFeatures().isCharacters()) throw error(HttpStatus.FORBIDDEN, "FEATURE_DISABLED", "角色卡服务未启用");
    }
    public Map<String,Object> list(String query, String cursor, int requested) {
        enabled(); int limit = Math.max(1, Math.min(requested, 50));
        String sql = "SELECT * FROM character_card WHERE 1=1";
        List<Object> args = new ArrayList<>();
        if (query != null && !query.isBlank()) { sql += " AND (instr(lower(title),lower(?))>0 OR instr(lower(summary),lower(?))>0)"; args.add(query.trim()); args.add(query.trim()); }
        var position = cursors.decode(cursor);
        if (position != null) { sql += " AND (updated_at<? OR (updated_at=? AND id<?))"; args.add(position.updatedAt()); args.add(position.updatedAt()); args.add(position.id()); }
        sql += " ORDER BY updated_at DESC,id DESC LIMIT ?"; args.add(limit+1);
        var rows = jdbc.query(sql, (rs,n) -> new Card(rs.getString("id"), rs.getString("title"), rs.getString("author_name"), rs.getString("summary"), rs.getInt("current_version"), rs.getString("updated_at")), args.toArray());
        boolean more = rows.size()>limit; if (more) rows=rows.subList(0,limit);
        Map<String,Object> result = new LinkedHashMap<>(); result.put("items",rows); result.put("hasMore",more);
        result.put("nextCursor", more ? cursors.encode(rows.getLast().updatedAt(), rows.getLast().characterId()) : null);
        return result;
    }
    public Card detail(String id) {
        enabled(); return jdbc.query("SELECT * FROM character_card WHERE id=?", (rs,n) -> new Card(rs.getString("id"),rs.getString("title"),rs.getString("author_name"),rs.getString("summary"),rs.getInt("current_version"),rs.getString("updated_at")),id).stream().findFirst().orElseThrow(() -> error(HttpStatus.NOT_FOUND,"CHARACTER_NOT_FOUND","角色卡不存在"));
    }
    public byte[] download(String id, Integer version) {
        Card card=detail(id);
        return jdbc.query("SELECT package_zip FROM character_version WHERE character_id=? AND version=?", (rs,n)->rs.getBytes(1),id,version==null?card.version():version).stream().findFirst().orElseThrow(() -> error(HttpStatus.NOT_FOUND,"CHARACTER_NOT_FOUND","角色卡版本不存在"));
    }
    @Transactional
    public Card publish(String id, String title, String author, String summary, int version, byte[] zip, CurrentDevice actor, String requestId) {
        enabled();
        if (!properties.getFeatures().isAdminPublish()) throw error(HttpStatus.FORBIDDEN,"FEATURE_DISABLED","内容发布未启用");
        if (!id.matches("[A-Za-z0-9][A-Za-z0-9._-]{1,127}") || title.isBlank() || title.length()>200 || author.length()>200 || summary.length()>2000 || version<1)
            throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","角色 ID、标题、作者、简介或版本无效");
        validateZip(zip);
        String hash;
        try { hash=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(zip)); } catch (Exception e) { throw new IllegalStateException(e); }
        var existing=jdbc.query("SELECT content_sha256 FROM character_version WHERE character_id=? AND version=?",(rs,n)->rs.getString(1),id,version);
        if (!existing.isEmpty()) {
            Card card=detail(id);
            if (card.version()==version && existing.getFirst().equals(hash) && card.title().equals(title.trim()) && card.author().equals(author.trim()) && card.summary().equals(summary.trim())) return card;
            throw error(HttpStatus.CONFLICT,"VERSION_CONFLICT","该版本已存在，请发布新版本");
        }
        int current=jdbc.query("SELECT current_version FROM character_card WHERE id=?",(rs,n)->rs.getInt(1),id).stream().findFirst().orElse(0);
        if (version!=current+1) throw error(HttpStatus.CONFLICT,"VERSION_CONFLICT","版本必须是当前版本加一");
        String now=Instant.now().toString();
        jdbc.update("INSERT INTO character_card(id,title,author_name,summary,current_version,created_at,updated_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,author_name=excluded.author_name,summary=excluded.summary,current_version=excluded.current_version,updated_at=excluded.updated_at",id,title.trim(),author.trim(),summary.trim(),version,now,now);
        jdbc.update("INSERT INTO character_version(character_id,version,package_zip,content_sha256,created_at) VALUES(?,?,?,?,?)",id,version,zip,hash,now);
        audit.record(actor,"CHARACTER_PUBLISHED","CHARACTER",id,requestId);
        return detail(id);
    }
    private void validateZip(byte[] bytes) {
        if (bytes.length==0 || bytes.length>4*1024*1024) throw error(HttpStatus.PAYLOAD_TOO_LARGE,"PAYLOAD_TOO_LARGE","角色包必须为1字节至4MB");
        int entries=0, profiles=0; long expanded=0;
        // GBK fallback handles legacy Windows ZIP names; UTF-8 flagged names still decode as UTF-8.
        try (var zip=new ZipInputStream(new ByteArrayInputStream(bytes),Charset.forName("GBK"))) {
            for (var entry=zip.getNextEntry(); entry!=null; entry=zip.getNextEntry()) {
                String name=entry.getName().replace('\\','/');
                if (++entries>2000 || name.startsWith("/") || name.matches("^[A-Za-z]:.*") || Arrays.asList(name.split("/")).contains("..")) throw new IOException("invalid path");
                boolean profile=!entry.isDirectory() && name.toLowerCase(Locale.ROOT).endsWith("/profile.json");
                var buffer=new java.io.ByteArrayOutputStream();
                byte[] chunk=new byte[8192]; int read;
                while ((read=zip.read(chunk))!=-1) {
                    expanded+=read; if (expanded>32L*1024*1024) throw new IOException("expanded package too large");
                    if (profile) { if (buffer.size()+read>1024*1024) throw new IOException("profile too large"); buffer.write(chunk,0,read); }
                }
                if (profile) { var json=mapper.readTree(buffer.toByteArray()); if (json==null || !json.isObject()) throw new IOException("invalid profile"); profiles++; }
            }
            if (profiles==0) throw new IOException("missing profile");
        } catch (IOException | IllegalArgumentException e) { throw error(HttpStatus.BAD_REQUEST,"CHARACTER_INVALID","ZIP 无效：需要角色目录中的 Profile.json，且解压大小不能超过32MB"); }
    }
    private ApiException error(HttpStatus status,String code,String message) { return new ApiException(status,code,message); }
}

package com.aichat.server.sync;

import com.aichat.server.auth.CurrentDevice;
import com.aichat.server.common.ApiException;
import com.aichat.server.config.AppProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Stores authenticated-encryption envelopes only; keys and plaintext never enter this service. */
@Service
public class EncryptedSyncService {
    private static final Set<String> DOMAINS=Set.of("settings","characters","conversations","messages","memories");
    private final JdbcTemplate jdbc;
    private final AppProperties properties;
    private final ObjectMapper mapper;
    private final SyncSpaceService spaces;
    public EncryptedSyncService(JdbcTemplate jdbc,AppProperties properties,ObjectMapper mapper,SyncSpaceService spaces) {
        this.jdbc=jdbc; this.properties=properties; this.mapper=mapper; this.spaces=spaces;
    }
    public record Upload(long baseRevision,String sha256,String ciphertext,String nonce,String algorithm) {}
    public record Stored(String domain,long revision,String sha256,String ciphertext,String nonce,String algorithm,String updatedAt) {}
    public record Receipt(String domain,long revision,String sha256,String updatedAt) {}
    public CurrentDevice require(CurrentDevice device) {
        if(!properties.getFeatures().isSync()) throw error(HttpStatus.FORBIDDEN,"FEATURE_DISABLED","同步未启用");
        if(device==null) throw error(HttpStatus.UNAUTHORIZED,"AUTH_REQUIRED","需要设备令牌");
        return device;
    }
    public Map<String,Object> manifest(CurrentDevice device) {
        require(device);
        return Map.of("items",jdbc.queryForList("SELECT domain,revision,content_sha256 AS sha256,updated_at AS updatedAt FROM sync_object WHERE device_id=? ORDER BY domain",device.id()),
            "scopes",jdbc.queryForList("SELECT domain,enabled FROM sync_scope WHERE device_id=? ORDER BY domain",device.id()),
            "serverTime",Instant.now().toString());
    }
    public Map<String,Object> manifest(CurrentDevice device,String spaceId) {
        if(spaceId==null||spaceId.isBlank())return manifest(device);
        spaces.requireMember(spaceId,device);
        return Map.of("items",jdbc.queryForList("SELECT domain,revision,content_sha256 AS sha256,updated_at AS updatedAt FROM sync_shared_object WHERE space_id=? ORDER BY domain",spaceId),
            "scopes",jdbc.queryForList("SELECT domain,enabled FROM sync_shared_scope WHERE space_id=? ORDER BY domain",spaceId),"spaceId",spaceId,"serverTime",Instant.now().toString());
    }
    @Transactional
    public void scope(CurrentDevice device,String domain,boolean enabled) {
        require(device); domain(domain);
        jdbc.update("INSERT INTO sync_scope(device_id,domain,enabled,updated_at) VALUES(?,?,?,?) ON CONFLICT(device_id,domain) DO UPDATE SET enabled=excluded.enabled,updated_at=excluded.updated_at",
            device.id(),domain,enabled?1:0,Instant.now().toString());
    }
    @Transactional public void scope(CurrentDevice device,String domain,boolean enabled,String spaceId){
        if(spaceId==null||spaceId.isBlank()){scope(device,domain,enabled);return;}
        spaces.requireMember(spaceId,device);domain(domain);
        jdbc.update("INSERT INTO sync_shared_scope(space_id,domain,enabled,updated_at) VALUES(?,?,?,?) ON CONFLICT(space_id,domain) DO UPDATE SET enabled=excluded.enabled,updated_at=excluded.updated_at",spaceId,domain,enabled?1:0,Instant.now().toString());
    }
    public Stored read(CurrentDevice device,String domain) {
        enabled(device,domain);
        return jdbc.query("SELECT * FROM sync_object WHERE device_id=? AND domain=?",(rs,n)->new Stored(domain,
            rs.getLong("revision"),rs.getString("content_sha256"),rs.getString("ciphertext"),rs.getString("nonce"),"AES-256-GCM",rs.getString("updated_at")),device.id(),domain)
            .stream().findFirst().orElseThrow(()->error(HttpStatus.NOT_FOUND,"NOT_FOUND","同步对象不存在"));
    }
    public Stored read(CurrentDevice device,String domain,String spaceId){
        if(spaceId==null||spaceId.isBlank())return read(device,domain);spaces.requireMember(spaceId,device);domain(domain);
        enabledShared(spaceId,domain);
        return jdbc.query("SELECT * FROM sync_shared_object WHERE space_id=? AND domain=?",(rs,n)->new Stored(domain,rs.getLong("revision"),rs.getString("content_sha256"),rs.getString("ciphertext"),rs.getString("nonce"),"AES-256-GCM",rs.getString("updated_at")),spaceId,domain).stream().findFirst().orElseThrow(()->error(HttpStatus.NOT_FOUND,"NOT_FOUND","同步对象不存在"));
    }
    @Transactional
    public Receipt upload(CurrentDevice device,String domain,Upload request,String key) {
        enabled(device,domain);
        if(key==null||key.isBlank()||key.length()>128) throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","需要 Idempotency-Key");
        if(request==null||request.baseRevision()<0||!"AES-256-GCM".equals(request.algorithm()))
            throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","加密算法或版本无效");
        byte[] bytes,nonce;
        try { bytes=Base64.getDecoder().decode(request.ciphertext());nonce=Base64.getDecoder().decode(request.nonce()); }
        catch(Exception e){throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","加密块必须为 Base64");}
        if(bytes.length>2*1024*1024) throw error(HttpStatus.PAYLOAD_TOO_LARGE,"PAYLOAD_TOO_LARGE","加密块不能超过2MB");
        if(bytes.length<16||nonce.length!=12||!hash(bytes).equals(request.sha256()))
            throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","加密块哈希、nonce 或认证标签长度无效");
        String signature=hash((domain+":"+request.baseRevision()+":"+request.sha256()+":"+request.nonce()).getBytes(StandardCharsets.UTF_8));
        var prior=jdbc.query("SELECT request_hash,response_json FROM sync_write_result WHERE device_id=? AND idempotency_key=?",
            (rs,n)->Map.entry(rs.getString(1),rs.getString(2)),device.id(),key);
        if(!prior.isEmpty()) {
            if(!signature.equals(prior.getFirst().getKey())) throw conflict();
            try{return mapper.readValue(prior.getFirst().getValue(),Receipt.class);}catch(Exception e){throw new IllegalStateException("stored receipt invalid",e);}
        }
        long current=jdbc.query("SELECT revision FROM sync_object WHERE device_id=? AND domain=?",(rs,n)->rs.getLong(1),device.id(),domain).stream().findFirst().orElse(0L);
        if(current!=request.baseRevision()) throw conflict();
        String now=Instant.now().toString();
        long revision=current+1;
        jdbc.update("INSERT INTO sync_object(device_id,domain,revision,content_sha256,ciphertext,nonce,updated_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(device_id,domain) DO UPDATE SET revision=excluded.revision,content_sha256=excluded.content_sha256,ciphertext=excluded.ciphertext,nonce=excluded.nonce,updated_at=excluded.updated_at",
            device.id(),domain,revision,request.sha256(),request.ciphertext(),request.nonce(),now);
        Receipt receipt=new Receipt(domain,revision,request.sha256(),now);
        try{jdbc.update("INSERT INTO sync_write_result(device_id,idempotency_key,request_hash,response_json,created_at) VALUES(?,?,?,?,?)",device.id(),key,signature,mapper.writeValueAsString(receipt),now);}
        catch(com.fasterxml.jackson.core.JsonProcessingException e){throw new IllegalStateException(e);}
        return receipt;
    }
    @Transactional public Receipt upload(CurrentDevice device,String domain,Upload request,String key,String spaceId){
        if(spaceId==null||spaceId.isBlank())return upload(device,domain,request,key);
        spaces.requireMember(spaceId,device);domain(domain);
        if(key==null||key.isBlank()||key.length()>128)throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","需要 Idempotency-Key");
        if(request==null)throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","加密算法或版本无效");
        byte[] bytes,nonce;try{bytes=Base64.getDecoder().decode(request.ciphertext());nonce=Base64.getDecoder().decode(request.nonce());}catch(Exception e){throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","加密块必须为 Base64");}
        validateUpload(request,bytes,nonce);
        String signature=hash((domain+":"+request.baseRevision()+":"+request.sha256()+":"+request.nonce()).getBytes(StandardCharsets.UTF_8));
        var prior=jdbc.query("SELECT request_hash,response_json FROM sync_shared_write_result WHERE space_id=? AND idempotency_key=?",(rs,n)->Map.entry(rs.getString(1),rs.getString(2)),spaceId,key);
        if(!prior.isEmpty()){if(!signature.equals(prior.getFirst().getKey()))throw conflict();try{return mapper.readValue(prior.getFirst().getValue(),Receipt.class);}catch(Exception e){throw new IllegalStateException(e);}}
        long current=jdbc.query("SELECT revision FROM sync_shared_object WHERE space_id=? AND domain=?",(rs,n)->rs.getLong(1),spaceId,domain).stream().findFirst().orElse(0L);
        if(current!=request.baseRevision())throw conflict();String now=Instant.now().toString();long revision=current+1;
        jdbc.update("INSERT INTO sync_shared_object(space_id,domain,revision,content_sha256,ciphertext,nonce,updated_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(space_id,domain) DO UPDATE SET revision=excluded.revision,content_sha256=excluded.content_sha256,ciphertext=excluded.ciphertext,nonce=excluded.nonce,updated_at=excluded.updated_at",spaceId,domain,revision,request.sha256(),request.ciphertext(),request.nonce(),now);
        Receipt receipt=new Receipt(domain,revision,request.sha256(),now);try{jdbc.update("INSERT INTO sync_shared_write_result(space_id,idempotency_key,request_hash,response_json,created_at) VALUES(?,?,?,?,?)",spaceId,key,signature,mapper.writeValueAsString(receipt),now);}catch(Exception e){throw new IllegalStateException(e);}return receipt;
    }
    private void enabled(CurrentDevice device,String domain) {
        require(device); domain(domain);
        int count=jdbc.queryForObject("SELECT count(*) FROM sync_scope WHERE device_id=? AND domain=? AND enabled=1",Integer.class,device.id(),domain);
        if(count!=1) throw error(HttpStatus.FORBIDDEN,"SYNC_SCOPE_DISABLED","请先显式开启该同步域");
    }
    private void enabledShared(String spaceId,String domain){int count=jdbc.queryForObject("SELECT count(*) FROM sync_shared_scope WHERE space_id=? AND domain=? AND enabled=1",Integer.class,spaceId,domain);if(count!=1)throw error(HttpStatus.FORBIDDEN,"SYNC_SCOPE_DISABLED","请先显式开启该同步域");}
    private void validateUpload(Upload request,byte[] bytes,byte[] nonce){
        if(request==null||request.baseRevision()<0||!"AES-256-GCM".equals(request.algorithm()))throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","加密算法或版本无效");
        if(bytes.length>2*1024*1024)throw error(HttpStatus.PAYLOAD_TOO_LARGE,"PAYLOAD_TOO_LARGE","加密块不能超过2MB");
        if(bytes.length<16||nonce.length!=12||!hash(bytes).equals(request.sha256()))throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","加密块哈希、nonce 或认证标签长度无效");
    }
    private void domain(String domain){if(!DOMAINS.contains(domain))throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","同步域不在白名单");}
    private String hash(byte[] bytes){try{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));}catch(Exception e){throw new IllegalStateException(e);}}
    private ApiException conflict(){return error(HttpStatus.CONFLICT,"VERSION_CONFLICT","同步版本已变化，请下载后合并");}
    private ApiException error(HttpStatus status,String code,String message){return new ApiException(status,code,message);}
}

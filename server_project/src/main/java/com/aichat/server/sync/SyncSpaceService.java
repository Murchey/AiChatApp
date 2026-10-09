package com.aichat.server.sync;

import com.aichat.server.auth.CurrentDevice;
import com.aichat.server.auth.SimpleRateLimiter;
import com.aichat.server.common.ApiException;
import com.aichat.server.config.AppProperties;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.time.*;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Shared namespace authorization. It never receives or derives the client encryption key. */
@Service
public class SyncSpaceService {
    private static final SecureRandom RANDOM=new SecureRandom();
    private final JdbcTemplate jdbc;
    private final AppProperties properties;
    private final SimpleRateLimiter limiter;
    public SyncSpaceService(JdbcTemplate jdbc,AppProperties properties,SimpleRateLimiter limiter){this.jdbc=jdbc;this.properties=properties;this.limiter=limiter;}
    public record Space(String spaceId,String role,String createdAt){}
    public record Created(Space space,String joinCode){}
    public record Join(String spaceId,String role,String createdAt){}
    public void requireFeature(){if(!properties.getFeatures().isSync())throw error(HttpStatus.FORBIDDEN,"FEATURE_DISABLED","同步未启用");}
    public CurrentDevice requireDevice(CurrentDevice device){requireFeature();if(device==null)throw error(HttpStatus.UNAUTHORIZED,"AUTH_REQUIRED","需要设备令牌");return device;}
    @Transactional
    public Created create(CurrentDevice device){
        requireDevice(device);limiter.check("sync-space-create:"+device.id(),5,3600);String id=UUID.randomUUID().toString();String now=Instant.now().toString();
        jdbc.update("INSERT INTO sync_space(id,owner_device_id,created_at) VALUES(?,?,?)",id,device.id(),now);
        jdbc.update("INSERT INTO sync_space_member(space_id,device_id,role,created_at) VALUES(?,?,?,?)",id,device.id(),"OWNER",now);
        String code=code();createInvite(id,code,10,24*7);return new Created(new Space(id,"OWNER",now),code);
    }
    @Transactional
    public String invite(String spaceId,CurrentDevice device){
        requireMember(spaceId,device,"OWNER");limiter.check("sync-space-invite:"+device.id(),20,3600);String code=code();createInvite(spaceId,code,1,24);return code;
    }
    private void createInvite(String spaceId,String code,int uses,int hours){
        jdbc.update("INSERT INTO sync_space_invite(id,space_id,code_hash,max_uses,expires_at,created_at) VALUES(?,?,?,?,?,?)",
            UUID.randomUUID().toString(),spaceId,hash(code),uses,Instant.now().plus(hours,java.time.temporal.ChronoUnit.HOURS).toString(),Instant.now().toString());
    }
    @Transactional
    public Join join(String code,CurrentDevice device){
        requireDevice(device);limiter.check("sync-space-join:"+device.id(),10,3600);if(code==null||code.length()>128)throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","加入码无效");
        var rows=jdbc.query("SELECT * FROM sync_space_invite WHERE code_hash=?",(rs,n)->new Object[]{rs.getString("id"),rs.getString("space_id"),rs.getInt("max_uses"),rs.getInt("used_count"),rs.getString("expires_at")},hash(code));
        if(rows.isEmpty())throw error(HttpStatus.NOT_FOUND,"INVITE_NOT_FOUND","加入码无效或已过期");var row=rows.getFirst();
        if((row[4]!=null&&Instant.parse(row[4].toString()).isBefore(Instant.now()))||((Integer)row[3])>=((Integer)row[2]))throw error(HttpStatus.GONE,"INVITE_EXPIRED","加入码已过期或用尽");
        String space=row[1].toString(),now=Instant.now().toString();
        jdbc.update("INSERT INTO sync_space_member(space_id,device_id,role,created_at) VALUES(?,?,?,?) ON CONFLICT(space_id,device_id) DO NOTHING",space,device.id(),"MEMBER",now);
        jdbc.update("UPDATE sync_space_invite SET used_count=used_count+1 WHERE id=? AND used_count<max_uses",row[0]);
        return new Join(space,"MEMBER",jdbc.queryForObject("SELECT created_at FROM sync_space WHERE id=?",String.class,space));
    }
    public List<Space> list(CurrentDevice device){requireDevice(device);return jdbc.query("SELECT s.id,m.role,s.created_at FROM sync_space s JOIN sync_space_member m ON m.space_id=s.id WHERE m.device_id=? ORDER BY s.created_at",(rs,n)->new Space(rs.getString(1),rs.getString(2),rs.getString(3)),device.id());}
    public String requireMember(String spaceId,CurrentDevice device,String requiredRole){
        requireDevice(device);if(spaceId==null||spaceId.isBlank()||spaceId.length()>64)throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","同步空间无效");
        String role=jdbc.query("SELECT role FROM sync_space_member WHERE space_id=? AND device_id=?",(rs,n)->rs.getString(1),spaceId,device.id()).stream().findFirst().orElseThrow(()->error(HttpStatus.FORBIDDEN,"SYNC_SPACE_FORBIDDEN","设备未加入同步空间"));
        if(requiredRole!=null&&!requiredRole.equals(role))throw error(HttpStatus.FORBIDDEN,"SYNC_SPACE_FORBIDDEN","需要空间所有者权限");return spaceId;
    }
    public void requireMember(String spaceId,CurrentDevice device){requireMember(spaceId,device,null);}
    private String code(){byte[] bytes=new byte[18];RANDOM.nextBytes(bytes);return "SYN-"+Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);}
    private String hash(String value){try{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));}catch(Exception e){throw new IllegalStateException(e);}}
    private ApiException error(HttpStatus status,String code,String message){return new ApiException(status,code,message);}
}

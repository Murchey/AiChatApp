package com.aichat.server.comment;

import com.aichat.server.auth.*;
import com.aichat.server.common.ApiException;
import com.aichat.server.config.AppProperties;
import com.aichat.server.story.CursorCodec;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.util.*;
import java.util.function.Supplier;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class CommentService {
    private final JdbcTemplate jdbc;
    private final AppProperties properties;
    private final CursorCodec cursors;
    private final ObjectMapper mapper;
    private final SimpleRateLimiter limiter;
    private final AuditRepository audit;
    public CommentService(JdbcTemplate jdbc,AppProperties properties,CursorCodec cursors,ObjectMapper mapper,SimpleRateLimiter limiter,AuditRepository audit){
        this.jdbc=jdbc;this.properties=properties;this.cursors=cursors;this.mapper=mapper;this.limiter=limiter;this.audit=audit;
    }
    public record Comment(String id,String storyId,int storyVersion,String parentId,String body,String status,String createdAt,String updatedAt) {}
    private record Row(Comment comment,String author,boolean publicVisibility) {}
    public void enabled(){if(!properties.getFeatures().isComments())throw error(HttpStatus.FORBIDDEN,"FEATURE_DISABLED","评论未启用");}
    private CurrentDevice authenticated(CurrentDevice device){enabled();if(device==null)throw error(HttpStatus.UNAUTHORIZED,"AUTH_REQUIRED","需要设备令牌");return device;}
    private int publishedVersion(String story){
        return jdbc.query("SELECT current_version FROM story WHERE id=? AND status='PUBLISHED'",(rs,n)->rs.getInt(1),story).stream().findFirst().orElseThrow(()->error(HttpStatus.NOT_FOUND,"NOT_FOUND","已发布故事不存在"));
    }
    public Map<String,Object> list(String story,String cursor,int requested){
        enabled();publishedVersion(story);int limit=Math.max(1,Math.min(requested,50));var position=cursors.decode(cursor);
        List<Object> args=new ArrayList<>();args.add(story);
        String sql="SELECT c.* FROM comment c WHERE c.story_id=? AND c.public_visibility=1 AND c.status IN ('VISIBLE','DELETED') AND (c.parent_id IS NULL OR EXISTS (SELECT 1 FROM comment p WHERE p.id=c.parent_id AND p.public_visibility=1 AND p.status IN ('VISIBLE','DELETED')))";
        if(position!=null){sql+=" AND (c.created_at<? OR (c.created_at=? AND c.id<?))";args.add(position.updatedAt());args.add(position.updatedAt());args.add(position.id());}
        sql+=" ORDER BY c.created_at DESC,c.id DESC LIMIT ?";args.add(limit+1);
        List<Comment> rows=jdbc.query(sql,(rs,n)->map(rs).comment(),args.toArray());boolean more=rows.size()>limit;
        if(more)rows=rows.subList(0,limit);
        Map<String,Object> result=new LinkedHashMap<>();result.put("items",rows);result.put("hasMore",more);
        result.put("nextCursor",more?cursors.encode(rows.getLast().createdAt(),rows.getLast().id()):null);
        return result;
    }
    @Transactional
    public Object create(String story,String parent,String body,String key,CurrentDevice device){
        authenticated(device);int version=publishedVersion(story);
        if(body==null||body.isBlank()||body.codePointCount(0,body.length())>2000||body.matches("(?s).*<[^>]+>.*"))throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","评论必须为1至2000字符纯文本");
        String normalized=body.trim();
        return once(device,key,"create:"+story+":"+parent+":"+normalized,()->{
            limiter.check("comment:"+device.id()+":"+story,10,60);
            if(parent!=null){
                Row target=find(parent);
                if(!target.comment().storyId().equals(story)||target.comment().parentId()!=null||!publiclyVisible(target))throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","只能回复本故事可见的一级评论");
            }
            String id=UUID.randomUUID().toString(),now=Instant.now().toString();
            jdbc.update("INSERT INTO comment(id,story_id,story_version,parent_id,author_device_id,body,status,created_at,updated_at) VALUES(?,?,?,?,?,?,'PENDING',?,?)",id,story,version,parent,device.id(),normalized,now,now);
            return find(id).comment();
        });
    }
    @Transactional
    public Comment delete(String id,CurrentDevice actor,String requestId){
        authenticated(actor);Row row=find(id);
        if(!actor.isAdmin()&&!row.author().equals(actor.id()))throw error(HttpStatus.FORBIDDEN,"FORBIDDEN","只能删除自己的评论");
        String now=Instant.now().toString();jdbc.update("UPDATE comment SET status='DELETED',deleted_at=?,updated_at=? WHERE id=?",now,now,id);
        if(actor.isAdmin())audit.record(actor,"COMMENT_DELETED","COMMENT",id,requestId);
        return find(id).comment();
    }
    @Transactional
    public Object report(String id,String reason,String key,CurrentDevice device){
        authenticated(device);Row row=find(id);publishedVersion(row.comment().storyId());
        if(!publiclyVisible(row))throw error(HttpStatus.NOT_FOUND,"NOT_FOUND","评论不可见");
        if(reason==null||!Set.of("SPAM","ABUSE","ILLEGAL","OTHER").contains(reason))throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","举报原因无效");
        return once(device,key,"report:"+id+":"+reason,()->{
            limiter.check("report:"+device.id(),10,60);
            var old=jdbc.query("SELECT id FROM report WHERE comment_id=? AND reporter_device_id=? AND status='PENDING'",(rs,n)->rs.getString(1),id,device.id());
            if(!old.isEmpty())return Map.of("id",old.getFirst(),"status","PENDING");
            String report=UUID.randomUUID().toString();
            jdbc.update("INSERT INTO report(id,comment_id,reporter_device_id,reason_code,status,created_at) VALUES(?,?,?,?,'PENDING',?)",report,id,device.id(),reason,Instant.now().toString());
            return Map.of("id",report,"status","PENDING");
        });
    }
    @Transactional
    public Comment moderate(String id,String status,CurrentDevice admin,String requestId){
        authenticated(admin);if(!admin.isAdmin())throw error(HttpStatus.FORBIDDEN,"FORBIDDEN","需要管理员权限");
        find(id);if(!Set.of("VISIBLE","HIDDEN","DELETED").contains(status==null?"":status))throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","审核状态无效");
        String now=Instant.now().toString();
        jdbc.update("UPDATE comment SET status=?,deleted_at=?,updated_at=? WHERE id=?",status,"DELETED".equals(status)?now:null,now,id);
        if(!"DELETED".equals(status))jdbc.update("UPDATE comment SET public_visibility=? WHERE id=?","VISIBLE".equals(status)?1:0,id);
        jdbc.update("UPDATE report SET status='RESOLVED' WHERE comment_id=? AND status='PENDING'",id);
        audit.record(admin,"COMMENT_"+status,"COMMENT",id,requestId);return find(id).comment();
    }
    public Map<String,Object> reviewQueue(String status,String cursor,int requested){
        enabled();if(!Set.of("PENDING","VISIBLE","HIDDEN","DELETED").contains(status))throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","审核状态无效");
        int limit=Math.max(1,Math.min(requested,50));var position=cursors.decode(cursor);List<Object> args=new ArrayList<>();args.add(status);
        String sql="SELECT * FROM comment WHERE status=?";
        if(position!=null){sql+=" AND (created_at<? OR (created_at=? AND id<?))";args.add(position.updatedAt());args.add(position.updatedAt());args.add(position.id());}
        sql+=" ORDER BY created_at DESC,id DESC LIMIT ?";args.add(limit+1);
        var rows=jdbc.query(sql,(rs,n)->map(rs).comment(),args.toArray());boolean more=rows.size()>limit;if(more)rows=rows.subList(0,limit);
        Map<String,Object> result=new LinkedHashMap<>();result.put("items",rows);result.put("hasMore",more);result.put("nextCursor",more?cursors.encode(rows.getLast().createdAt(),rows.getLast().id()):null);return result;
    }
    public Map<String,Object> reports(String id,String cursor,int requested){
        enabled();find(id);int limit=Math.max(1,Math.min(requested,50));var position=cursors.decode(cursor);
        List<Object> args=new ArrayList<>();args.add(id);
        String sql="SELECT id,reason_code,status,created_at FROM report WHERE comment_id=?";
        if(position!=null){sql+=" AND (created_at<? OR (created_at=? AND id<?))";args.add(position.updatedAt());args.add(position.updatedAt());args.add(position.id());}
        sql+=" ORDER BY created_at DESC,id DESC LIMIT ?";args.add(limit+1);
        var rows=jdbc.queryForList(sql,args.toArray());boolean more=rows.size()>limit;if(more)rows=rows.subList(0,limit);
        Map<String,Object> result=new LinkedHashMap<>();result.put("items",rows);result.put("hasMore",more);
        result.put("nextCursor",more?cursors.encode(rows.getLast().get("created_at").toString(),rows.getLast().get("id").toString()):null);return result;
    }
    public String storyForReply(String id){enabled();return find(id).comment().storyId();}
    private Row find(String id){return jdbc.query("SELECT * FROM comment WHERE id=?",(rs,n)->map(rs),id).stream().findFirst().orElseThrow(()->error(HttpStatus.NOT_FOUND,"NOT_FOUND","评论不存在"));}
    private Row map(java.sql.ResultSet rs)throws java.sql.SQLException{
        String status=rs.getString("status");return new Row(new Comment(rs.getString("id"),rs.getString("story_id"),rs.getInt("story_version"),rs.getString("parent_id"),"DELETED".equals(status)?"评论已删除":rs.getString("body"),status,rs.getString("created_at"),rs.getString("updated_at")),rs.getString("author_device_id"),rs.getInt("public_visibility")==1);
    }
    private boolean publiclyVisible(Row row){
        if(!row.publicVisibility()||!Set.of("VISIBLE","DELETED").contains(row.comment().status()))return false;
        return row.comment().parentId()==null||publiclyVisible(find(row.comment().parentId()));
    }
    private Object once(CurrentDevice device,String key,String signature,Supplier<Object> action){
        if(key==null||key.isBlank()||key.length()>128)throw error(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","需要 Idempotency-Key");
        String hash;try{hash=java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(signature.getBytes(java.nio.charset.StandardCharsets.UTF_8)));}catch(Exception e){throw new IllegalStateException(e);}
        var previous=jdbc.query("SELECT signature,response_json FROM comment_request_result WHERE device_id=? AND idempotency_key=?",(rs,n)->Map.entry(rs.getString(1),rs.getString(2)),device.id(),key);
        if(!previous.isEmpty()){
            if(!hash.equals(previous.getFirst().getKey()))throw error(HttpStatus.CONFLICT,"IDEMPOTENCY_CONFLICT","幂等键已用于其他请求");
            try{return mapper.readTree(previous.getFirst().getValue());}catch(Exception e){throw new IllegalStateException(e);}
        }
        Object result=action.get();
        try{jdbc.update("INSERT INTO comment_request_result(device_id,idempotency_key,signature,response_json,created_at) VALUES(?,?,?,?,?)",device.id(),key,hash,mapper.writeValueAsString(result),Instant.now().toString());}catch(com.fasterxml.jackson.core.JsonProcessingException e){throw new IllegalStateException(e);}
        return result;
    }
    private ApiException error(HttpStatus status,String code,String message){return new ApiException(status,code,message);}
}

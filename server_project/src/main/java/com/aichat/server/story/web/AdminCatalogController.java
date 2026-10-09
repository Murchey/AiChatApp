package com.aichat.server.story.web;

import com.aichat.server.auth.AdminAuthService;
import com.aichat.server.common.ApiResponse;
import com.aichat.server.common.RequestIdFilter;
import com.aichat.server.story.CursorCodec;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/admin")
public class AdminCatalogController {
    private final AdminAuthService auth;
    private final JdbcTemplate jdbc;
    private final CursorCodec cursors;
    public AdminCatalogController(AdminAuthService auth, JdbcTemplate jdbc, CursorCodec cursors) {
        this.auth=auth; this.jdbc=jdbc; this.cursors=cursors;
    }
    @GetMapping("/stories")
    public ApiResponse<?> drafts(@RequestParam(required=false) String cursor,
                                @RequestParam(defaultValue="20") int limit, HttpServletRequest req) {
        auth.requireAdmin(req);
        return new ApiResponse<>(page("story_draft", "story_id", "updated_at",
            "story_id,base_version,revision,status,created_at,updated_at", cursor, limit), RequestIdFilter.from(req));
    }
    @GetMapping("/audit-logs")
    public ApiResponse<?> audit(@RequestParam(required=false) String cursor,
                               @RequestParam(defaultValue="20") int limit, HttpServletRequest req) {
        auth.requireAdmin(req);
        return new ApiResponse<>(page("admin_audit_log", "id", "created_at",
            "id,actor_device_id,action,resource_type,resource_id,request_id,created_at", cursor, limit), RequestIdFilter.from(req));
    }
    private Map<String,Object> page(String table,String id,String time,String columns,String cursor,int requested) {
        int limit=Math.max(1,Math.min(requested,50));
        var position=cursors.decode(cursor);
        List<Object> args=new ArrayList<>();
        String sql="SELECT "+columns+" FROM "+table;
        if(position!=null) {
            sql+=" WHERE ("+time+"<? OR ("+time+"=? AND "+id+"<?))";
            args.add(position.updatedAt()); args.add(position.updatedAt()); args.add(position.id());
        }
        sql+=" ORDER BY "+time+" DESC,"+id+" DESC LIMIT ?"; args.add(limit+1);
        var rows=jdbc.queryForList(sql,args.toArray());
        boolean more=rows.size()>limit;
        if(more) rows=rows.subList(0,limit);
        Map<String,Object> result=new LinkedHashMap<>();
        result.put("items",rows); result.put("hasMore",more);
        var last=rows.isEmpty()?null:rows.getLast();
        result.put("nextCursor",more?cursors.encode(last.get(time).toString(),last.get(id).toString()):null);
        return result;
    }
}

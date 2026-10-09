package com.aichat.server.comment;

import com.aichat.server.auth.*;
import com.aichat.server.common.*;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api")
public class CommentController {
    private final CommentService service;
    private final AdminAuthService admin;
    public CommentController(CommentService service,AdminAuthService admin){this.service=service;this.admin=admin;}
    public record Body(String body) {}
    public record Report(String reasonCode) {}
    public record Moderation(String status) {}
    @GetMapping("/stories/{id}/comments") public ApiResponse<?> list(@PathVariable String id,@RequestParam(required=false) String cursor,@RequestParam(defaultValue="20") int limit,HttpServletRequest req){return wrap(service.list(id,cursor,limit),req);}
    @PostMapping("/stories/{id}/comments") public ApiResponse<?> create(@PathVariable String id,@RequestBody Body body,@RequestHeader(value="Idempotency-Key",required=false) String key,HttpServletRequest req){return wrap(service.create(id,null,body.body(),key,device(req)),req);}
    @PostMapping("/comments/{id}/replies") public ApiResponse<?> reply(@PathVariable String id,@RequestBody Body body,@RequestHeader(value="Idempotency-Key",required=false) String key,HttpServletRequest req){return wrap(service.create(service.storyForReply(id),id,body.body(),key,device(req)),req);}
    @DeleteMapping("/comments/{id}") public ApiResponse<?> delete(@PathVariable String id,HttpServletRequest req){CurrentDevice actor=device(req);if(req.getHeader("X-Admin-Token")!=null)actor=admin.requireAdmin(req);return wrap(service.delete(id,actor,RequestIdFilter.from(req)),req);}
    @PostMapping("/comments/{id}/reports") public ApiResponse<?> report(@PathVariable String id,@RequestBody Report body,@RequestHeader(value="Idempotency-Key",required=false) String key,HttpServletRequest req){return wrap(service.report(id,body.reasonCode(),key,device(req)),req);}
    @PostMapping("/admin/comments/{id}/moderate") public ApiResponse<?> moderate(@PathVariable String id,@RequestBody Moderation body,HttpServletRequest req){return wrap(service.moderate(id,body.status(),admin.requireAdmin(req),RequestIdFilter.from(req)),req);}
    @GetMapping("/admin/comments") public ApiResponse<?> queue(@RequestParam(defaultValue="PENDING") String status,@RequestParam(required=false) String cursor,@RequestParam(defaultValue="20") int limit,HttpServletRequest req){admin.requireAdmin(req);return wrap(service.reviewQueue(status,cursor,limit),req);}
    @GetMapping("/admin/comments/{id}/reports") public ApiResponse<?> reports(@PathVariable String id,@RequestParam(required=false) String cursor,@RequestParam(defaultValue="20") int limit,HttpServletRequest req){admin.requireAdmin(req);return wrap(service.reports(id,cursor,limit),req);}
    private CurrentDevice device(HttpServletRequest req){Object value=req.getAttribute(CurrentDevice.REQUEST_ATTRIBUTE);return value instanceof CurrentDevice device?device:null;}
    private ApiResponse<?> wrap(Object data,HttpServletRequest req){return new ApiResponse<>(data,RequestIdFilter.from(req));}
}

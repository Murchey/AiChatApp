package com.aichat.server.sync;

import com.aichat.server.auth.CurrentDevice;
import com.aichat.server.common.ApiResponse;
import com.aichat.server.common.RequestIdFilter;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/sync")
public class SyncController {
    private final EncryptedSyncService service;
    public SyncController(EncryptedSyncService service){this.service=service;}
    public record Scope(boolean enabled) {}
    public record Resolution(String domain,EncryptedSyncService.Upload object) {}
    private CurrentDevice device(HttpServletRequest req){
        Object value=req.getAttribute(CurrentDevice.REQUEST_ATTRIBUTE);
        return value instanceof CurrentDevice device?device:null;
    }
    @GetMapping("/manifest")
    public ApiResponse<?> manifest(@RequestHeader(value="X-Sync-Space",required=false) String space,HttpServletRequest req){return new ApiResponse<>(service.manifest(device(req),space),RequestIdFilter.from(req));}
    @PutMapping("/scopes/{domain}")
    public ApiResponse<?> scope(@PathVariable String domain,@RequestBody Scope body,@RequestHeader(value="X-Sync-Space",required=false) String space,HttpServletRequest req){
        service.scope(device(req),domain,body.enabled(),space);
        return new ApiResponse<>(body,RequestIdFilter.from(req));
    }
    @GetMapping("/objects/{domain}")
    public ApiResponse<?> read(@PathVariable String domain,@RequestHeader(value="X-Sync-Space",required=false) String space,HttpServletRequest req){return new ApiResponse<>(service.read(device(req),domain,space),RequestIdFilter.from(req));}
    @PutMapping("/objects/{domain}")
    public ApiResponse<?> upload(@PathVariable String domain,@RequestBody EncryptedSyncService.Upload body,
        @RequestHeader(value="Idempotency-Key",required=false) String key,@RequestHeader(value="X-Sync-Space",required=false) String space,HttpServletRequest req){
        return new ApiResponse<>(service.upload(device(req),domain,body,key,space),RequestIdFilter.from(req));
    }
    @PostMapping("/resolve")
    public ApiResponse<?> resolve(@RequestBody Resolution body,@RequestHeader(value="Idempotency-Key",required=false) String key,HttpServletRequest req){
        return new ApiResponse<>(service.upload(device(req),body.domain(),body.object(),key),RequestIdFilter.from(req));
    }
}

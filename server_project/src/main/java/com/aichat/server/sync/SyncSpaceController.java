package com.aichat.server.sync;
import com.aichat.server.auth.CurrentDevice;
import com.aichat.server.common.*;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;

@RestController @RequestMapping("/api/sync/spaces")
public class SyncSpaceController {
    private final SyncSpaceService service;
    public SyncSpaceController(SyncSpaceService service){this.service=service;}
    public record Join(String code){}
    private CurrentDevice device(HttpServletRequest req){Object value=req.getAttribute(CurrentDevice.REQUEST_ATTRIBUTE);return value instanceof CurrentDevice d?d:null;}
    @PostMapping public ApiResponse<?> create(HttpServletRequest req){return wrap(service.create(device(req)),req);}
    @GetMapping public ApiResponse<?> list(HttpServletRequest req){return wrap(service.list(device(req)),req);}
    @PostMapping("/{id}/invites") public ApiResponse<?> invite(@PathVariable String id,HttpServletRequest req){return wrap(java.util.Map.of("joinCode",service.invite(id,device(req))),req);}
    @PostMapping("/join") public ApiResponse<?> join(@RequestBody Join body,HttpServletRequest req){return wrap(service.join(body.code(),device(req)),req);}
    private ApiResponse<?> wrap(Object data,HttpServletRequest req){return new ApiResponse<>(data,RequestIdFilter.from(req));}
}

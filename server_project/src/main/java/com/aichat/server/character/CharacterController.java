package com.aichat.server.character;

import com.aichat.server.auth.AdminAuthService;
import com.aichat.server.common.ApiResponse;
import com.aichat.server.common.RequestIdFilter;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api")
public class CharacterController {
    private final CharacterService service;
    private final AdminAuthService admin;
    public CharacterController(CharacterService service, AdminAuthService admin) { this.service=service; this.admin=admin; }
    @GetMapping("/characters")
    public ApiResponse<?> list(@RequestParam(required=false) String q, @RequestParam(required=false) String cursor, @RequestParam(defaultValue="20") int limit, HttpServletRequest request) {
        return new ApiResponse<>(service.list(q,cursor,limit),RequestIdFilter.from(request));
    }
    @GetMapping("/characters/{id}")
    public ApiResponse<?> detail(@PathVariable String id,HttpServletRequest request) { return new ApiResponse<>(service.detail(id),RequestIdFilter.from(request)); }
    @GetMapping("/characters/{id}/download")
    public ResponseEntity<byte[]> download(@PathVariable String id,@RequestParam(required=false) Integer version) {
        return ResponseEntity.ok().contentType(MediaType.parseMediaType("application/zip"))
            .header(HttpHeaders.CONTENT_DISPOSITION,ContentDisposition.attachment().filename("character.zip").build().toString()).body(service.download(id,version));
    }
    @PostMapping(value="/admin/characters",consumes="application/zip")
    public ApiResponse<?> publish(@RequestParam String characterId,@RequestParam String title,@RequestParam(defaultValue="") String author,@RequestParam(defaultValue="") String summary,@RequestParam int version,@RequestBody byte[] bytes,HttpServletRequest request) {
        var actor=admin.requireAdmin(request);
        return new ApiResponse<>(service.publish(characterId,title,author,summary,version,bytes,actor,RequestIdFilter.from(request)),RequestIdFilter.from(request));
    }
}

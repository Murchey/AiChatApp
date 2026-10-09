package com.aichat.server.story.web;

import com.aichat.server.auth.AdminAuthService;
import com.aichat.server.common.ApiResponse;
import com.aichat.server.common.RequestIdFilter;
import com.aichat.server.story.StoryDraftService;
import com.fasterxml.jackson.databind.JsonNode;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/admin/stories")
public class AdminStoryDraftController {
    private final AdminAuthService auth;
    private final StoryDraftService drafts;
    public AdminStoryDraftController(AdminAuthService auth, StoryDraftService drafts) {
        this.auth = auth; this.drafts = drafts;
    }
    public record Create(@NotNull JsonNode document, @Min(0) int baseVersion) {}
    public record Update(@NotNull JsonNode document, @Min(1) long revision) {}
    public record Revision(@Min(1) long revision) {}
    public record Publish(@Min(1) long revision, @Min(0) int baseVersion) {}

    @PostMapping
    public ApiResponse<?> create(@Valid @RequestBody Create body, HttpServletRequest req) {
        return new ApiResponse<>(drafts.create(body.document(), body.baseVersion(), auth.requireAdmin(req), RequestIdFilter.from(req)), RequestIdFilter.from(req));
    }
    @GetMapping("/{id}/draft")
    public ApiResponse<?> get(@PathVariable String id, HttpServletRequest req) {
        auth.requireAdmin(req);
        return new ApiResponse<>(drafts.get(id), RequestIdFilter.from(req));
    }
    @PutMapping("/{id}/draft")
    public ApiResponse<?> update(@PathVariable String id, @Valid @RequestBody Update body, HttpServletRequest req) {
        return new ApiResponse<>(drafts.update(id, body.revision(), body.document(), auth.requireAdmin(req), RequestIdFilter.from(req)), RequestIdFilter.from(req));
    }
    @PostMapping("/{id}/validate")
    public ApiResponse<?> validate(@PathVariable String id, @Valid @RequestBody Revision body, HttpServletRequest req) {
        return new ApiResponse<>(drafts.validate(id, body.revision(), auth.requireAdmin(req), RequestIdFilter.from(req)), RequestIdFilter.from(req));
    }
    @PostMapping("/{id}/submit")
    public ApiResponse<?> submit(@PathVariable String id, @Valid @RequestBody Revision body, HttpServletRequest req) {
        return new ApiResponse<>(drafts.submit(id, body.revision(), auth.requireAdmin(req), RequestIdFilter.from(req)), RequestIdFilter.from(req));
    }
    @PostMapping("/{id}/publish")
    public ApiResponse<?> publish(@PathVariable String id, @Valid @RequestBody Publish body,
                                 @RequestHeader(value="Idempotency-Key", required=false) String key, HttpServletRequest req) {
        return new ApiResponse<>(drafts.publish(id, body.revision(), body.baseVersion(), key, auth.requireAdmin(req), RequestIdFilter.from(req)), RequestIdFilter.from(req));
    }
    @PostMapping("/{id}/archive")
    public ApiResponse<?> archive(@PathVariable String id, @Valid @RequestBody Revision body, HttpServletRequest req) {
        return new ApiResponse<>(drafts.archive(id, body.revision(), auth.requireAdmin(req), RequestIdFilter.from(req)), RequestIdFilter.from(req));
    }
}

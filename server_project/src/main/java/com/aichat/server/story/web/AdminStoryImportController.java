package com.aichat.server.story.web;

import com.aichat.server.auth.AdminAuthService;
import com.aichat.server.auth.AuditRepository;
import com.aichat.server.auth.CurrentDevice;
import com.aichat.server.common.ApiResponse;
import com.aichat.server.common.RequestIdFilter;
import com.aichat.server.story.StoryCatalogEntry;
import com.aichat.server.story.StoryService;
import com.fasterxml.jackson.databind.JsonNode;
import jakarta.servlet.http.HttpServletRequest;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/admin/stories")
public class AdminStoryImportController {
    private final AdminAuthService admin;
    private final StoryService stories;
    private final AuditRepository audit;

    public AdminStoryImportController(AdminAuthService admin, StoryService stories, AuditRepository audit) {
        this.admin = admin;
        this.stories = stories;
        this.audit = audit;
    }

    @PostMapping("/publish")
    public ApiResponse<Map<String, Object>> publish(@RequestBody JsonNode document, HttpServletRequest request) {
        CurrentDevice actor = admin.requireAdmin(request);
        StoryCatalogEntry entry = stories.publish(document);
        audit.record(actor, "STORY_PUBLISHED", "STORY", entry.storyId(), RequestIdFilter.from(request));
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("story", entry);
        data.put("status", "PUBLISHED");
        return new ApiResponse<>(data, RequestIdFilter.from(request));
    }
}

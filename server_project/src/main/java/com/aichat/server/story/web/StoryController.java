package com.aichat.server.story.web;

import com.aichat.server.auth.CurrentDevice;
import com.aichat.server.common.ApiException;
import com.aichat.server.common.RequestIdFilter;
import com.aichat.server.story.StoryCatalogEntry;
import com.aichat.server.story.StoryPage;
import com.aichat.server.story.StoryService;
import com.fasterxml.jackson.databind.JsonNode;
import jakarta.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/stories")
public class StoryController {
    private final StoryService stories;

    public StoryController(StoryService stories) {
        this.stories = stories;
    }

    @GetMapping
    public Map<String, Object> list(@RequestParam(required = false) String q,
                                    @RequestParam(required = false) String tag,
                                    @RequestParam(required = false) String cursor,
                                    @RequestParam(defaultValue = "20") int limit,
                                    HttpServletRequest request) {
        StoryPage page = stories.list(q, tag, cursor, limit);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("stories", page.items().stream().map(this::entryJson).toList());
        body.put("nextCursor", page.nextCursor());
        body.put("hasMore", page.hasMore());
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("items", body.get("stories"));
        data.put("nextCursor", page.nextCursor());
        data.put("hasMore", page.hasMore());
        body.put("data", data);
        body.put("requestId", RequestIdFilter.from(request));
        return body;
    }

    @GetMapping("/{storyId}")
    public JsonNode detail(@PathVariable String storyId,
                           @RequestParam(required = false) Integer version) {
        return stories.detail(storyId, version);
    }

    @GetMapping("/{storyId}/versions/{version}")
    public JsonNode version(@PathVariable String storyId, @PathVariable int version) {
        return stories.detail(storyId, version);
    }

    @GetMapping("/{storyId}/download")
    public JsonNode download(@PathVariable String storyId,
                             @RequestParam(required = false) Integer version,
                             @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
                             HttpServletRequest request) {
        Object current = request.getAttribute(CurrentDevice.REQUEST_ATTRIBUTE);
        CurrentDevice device = current instanceof CurrentDevice value ? value : null;
        return stories.download(storyId, version, device, idempotencyKey);
    }

    private Map<String, Object> entryJson(StoryCatalogEntry entry) {
        Map<String, Object> value = new LinkedHashMap<>();
        value.put("storyId", entry.storyId());
        value.put("version", entry.version());
        value.put("title", entry.title());
        value.put("author", entry.author());
        value.put("summary", entry.summary());
        value.put("tags", entry.tags());
        value.put("file", entry.file());
        if (entry.downloadCount() != null) value.put("downloadCount", entry.downloadCount());
        return value;
    }
}

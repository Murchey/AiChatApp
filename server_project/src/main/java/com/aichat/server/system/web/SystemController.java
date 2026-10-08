package com.aichat.server.system.web;

import com.aichat.server.common.ApiResponse;
import com.aichat.server.common.RequestIdFilter;
import com.aichat.server.config.AppProperties;
import java.time.Clock;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class SystemController {
    private final AppProperties properties;
    private final Clock clock = Clock.systemUTC();

    public SystemController(AppProperties properties) {
        this.properties = properties;
    }

    @GetMapping("/health")
    public ApiResponse<Map<String, Object>> health(jakarta.servlet.http.HttpServletRequest request) {
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("status", "UP");
        data.put("service", "aichat-backend");
        data.put("timestamp", Instant.now(clock));
        return new ApiResponse<>(data, RequestIdFilter.from(request));
    }

    @GetMapping("/version")
    public ApiResponse<Map<String, Object>> version(jakarta.servlet.http.HttpServletRequest request) {
        Map<String, Object> features = new LinkedHashMap<>();
        features.put("stories", properties.getFeatures().isStories());
        features.put("sync", properties.getFeatures().isSync());
        features.put("comments", properties.getFeatures().isComments());
        features.put("adminPublish", properties.getFeatures().isAdminPublish());
        features.put("llmRelay", properties.getFeatures().isLlmRelay());

        Map<String, Object> data = new LinkedHashMap<>();
        data.put("serverVersion", properties.getServerVersion());
        data.put("apiVersion", properties.getApiVersion());
        data.put("minClientVersion", properties.getMinClientVersion());
        data.put("features", features);
        return new ApiResponse<>(data, RequestIdFilter.from(request));
    }
}

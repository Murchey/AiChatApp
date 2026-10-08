package com.aichat.server.story;

import com.aichat.server.common.ApiErrorResponse;
import com.aichat.server.common.ApiException;
import com.fasterxml.jackson.databind.JsonNode;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
public class StoryValidator {
    public void validate(JsonNode root) {
        List<ApiErrorResponse.ErrorDetail> errors = new ArrayList<>();
        if (root == null || !root.isObject()) {
            throw invalid(List.of(new ApiErrorResponse.ErrorDetail("$", "必须是 JSON 对象")));
        }
        int schema = root.path("schemaVersion").asInt(-1);
        if (schema != 1) errors.add(error("schemaVersion", "只支持 schemaVersion=1"));
        int version = root.path("version").asInt(0);
        if (version < 1) errors.add(error("version", "版本号必须是正整数"));
        String storyId = text(root, "storyId");
        if (storyId == null || !storyId.matches("[A-Za-z0-9][A-Za-z0-9._-]{1,127}")) {
            errors.add(error("storyId", "必须是 2-128 位字母、数字、点、下划线或短横线"));
        }
        requiredText(root, "title", 1, 200, errors);
        requiredText(root, "summary", 0, 2000, errors);
        JsonNode tags = root.path("tags");
        if (!tags.isMissingNode() && !tags.isArray()) errors.add(error("tags", "必须是数组"));
        if (tags.isArray() && tags.size() > 20) errors.add(error("tags", "最多 20 个标签"));
        Set<String> tagSet = new HashSet<>();
        if (tags.isArray()) for (int i = 0; i < tags.size(); i++) {
            String tag = tags.get(i).asText("").trim();
            if (tag.isEmpty() || tag.length() > 40) errors.add(error("tags[" + i + "]", "标签长度必须为 1-40"));
            if (!tagSet.add(tag.toLowerCase())) errors.add(error("tags[" + i + "]", "标签不能重复"));
        }
        JsonNode chapters = root.path("chapters");
        if (!chapters.isArray() || chapters.isEmpty() || chapters.size() > 100) {
            errors.add(error("chapters", "必须包含 1-100 个章节"));
        }
        Set<Integer> chapterOrders = new HashSet<>();
        Set<String> memoryIds = new HashSet<>();
        if (chapters.isArray()) for (int i = 0; i < chapters.size(); i++) {
            JsonNode chapter = chapters.get(i);
            String path = "chapters[" + i + "]";
            if (!chapter.isObject()) { errors.add(error(path, "章节必须是对象")); continue; }
            requiredText(chapter, "id", 1, 128, errors, path + ".id");
            requiredText(chapter, "title", 1, 200, errors, path + ".title");
            int order = chapter.path("order").asInt(Integer.MIN_VALUE);
            if (order == Integer.MIN_VALUE || order < 1) errors.add(error(path + ".order", "章节 order 必须是正整数"));
            if (!chapterOrders.add(order)) errors.add(error(path + ".order", "章节 order 不能重复"));
            JsonNode memories = chapter.path("memories");
            if (!memories.isArray() || memories.isEmpty() || memories.size() > 500) {
                errors.add(error(path + ".memories", "必须包含 1-500 个记忆点")); continue;
            }
            for (int j = 0; j < memories.size(); j++) {
                JsonNode memory = memories.get(j);
                String memoryPath = path + ".memories[" + j + "]";
                if (!memory.isObject()) { errors.add(error(memoryPath, "记忆点必须是对象")); continue; }
                String id = text(memory, "id");
                if (id == null || id.length() < 1 || id.length() > 128 || !memoryIds.add(id)) {
                    errors.add(error(memoryPath + ".id", "记忆点 ID 必须存在且全局唯一"));
                }
                if (memory.path("order").asInt(Integer.MIN_VALUE) < 1) {
                    errors.add(error(memoryPath + ".order", "记忆点 order 必须是正整数"));
                }
                String content = text(memory, "content");
                if (content == null || content.isBlank() || content.length() > 20000) {
                    errors.add(error(memoryPath + ".content", "正文必须为 1-20000 字符"));
                }
            }
        }
        if (memoryIds.size() > 5000) errors.add(error("chapters", "记忆点总数不能超过 5000"));
        if (!errors.isEmpty()) throw invalid(errors);
    }

    private void requiredText(JsonNode root, String field, int min, int max, List<ApiErrorResponse.ErrorDetail> errors) {
        requiredText(root, field, min, max, errors, field);
    }

    private void requiredText(JsonNode root, String field, int min, int max, List<ApiErrorResponse.ErrorDetail> errors, String path) {
        String value = text(root, field);
        if (value == null || value.length() < min || value.length() > max) errors.add(error(path, "长度必须为 " + min + "-" + max));
    }

    private String text(JsonNode node, String field) {
        JsonNode value = node.get(field);
        return value == null || !value.isTextual() ? null : value.asText().trim();
    }

    private ApiErrorResponse.ErrorDetail error(String field, String reason) { return new ApiErrorResponse.ErrorDetail(field, reason); }
    private ApiException invalid(List<ApiErrorResponse.ErrorDetail> errors) {
        return new ApiException(HttpStatus.BAD_REQUEST, "STORY_INVALID", "故事 JSON 校验失败", errors);
    }
}

package com.aichat.server.story;

import java.util.List;

public record StoryCatalogEntry(
        String storyId,
        int version,
        String title,
        String author,
        String summary,
        List<String> tags,
        String file,
        Long downloadCount,
        String updatedAt) {
    public StoryCatalogEntry {
        tags = tags == null ? List.of() : List.copyOf(tags);
    }
}

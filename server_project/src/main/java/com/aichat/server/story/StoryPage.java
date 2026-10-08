package com.aichat.server.story;

import java.util.List;

public record StoryPage(List<StoryCatalogEntry> items, String nextCursor, boolean hasMore) {
    public StoryPage {
        items = items == null ? List.of() : List.copyOf(items);
    }
}

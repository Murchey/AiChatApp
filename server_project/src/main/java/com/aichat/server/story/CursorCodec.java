package com.aichat.server.story;

import com.aichat.server.common.ApiException;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
public class CursorCodec {
    public record Cursor(String updatedAt, String id) {}

    public String encode(String updatedAt, String id) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString((updatedAt + "\n" + id).getBytes(StandardCharsets.UTF_8));
    }

    public Cursor decode(String value) {
        if (value == null || value.isBlank()) return null;
        try {
            String decoded = new String(Base64.getUrlDecoder().decode(value), StandardCharsets.UTF_8);
            String[] parts = decoded.split("\\n", 2);
            if (parts.length != 2 || parts[0].isBlank() || parts[1].isBlank()) throw new IllegalArgumentException();
            return new Cursor(parts[0], parts[1]);
        } catch (IllegalArgumentException exception) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_CURSOR", "分页游标无效");
        }
    }
}

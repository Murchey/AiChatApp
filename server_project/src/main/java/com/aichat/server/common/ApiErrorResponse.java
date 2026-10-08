package com.aichat.server.common;

import java.util.List;

public record ApiErrorResponse(ErrorBody error) {
    public record ErrorBody(
            String code,
            String message,
            List<ErrorDetail> details,
            String requestId) {
    }

    public record ErrorDetail(String field, String reason) {
    }
}

package com.aichat.server.common;

import org.springframework.http.HttpStatus;
import java.util.List;

public class ApiException extends RuntimeException {
    private final HttpStatus status;
    private final String code;
    private final List<ApiErrorResponse.ErrorDetail> details;
    private Integer retryAfterSeconds;

    public ApiException(HttpStatus status, String code, String message) {
        this(status, code, message, List.of());
    }

    public ApiException(HttpStatus status, String code, String message,
                        List<ApiErrorResponse.ErrorDetail> details) {
        super(message);
        this.status = status;
        this.code = code;
        this.details = details == null ? List.of() : List.copyOf(details);
    }

    public HttpStatus getStatus() { return status; }
    public String getCode() { return code; }
    public List<ApiErrorResponse.ErrorDetail> getDetails() { return details; }
    public Integer getRetryAfterSeconds(){return retryAfterSeconds;}
    public ApiException retryAfter(int seconds){retryAfterSeconds=Math.max(1,Math.min(seconds,86400));return this;}
}

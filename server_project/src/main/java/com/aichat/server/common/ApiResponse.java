package com.aichat.server.common;

public record ApiResponse<T>(T data, String requestId) {
}

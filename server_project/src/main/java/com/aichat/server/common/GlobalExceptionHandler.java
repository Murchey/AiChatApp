package com.aichat.server.common;

import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ApiErrorResponse> api(ApiException exception, HttpServletRequest request) {
        var result=response(exception.getStatus(), exception.getCode(), exception.getMessage(), exception.getDetails(), request);
        if(exception.getRetryAfterSeconds()!=null)return ResponseEntity.status(exception.getStatus()).header("Retry-After",exception.getRetryAfterSeconds().toString()).body(result.getBody());
        return result;
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiErrorResponse> validation(
            MethodArgumentNotValidException exception,
            HttpServletRequest request) {
        List<ApiErrorResponse.ErrorDetail> details = exception.getBindingResult()
                .getFieldErrors()
                .stream()
                .map(error -> new ApiErrorResponse.ErrorDetail(error.getField(), error.getDefaultMessage()))
                .toList();
        return response(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "请求参数无效", details, request);
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ApiErrorResponse> malformedJson(
            HttpMessageNotReadableException exception,
            HttpServletRequest request) {
        return response(HttpStatus.BAD_REQUEST, "MALFORMED_JSON", "请求 JSON 无法解析", List.of(), request);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiErrorResponse> unexpected(
            Exception exception,
            HttpServletRequest request) {
        return response(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", "服务器内部错误", List.of(), request);
    }

    private ResponseEntity<ApiErrorResponse> response(
            HttpStatus status,
            String code,
            String message,
            List<ApiErrorResponse.ErrorDetail> details,
            HttpServletRequest request) {
        var body = new ApiErrorResponse(new ApiErrorResponse.ErrorBody(
                code, message, details, RequestIdFilter.from(request)));
        return ResponseEntity.status(status).body(body);
    }
}

package com.aichat.server.common;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.UUID;
import java.util.regex.Pattern;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
@org.springframework.core.annotation.Order(0)
public class RequestIdFilter extends OncePerRequestFilter {
    public static final String ATTRIBUTE = RequestIdFilter.class.getName() + ".requestId";
    private static final Pattern SAFE_ID = Pattern.compile("[A-Za-z0-9._-]{1,80}");

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {
        String incoming = request.getHeader("X-Request-Id");
        String requestId = incoming != null && SAFE_ID.matcher(incoming).matches()
                ? incoming
                : "req_" + UUID.randomUUID().toString().replace("-", "");
        request.setAttribute(ATTRIBUTE, requestId);
        response.setHeader("X-Request-Id", requestId);
        filterChain.doFilter(request, response);
    }

    public static String from(HttpServletRequest request) {
        Object value = request.getAttribute(ATTRIBUTE);
        return value == null ? "req_unknown" : value.toString();
    }
}

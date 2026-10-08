package com.aichat.server.auth;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
public class AuthFilter extends OncePerRequestFilter {
    private final TokenService tokens;

    public AuthFilter(TokenService tokens) {
        this.tokens = tokens;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getRequestURI();
        return path.equals("/api/health") || path.equals("/api/version")
                || path.equals("/api/invite/exchange") || path.startsWith("/actuator/");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        if (header != null && header.regionMatches(true, 0, "Bearer ", 0, 7)) {
            CurrentDevice device = tokens.authenticate(header.substring(7).trim());
            if (device != null) request.setAttribute(CurrentDevice.REQUEST_ATTRIBUTE, device);
        }
        chain.doFilter(request, response);
    }
}

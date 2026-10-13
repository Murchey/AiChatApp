package com.aichat.server.auth.web;

import com.aichat.server.auth.*;
import com.aichat.server.common.ApiResponse;
import com.aichat.server.common.RequestIdFilter;
import jakarta.servlet.http.HttpServletRequest;
import java.util.LinkedHashMap;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/auth")
public class AccountController {
    public record Credentials(String username, String password) {}
    private final AccountService accounts;
    private final SimpleRateLimiter limiter;
    public AccountController(AccountService accounts, SimpleRateLimiter limiter) { this.accounts=accounts; this.limiter=limiter; }
    @PostMapping("/register")
    public ApiResponse<?> register(@RequestBody Credentials body,HttpServletRequest request) {
        limiter.check("account-register:"+request.getRemoteAddr(),5,60);
        return response(accounts.register(body.username(),body.password()),request);
    }
    @PostMapping("/login")
    public ApiResponse<?> login(@RequestBody Credentials body,HttpServletRequest request) {
        limiter.check("account-login:"+request.getRemoteAddr(),10,60);
        return response(accounts.login(body.username(),body.password()),request);
    }
    @GetMapping("/me")
    public ApiResponse<?> me(HttpServletRequest request) {
        Object value=request.getAttribute(CurrentDevice.REQUEST_ATTRIBUTE);
        return new ApiResponse<>(accounts.me(value instanceof CurrentDevice device?device:null),RequestIdFilter.from(request));
    }
    private ApiResponse<?> response(AccountService.Session session,HttpServletRequest request) {
        var data=new LinkedHashMap<String,Object>();
        data.put("userId",session.account().userId()); data.put("username",session.account().username()); data.put("deviceId",session.account().deviceId());
        var pair=session.tokens();
        data.put("accessToken",pair.accessToken()); data.put("refreshToken",pair.refreshToken());
        data.put("accessExpiresAt",pair.accessExpiresAt()); data.put("refreshExpiresAt",pair.refreshExpiresAt());
        return new ApiResponse<>(data,RequestIdFilter.from(request));
    }
}

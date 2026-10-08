package com.aichat.server.auth;

import com.aichat.server.common.ApiException;
import com.aichat.server.config.AppProperties;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.HexFormat;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class TokenService {
    public record TokenPair(String accessToken, String refreshToken, Instant accessExpiresAt, Instant refreshExpiresAt) {}

    private final DeviceRepository devices;
    private final RefreshTokenRepository refreshTokens;
    private final AppProperties properties;
    private final SecureRandom random = new SecureRandom();
    private final Clock clock = Clock.systemUTC();

    public TokenService(DeviceRepository devices, RefreshTokenRepository refreshTokens, AppProperties properties) {
        this.devices = devices;
        this.refreshTokens = refreshTokens;
        this.properties = properties;
    }

    @Transactional
    public TokenPair issue(String deviceId, String role, String label, Instant now) {
        String access = randomToken();
        String refresh = randomToken();
        Instant accessExpiry = now.plus(safeAccessMinutes(), ChronoUnit.MINUTES);
        Instant refreshExpiry = now.plus(safeRefreshDays(), ChronoUnit.DAYS);
        if (devices.exists(deviceId)) {
            devices.rotateAccess(deviceId, hash(access), now, accessExpiry);
        } else {
            devices.insert(deviceId, label, hash(access), role, now, accessExpiry);
        }
        refreshTokens.insert(deviceId, hash(refresh), refreshExpiry, now);
        return new TokenPair(access, refresh, accessExpiry, refreshExpiry);
    }

    @Transactional
    public TokenPair rotate(String refreshToken) {
        Instant now = clock.instant();
        RefreshTokenRepository.Stored stored = refreshTokens.findByHash(hash(refreshToken))
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_REFRESH_TOKEN", "刷新令牌无效或已过期"));
        if (!stored.activeAt(now)) {
            refreshTokens.revokeForDevice(stored.deviceId(), now);
            throw new ApiException(HttpStatus.UNAUTHORIZED, "REFRESH_REPLAY", "刷新令牌已失效，设备会话已撤销");
        }
        CurrentDevice device = devices.findById(stored.deviceId())
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "DEVICE_REVOKED", "设备已撤销"));
        String access = randomToken();
        String refresh = randomToken();
        Instant accessExpiry = now.plus(safeAccessMinutes(), ChronoUnit.MINUTES);
        Instant refreshExpiry = now.plus(safeRefreshDays(), ChronoUnit.DAYS);
        devices.rotateAccess(device.id(), hash(access), now, accessExpiry);
        String nextId = refreshTokens.insert(device.id(), hash(refresh), refreshExpiry, now);
        refreshTokens.revoke(stored.id(), now, nextId);
        return new TokenPair(access, refresh, accessExpiry, refreshExpiry);
    }

    public CurrentDevice authenticate(String accessToken) {
        if (accessToken == null || accessToken.isBlank()) return null;
        Instant now = clock.instant();
        CurrentDevice device = devices.findByAccessHash(hash(accessToken), now).orElse(null);
        if (device != null) devices.touch(device.id(), now);
        return device;
    }

    public void revoke(String deviceId) {
        Instant now = clock.instant();
        devices.revoke(deviceId, now);
        refreshTokens.revokeForDevice(deviceId, now);
    }

    public String hash(String value) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest((value + properties.getSecurity().getTokenPepper())
                    .getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 unavailable", exception);
        }
    }

    private String randomToken() {
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private int safeAccessMinutes() { return Math.max(1, Math.min(24 * 60, properties.getSecurity().getAccessTokenMinutes())); }
    private int safeRefreshDays() { return Math.max(1, Math.min(365, properties.getSecurity().getRefreshTokenDays())); }
}

package com.aichat.server.auth;

import com.aichat.server.common.ApiException;
import java.time.Clock;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
public class SimpleRateLimiter {
    private record Bucket(Instant startedAt, AtomicInteger count) {}
    private final Map<String, Bucket> buckets = new ConcurrentHashMap<>();
    private final Clock clock = Clock.systemUTC();

    public void check(String key, int limit, long windowSeconds) {
        Instant now = clock.instant();
        Bucket bucket = buckets.compute(key, (ignored, old) -> {
            if (old == null || old.startedAt().plusSeconds(windowSeconds).isBefore(now)) return new Bucket(now, new AtomicInteger(1));
            old.count().incrementAndGet();
            return old;
        });
        if (bucket.count().get() > limit) {
            throw new ApiException(HttpStatus.TOO_MANY_REQUESTS, "RATE_LIMITED", "请求过于频繁，请稍后再试")
                .retryAfter((int)Math.max(1,java.time.Duration.between(now,bucket.startedAt().plusSeconds(windowSeconds)).toSeconds()));
        }
    }
}

package com.aichat.server.system;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

@SpringBootTest
@ActiveProfiles("test")
class MigrationSmokeTest {
    private static String databaseUrl;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @BeforeAll
    static void createDatabaseUrl() {
        databaseUrl = "jdbc:sqlite:file:aichat_m0_migration_" + UUID.randomUUID().toString().replace("-", "")
                + "?mode=memory&cache=shared";
    }

    @DynamicPropertySource
    static void databaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", () -> databaseUrl);
    }

    @Test
    void baselineCreatesCoreTables() {
        Integer tableCount = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name IN "
                        + "('device', 'invite_code', 'story', 'story_version', 'story_tag', 'admin_audit_log')",
                Integer.class);
        assertThat(tableCount).isEqualTo(6);
    }
}

package com.aichat.server.system;

import static org.assertj.core.api.Assertions.assertThat;
import java.sql.DriverManager;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;

class IncrementalMigrationTest {
    @Test void previousDatabaseUpgradesWithoutLosingPublishedStory() throws Exception {
        String url="jdbc:sqlite:file:migration_"+UUID.randomUUID()+"?mode=memory&cache=shared";
        try(var keeper=DriverManager.getConnection(url)) {
            Flyway.configure().dataSource(url,null,null).target("2").load().migrate();
            try(var sql=keeper.createStatement()) {
                sql.executeUpdate("INSERT INTO story(id,slug,title,status,current_version,created_at,updated_at) VALUES('previous','previous','existing','PUBLISHED',1,'2026-10-08T00:00:00Z','2026-10-08T00:00:00Z')");
            }
            Flyway.configure().dataSource(url,null,null).load().migrate();
            try(var sql=keeper.createStatement(); var row=sql.executeQuery("SELECT title,current_version FROM story WHERE id='previous'")) {
                assertThat(row.next()).isTrue(); assertThat(row.getString(1)).isEqualTo("existing"); assertThat(row.getInt(2)).isEqualTo(1);
            }
            try(var sql=keeper.createStatement(); var row=sql.executeQuery("SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('story_draft','admin_publish_result','sync_scope','sync_object','sync_write_result','comment','report','comment_request_result','sync_space','sync_space_member','sync_space_invite','sync_shared_scope','sync_shared_object','sync_shared_write_result')")) {
                assertThat(row.getInt(1)).isEqualTo(14);
            }
            Flyway.configure().dataSource(url,null,null).load().validate();
        }
    }
    @Test void commentParentConstraintsAndVisibilitySurviveFileDatabaseRestart()throws Exception{
        var file=java.nio.file.Files.createTempFile("aichat-m7-restart-",".sqlite");
        String url="jdbc:sqlite:"+file;
        try{
            Flyway.configure().dataSource(url,null,null).load().migrate();
            try(var connection=DriverManager.getConnection(url);var sql=connection.createStatement()){
                sql.execute("PRAGMA foreign_keys=ON");
                sql.executeUpdate("INSERT INTO device(id,label,role,status,token_hash,created_at,updated_at) VALUES('d','','USER','ACTIVE','hash','now','now')");
                sql.executeUpdate("INSERT INTO story(id,slug,title,status,current_version,created_at,updated_at) VALUES('s','s','test','PUBLISHED',1,'now','now')");
                sql.executeUpdate("INSERT INTO comment(id,story_id,story_version,author_device_id,body,status,public_visibility,created_at,updated_at) VALUES('p','s',1,'d','original','VISIBLE',1,'now','now')");
                sql.executeUpdate("INSERT INTO comment(id,story_id,story_version,parent_id,author_device_id,body,status,created_at,updated_at) VALUES('r','s',1,'p','d','reply','PENDING','now','now')");
                org.assertj.core.api.Assertions.assertThatThrownBy(()->sql.executeUpdate("INSERT INTO comment(id,story_id,story_version,parent_id,author_device_id,body,status,created_at,updated_at) VALUES('deep','s',1,'r','d','reply','PENDING','now','now')")).isInstanceOf(java.sql.SQLException.class);
                sql.executeUpdate("UPDATE comment SET status='DELETED' WHERE id='p'");
            }
            Flyway.configure().dataSource(url,null,null).load().validate();
            try(var connection=DriverManager.getConnection(url);var sql=connection.createStatement();var row=sql.executeQuery("SELECT body,status,public_visibility FROM comment WHERE id='p'")){
                assertThat(row.next()).isTrue();assertThat(row.getString(1)).isEqualTo("original");assertThat(row.getString(2)).isEqualTo("DELETED");assertThat(row.getInt(3)).isEqualTo(1);
            }
        }finally{java.nio.file.Files.deleteIfExists(file);}
    }
}

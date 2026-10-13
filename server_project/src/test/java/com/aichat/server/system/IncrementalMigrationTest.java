package com.aichat.server.system;

import static org.assertj.core.api.Assertions.assertThat;
import java.sql.DriverManager;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;

class IncrementalMigrationTest {
    @Test void accountMigrationKeepsLegacyContentAndDeviceIdentity() throws Exception {
        String url="jdbc:sqlite:file:account_upgrade_"+UUID.randomUUID()+"?mode=memory&cache=shared";
        try(var keeper=DriverManager.getConnection(url)) {
            Flyway.configure().dataSource(url,null,null).initSql("PRAGMA foreign_keys=ON").target("9").load().migrate();
            try(var sql=keeper.createStatement()) {
                sql.execute("PRAGMA foreign_keys=ON");
                sql.executeUpdate("INSERT INTO device(id,role,token_hash,created_at,updated_at) VALUES('legacy','ADMIN','old-hash','now','now')");
                sql.executeUpdate("INSERT INTO story(id,slug,title,status,current_version,created_at,updated_at) VALUES('s','s','story','PUBLISHED',1,'now','now')");
                sql.executeUpdate("INSERT INTO character_card(id,title,current_version,created_at,updated_at) VALUES('c','character',1,'now','now')");
                sql.executeUpdate("INSERT INTO character_version VALUES('c',1,X'010203','sha','now')");
                sql.executeUpdate("INSERT INTO comment(id,character_id,story_version,author_device_id,body,created_at,updated_at) VALUES('p','c',1,'legacy','comment','now','now')");
                sql.executeUpdate("INSERT INTO report(id,comment_id,reporter_device_id,reason_code,created_at) VALUES('r','p','legacy','SPAM','now')");
            }
            Flyway.configure().dataSource(url,null,null).initSql("PRAGMA foreign_keys=ON").load().migrate();
            try(var sql=keeper.createStatement()) {
                try(var rows=sql.executeQuery("SELECT role,token_hash,account_id FROM device WHERE id='legacy'")) {
                    assertThat(rows.next()).isTrue(); assertThat(rows.getString(1)).isEqualTo("ADMIN");
                    assertThat(rows.getString(2)).isEqualTo("old-hash"); assertThat(rows.getString(3)).isNull();
                }
                try(var rows=sql.executeQuery("SELECT s.title,c.title,v.package_zip,p.body,r.comment_id FROM story s,character_card c JOIN character_version v ON v.character_id=c.id JOIN comment p ON p.character_id=c.id JOIN report r ON r.comment_id=p.id")) {
                    assertThat(rows.next()).isTrue(); assertThat(rows.getString(1)).isEqualTo("story");
                    assertThat(rows.getString(2)).isEqualTo("character"); assertThat(rows.getBytes(3)).containsExactly(1,2,3);
                    assertThat(rows.getString(4)).isEqualTo("comment"); assertThat(rows.getString(5)).isEqualTo("p");
                }
                try(var rows=sql.executeQuery("SELECT count(*) FROM user_account")){assertThat(rows.getInt(1)).isZero();}
                try(var rows=sql.executeQuery("PRAGMA foreign_key_check")){assertThat(rows.next()).isFalse();}
            }
        }
    }
    @Test void characterMigrationPreservesExistingRepliesAndReportsWithForeignKeysEnabled() throws Exception {
        String url="jdbc:sqlite:file:character_upgrade_"+UUID.randomUUID()+"?mode=memory&cache=shared";
        try(var keeper=DriverManager.getConnection(url)) {
            Flyway.configure().dataSource(url,null,null).initSql("PRAGMA foreign_keys=ON").target("8").load().migrate();
            try(var sql=keeper.createStatement()) {
                sql.execute("PRAGMA foreign_keys=ON");
                sql.executeUpdate("INSERT INTO device(id,token_hash,created_at,updated_at) VALUES('d','hash','now','now')");
                sql.executeUpdate("INSERT INTO story(id,slug,title,status,current_version,created_at,updated_at) VALUES('s','s','story','PUBLISHED',1,'now','now')");
                sql.executeUpdate("INSERT INTO comment(id,story_id,story_version,author_device_id,body,status,public_visibility,created_at,updated_at) VALUES('p','s',1,'d','old text','VISIBLE',1,'now','now')");
                sql.executeUpdate("INSERT INTO comment(id,story_id,story_version,parent_id,author_device_id,body,created_at,updated_at) VALUES('r','s',1,'p','d','reply','now','now')");
                sql.executeUpdate("INSERT INTO report(id,comment_id,reporter_device_id,reason_code,created_at) VALUES('report','p','d','SPAM','now')");
            }
            Flyway.configure().dataSource(url,null,null).initSql("PRAGMA foreign_keys=ON").load().migrate();
            try(var sql=keeper.createStatement()) {
                try(var rows=sql.executeQuery("SELECT body,public_visibility FROM comment WHERE id='p'")){assertThat(rows.next()).isTrue();assertThat(rows.getString(1)).isEqualTo("old text");assertThat(rows.getInt(2)).isEqualTo(1);}
                try(var rows=sql.executeQuery("SELECT parent_id FROM comment WHERE id='r'")){assertThat(rows.next()).isTrue();assertThat(rows.getString(1)).isEqualTo("p");}
                try(var rows=sql.executeQuery("SELECT comment_id FROM report WHERE id='report'")){assertThat(rows.next()).isTrue();assertThat(rows.getString(1)).isEqualTo("p");}
                try(var rows=sql.executeQuery("PRAGMA foreign_key_check")){assertThat(rows.next()).isFalse();}
            }
        }
    }
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

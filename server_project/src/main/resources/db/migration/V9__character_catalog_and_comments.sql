CREATE TABLE character_card (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    author_name TEXT NOT NULL DEFAULT '',
    summary TEXT NOT NULL DEFAULT '',
    current_version INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX idx_character_updated ON character_card(updated_at DESC,id DESC);
CREATE TABLE character_version (
    character_id TEXT NOT NULL REFERENCES character_card(id),
    version INTEGER NOT NULL,
    package_zip BLOB NOT NULL,
    content_sha256 TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY(character_id,version)
);

-- Keep existing comment IDs, visibility, reports and reply relationships.
-- A comment belongs to exactly one content item.
CREATE TABLE comment_new (
    id TEXT PRIMARY KEY,
    story_id TEXT REFERENCES story(id),
    character_id TEXT REFERENCES character_card(id),
    story_version INTEGER NOT NULL,
    parent_id TEXT REFERENCES comment_new(id),
    author_device_id TEXT NOT NULL REFERENCES device(id),
    body TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','VISIBLE','HIDDEN','DELETED')),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    public_visibility INTEGER NOT NULL DEFAULT 0 CHECK(public_visibility IN (0,1)),
    CHECK ((story_id IS NOT NULL AND character_id IS NULL) OR (story_id IS NULL AND character_id IS NOT NULL))
);
INSERT INTO comment_new(id,story_id,story_version,parent_id,author_device_id,body,status,created_at,updated_at,deleted_at,public_visibility)
SELECT id,story_id,story_version,parent_id,author_device_id,body,status,created_at,updated_at,deleted_at,public_visibility FROM comment;
CREATE TABLE report_new (
    id TEXT PRIMARY KEY,
    comment_id TEXT NOT NULL REFERENCES comment_new(id),
    reporter_device_id TEXT NOT NULL REFERENCES device(id),
    reason_code TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'PENDING',
    created_at TEXT NOT NULL
);
INSERT INTO report_new SELECT * FROM report;
DROP TABLE report;
DROP TABLE comment;
ALTER TABLE comment_new RENAME TO comment;
ALTER TABLE report_new RENAME TO report;
CREATE UNIQUE INDEX idx_pending_report ON report(comment_id,reporter_device_id) WHERE status='PENDING';
CREATE INDEX idx_comment_story_status_created ON comment(story_id,status,created_at DESC,id DESC);
CREATE INDEX idx_comment_character_status_created ON comment(character_id,status,created_at DESC,id DESC);
CREATE TRIGGER comment_parent_insert BEFORE INSERT ON comment
WHEN NEW.parent_id IS NOT NULL
BEGIN
  SELECT RAISE(ABORT,'invalid comment parent') WHERE NOT EXISTS (
    SELECT 1 FROM comment p WHERE p.id=NEW.parent_id AND p.story_id IS NEW.story_id
      AND p.character_id IS NEW.character_id AND p.parent_id IS NULL
  );
END;
CREATE TRIGGER comment_parent_update BEFORE UPDATE OF parent_id,story_id,character_id ON comment
BEGIN
  SELECT RAISE(ABORT,'comment parent and content are immutable')
    WHERE NEW.parent_id IS NOT OLD.parent_id OR NEW.story_id IS NOT OLD.story_id
      OR NEW.character_id IS NOT OLD.character_id;
END;

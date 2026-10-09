CREATE TABLE comment (
    id TEXT PRIMARY KEY,
    story_id TEXT NOT NULL,
    story_version INTEGER NOT NULL,
    parent_id TEXT,
    author_device_id TEXT NOT NULL,
    body TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','VISIBLE','HIDDEN','DELETED')),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    FOREIGN KEY(story_id) REFERENCES story(id),
    FOREIGN KEY(parent_id) REFERENCES comment(id),
    FOREIGN KEY(author_device_id) REFERENCES device(id)
);
CREATE INDEX idx_comment_story_status_created ON comment(story_id,status,created_at DESC,id DESC);
CREATE TABLE report (
    id TEXT PRIMARY KEY,
    comment_id TEXT NOT NULL,
    reporter_device_id TEXT NOT NULL,
    reason_code TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'PENDING',
    created_at TEXT NOT NULL,
    FOREIGN KEY(comment_id) REFERENCES comment(id),
    FOREIGN KEY(reporter_device_id) REFERENCES device(id)
);
CREATE UNIQUE INDEX idx_pending_report ON report(comment_id,reporter_device_id) WHERE status='PENDING';
CREATE TABLE comment_request_result (
    device_id TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    signature TEXT NOT NULL,
    response_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY(device_id,idempotency_key)
);

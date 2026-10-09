CREATE TABLE story_draft (
    story_id TEXT PRIMARY KEY,
    base_version INTEGER NOT NULL DEFAULT 0,
    revision INTEGER NOT NULL DEFAULT 1,
    draft_json TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'DRAFT',
    validated_revision INTEGER,
    author_device_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE TABLE admin_publish_result (
    actor_id TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    request_hash TEXT NOT NULL,
    response_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY(actor_id, idempotency_key)
);

CREATE TABLE IF NOT EXISTS device (
    id TEXT PRIMARY KEY,
    label TEXT NOT NULL DEFAULT '',
    token_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'USER',
    status TEXT NOT NULL DEFAULT 'ACTIVE',
    last_seen_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_device_status_seen
    ON device(status, last_seen_at);

CREATE TABLE IF NOT EXISTS invite_code (
    id TEXT PRIMARY KEY,
    code_hash TEXT NOT NULL UNIQUE,
    max_uses INTEGER NOT NULL DEFAULT 1,
    used_count INTEGER NOT NULL DEFAULT 0,
    expires_at TEXT,
    status TEXT NOT NULL DEFAULT 'ACTIVE',
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS story (
    id TEXT PRIMARY KEY,
    slug TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL,
    author_name TEXT NOT NULL DEFAULT '',
    summary TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'DRAFT',
    current_version INTEGER,
    download_count INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_story_status_updated
    ON story(status, updated_at DESC);

CREATE TABLE IF NOT EXISTS story_version (
    id TEXT PRIMARY KEY,
    story_id TEXT NOT NULL,
    version INTEGER NOT NULL,
    content_json TEXT NOT NULL,
    content_sha256 TEXT NOT NULL,
    content_size INTEGER NOT NULL,
    schema_version INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'DRAFT',
    published_at TEXT,
    created_at TEXT NOT NULL,
    UNIQUE(story_id, version),
    FOREIGN KEY(story_id) REFERENCES story(id)
);

CREATE INDEX IF NOT EXISTS idx_story_version_story_version
    ON story_version(story_id, version DESC);

CREATE TABLE IF NOT EXISTS story_tag (
    story_id TEXT NOT NULL,
    tag TEXT NOT NULL,
    PRIMARY KEY(story_id, tag),
    FOREIGN KEY(story_id) REFERENCES story(id)
);

CREATE INDEX IF NOT EXISTS idx_story_tag_tag_story
    ON story_tag(tag, story_id);

CREATE TABLE IF NOT EXISTS admin_audit_log (
    id TEXT PRIMARY KEY,
    actor_device_id TEXT,
    action TEXT NOT NULL,
    resource_type TEXT NOT NULL,
    resource_id TEXT,
    request_id TEXT,
    metadata_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL,
    FOREIGN KEY(actor_device_id) REFERENCES device(id)
);

CREATE INDEX IF NOT EXISTS idx_audit_actor_created
    ON admin_audit_log(actor_device_id, created_at DESC);

CREATE TABLE sync_space (
    id TEXT PRIMARY KEY,
    owner_device_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY(owner_device_id) REFERENCES device(id)
);
CREATE TABLE sync_space_member (
    space_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    role TEXT NOT NULL CHECK(role IN ('OWNER','MEMBER')),
    created_at TEXT NOT NULL,
    PRIMARY KEY(space_id,device_id),
    FOREIGN KEY(space_id) REFERENCES sync_space(id),
    FOREIGN KEY(device_id) REFERENCES device(id)
);
CREATE TABLE sync_space_invite (
    id TEXT PRIMARY KEY,
    space_id TEXT NOT NULL,
    code_hash TEXT NOT NULL UNIQUE,
    max_uses INTEGER NOT NULL DEFAULT 1,
    used_count INTEGER NOT NULL DEFAULT 0,
    expires_at TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY(space_id) REFERENCES sync_space(id)
);
CREATE INDEX idx_sync_space_member_device ON sync_space_member(device_id);
CREATE TABLE sync_shared_scope (
    space_id TEXT NOT NULL,
    domain TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL,
    PRIMARY KEY(space_id,domain),
    FOREIGN KEY(space_id) REFERENCES sync_space(id)
);
CREATE TABLE sync_shared_object (
    space_id TEXT NOT NULL,
    domain TEXT NOT NULL,
    revision INTEGER NOT NULL,
    content_sha256 TEXT NOT NULL,
    ciphertext TEXT NOT NULL,
    nonce TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    PRIMARY KEY(space_id,domain),
    FOREIGN KEY(space_id) REFERENCES sync_space(id)
);
CREATE TABLE sync_shared_write_result (
    space_id TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    request_hash TEXT NOT NULL,
    response_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY(space_id,idempotency_key)
);

ALTER TABLE device ADD COLUMN access_expires_at TEXT;

CREATE TABLE IF NOT EXISTS refresh_token (
    id TEXT PRIMARY KEY,
    device_id TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TEXT NOT NULL,
    revoked_at TEXT,
    replaced_by_id TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY(device_id) REFERENCES device(id)
);

CREATE INDEX IF NOT EXISTS idx_refresh_device_active
    ON refresh_token(device_id, revoked_at, expires_at);

CREATE TABLE IF NOT EXISTS idempotency_record (
    id TEXT PRIMARY KEY,
    device_id TEXT,
    route TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    response_json TEXT NOT NULL,
    status_code INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    UNIQUE(device_id, route, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_idempotency_expiry
    ON idempotency_record(expires_at);
